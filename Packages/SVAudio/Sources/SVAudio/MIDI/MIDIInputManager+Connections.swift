import CoreMIDI
import Foundation
import os

/// Signposter for Instruments profiling of MIDI input parsing.
private let midiSignposter = OSSignposter(subsystem: "com.survibe", category: "MIDIInput")

// MARK: - Source Refresh & Classification

extension MIDIInputManager {
    // MARK: - Source Refresh

    /// Re-enumerate physical CoreMIDI sources and connect to them.
    ///
    /// Safe to call from any thread. CoreMIDI operations (`MIDIGetSource`,
    /// `MIDIPortConnectSource`) are thread-safe. Observable UI state is
    /// updated via `Task { @MainActor in }` at the end.
    func refreshSources() {
        let (port, prevSources) = state.withLock { s in
            (s.inputPort, s.connectedSources)
        }

        let sourceCount = MIDIGetNumberOfSources()
        Self.logger.info("refreshSources: \(sourceCount) source(s) total")

        for source in prevSources {
            MIDIPortDisconnectSource(port, source)
        }

        guard sourceCount > 0, port != 0 else {
            state.withLock { s in s.connectedSources.removeAll() }
            connectionBox.yield(false)
            Task { @MainActor [weak self] in
                self?.isConnected = false
                self?.connectedDeviceName = nil
            }
            return
        }

        let (newSources, firstName) = enumerateAndConnectSources(
            count: sourceCount, port: port
        )

        state.withLock { s in s.connectedSources = newSources }

        let connected = !newSources.isEmpty
        let deviceName = firstName
        // Push state change to the connection stream immediately (on this CoreMIDI thread).
        connectionBox.yield(connected)
        Task { @MainActor [weak self] in
            self?.isConnected = connected
            self?.connectedDeviceName = deviceName
        }

        if connected {
            Self.logger.info("MIDI connected: \(deviceName ?? "unknown device", privacy: .public)")
        } else {
            Self.logger.info("No physical MIDI sources connected")
        }
    }

    /// Enumerate all CoreMIDI sources and connect physical ones to the port.
    private func enumerateAndConnectSources(
        count: Int, port: MIDIPortRef
    ) -> (sources: [MIDIEndpointRef], firstName: String?) {
        var newSources: [MIDIEndpointRef] = []
        var firstName: String?

        for i in 0..<count {
            let source = MIDIGetSource(i)
            guard source != 0 else { continue }

            guard Self.isPhysicalSource(source) else {
                Self.logger.info("Skipping virtual MIDI source \(i): \(Self.sourceName(source), privacy: .public)")
                continue
            }

            let connectStatus = MIDIPortConnectSource(port, source, nil)
            if connectStatus == noErr {
                newSources.append(source)
                if firstName == nil { firstName = Self.sourceName(source) }
                Self.logger.info("Connected to MIDI source \(i): \(Self.sourceName(source), privacy: .public)")
            } else {
                Self.logger.error(
                    "MIDIPortConnectSource failed for source \(i): OSStatus=\(connectStatus)"
                )
            }
        }

        return (newSources, firstName)
    }

    // MARK: - CoreMIDI Read Callback (static — runs on CoreMIDI thread)

    /// Parse a `MIDIEventList` (Universal MIDI Packets) and dispatch note events.
    ///
    /// Static method -- accesses no instance state. `box`, `callback`, and
    /// `deJitter` are all `Sendable` and protected by their own locks.
    ///
    /// Called from `MIDIInputPortCreateWithProtocol` on CoreMIDI's high-priority thread.
    ///
    /// ## Universal MIDI Packet (UMP) format -- MIDI 1.0 Channel Voice (message type 0x2)
    ///
    /// Each 32-bit word packs the MIDI message as big-endian bytes:
    ///   Bits [31:28] = UMP message type (0x2 = MIDI 1.0 Channel Voice)
    ///   Bits [27:24] = MIDI channel (0-15)
    ///   Bits [23:16] = status byte (0x80 Note-Off, 0x90 Note-On, etc.)
    ///   Bits [15:8]  = note number (0-127)
    ///   Bits [7:0]   = velocity (0-127)
    ///
    /// CoreMIDI automatically upgrades legacy MIDIPacketList sources to UMP when
    /// the port is created with `kMIDIProtocol_1_0`.
    ///
    /// ## MIDITimeStamp
    ///
    /// Each `MIDIEventPacket` carries a hardware-precise `timeStamp` field
    /// (host ticks from `mach_absolute_time`). We capture it into
    /// `MIDIInputEvent.midiTimestamp` for accurate play-along scoring.
    ///
    /// - Parameters:
    ///   - eventList: Pointer to the CoreMIDI event list.
    ///   - box: Continuation box for the AsyncStream note-on delivery path.
    ///   - callback: Direct low-latency callback box.
    ///   - deJitter: Filter that suppresses duplicate note-on events from switch bounce.
    static func parseEventList(
        _ eventList: UnsafePointer<MIDIEventList>,
        into box: ContinuationBox<MIDIInputEvent>,
        callback: NoteCallbackBox,
        ccCallback: CCCallbackBox,
        deJitter: MIDIDeJitterFilter
    ) {
        let count = Int(eventList.pointee.numPackets)
        guard count > 0 else { return }

        // Use withUnsafeMutablePointer on a mutable copy to safely advance through packets.
        var mutableList = eventList.pointee
        withUnsafeMutablePointer(to: &mutableList) { listPtr in
            var packetPtr = UnsafeMutablePointer<MIDIEventPacket>(&listPtr.pointee.packet)

            for _ in 0..<count {
                let packet = packetPtr.pointee
                let wordCount = Int(packet.wordCount)
                let hardwareTimestamp = packet.timeStamp

                parsePacketWords(
                    packet: packet, wordCount: wordCount,
                    hardwareTimestamp: hardwareTimestamp,
                    box: box, callback: callback,
                    ccCallback: ccCallback, deJitter: deJitter
                )

                packetPtr = MIDIEventPacketNext(packetPtr)
            }
        }
    }

    /// Parse UMP words from a single `MIDIEventPacket` and dispatch note events.
    ///
    /// - Parameters:
    ///   - packet: The raw event packet containing UMP words.
    ///   - wordCount: Number of 32-bit words in the packet.
    ///   - hardwareTimestamp: Hardware-precise timestamp from the packet.
    ///   - box: Continuation box for AsyncStream delivery.
    ///   - callback: Direct low-latency callback box.
    ///   - deJitter: Filter that suppresses duplicate note-on events from switch bounce.
    private static func parsePacketWords(
        packet: MIDIEventPacket,
        wordCount: Int,
        hardwareTimestamp: MIDITimeStamp,
        box: ContinuationBox<MIDIInputEvent>,
        callback: NoteCallbackBox,
        ccCallback: CCCallbackBox,
        deJitter: MIDIDeJitterFilter
    ) {
        let signpostID = midiSignposter.makeSignpostID()
        let signpostState = midiSignposter.beginInterval("UMPParsing", id: signpostID)

        withUnsafeBytes(of: packet.words) { rawWords in
            let words = rawWords.bindMemory(to: UInt32.self)
            var wordIndex = 0

            while wordIndex < wordCount {
                let word = words[wordIndex]
                wordIndex += 1

                // UMP message type is the top 4 bits of the 32-bit word.
                let umpMessageType = UInt8((word >> 28) & 0x0F)

                // 0x2 = MIDI 1.0 Channel Voice Message (single word).
                guard umpMessageType == 0x02 else { continue }

                let channel    = UInt8((word >> 24) & 0x0F)
                let statusByte = UInt8((word >> 16) & 0xFF)
                let noteNumber = UInt8((word >>  8) & 0x7F)
                let velocity   = UInt8(word & 0x7F)
                let messageType = statusByte & 0xF0

                switch messageType {
                case 0x90:  // Note-On (velocity=0 means Note-Off)
                    // De-jitter: suppress duplicate note-on within coalescence window.
                    if velocity > 0,
                       deJitter.shouldSuppress(note: noteNumber, timestamp: hardwareTimestamp)
                    {
                        continue
                    }
                    var token = ProbeToken()
                    token.stamp(.inputReceived)
                    let event = MIDIInputEvent(
                        noteNumber: noteNumber,
                        velocity: velocity,
                        channel: channel,
                        midiTimestamp: hardwareTimestamp,
                        probeToken: token
                    )
                    callback.fire(event)
                    box.yield(event)

                case 0x80:  // Note-Off (explicit)
                    var token = ProbeToken()
                    token.stamp(.inputReceived)
                    let event = MIDIInputEvent(
                        noteNumber: noteNumber,
                        velocity: 0,
                        channel: channel,
                        midiTimestamp: hardwareTimestamp,
                        probeToken: token
                    )
                    callback.fire(event)
                    box.yield(event)

                case 0xB0:  // Control Change
                    let ccEvent = MIDIControlChangeEvent(
                        controller: noteNumber,
                        value: velocity,
                        channel: channel,
                        midiTimestamp: hardwareTimestamp
                    )
                    ccCallback.fire(ccEvent)

                default:
                    break
                }
            }
        }

        midiSignposter.endInterval("UMPParsing", signpostState)
    }

    // MARK: - Source Classification

    /// Returns `true` if `endpoint` is a real physical MIDI device (USB or Bluetooth).
    ///
    /// Filters out IAC Driver, Network MIDI sessions, and offline devices.
    static func isPhysicalSource(_ endpoint: MIDIEndpointRef) -> Bool {
        let name = sourceName(endpoint).lowercased()
        let virtualKeywords = ["iac", "network session", "network midi", "virtual", "loopback"]
        if virtualKeywords.contains(where: { name.contains($0) }) {
            return false
        }

        var entity: MIDIEntityRef = 0
        guard MIDIEndpointGetEntity(endpoint, &entity) == noErr, entity != 0 else {
            return true
        }

        var device: MIDIDeviceRef = 0
        guard MIDIEntityGetDevice(entity, &device) == noErr, device != 0 else {
            return true
        }

        var offline: Int32 = 0
        MIDIObjectGetIntegerProperty(device, kMIDIPropertyOffline, &offline)
        return offline == 0
    }

    /// Return a human-readable display name for a MIDI endpoint.
    static func sourceName(_ endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        return (name?.takeRetainedValue() as String?) ?? "Unknown Device"
    }
}
