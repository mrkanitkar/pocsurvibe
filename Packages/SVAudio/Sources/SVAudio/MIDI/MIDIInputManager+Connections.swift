import AudioToolbox
import CoreMIDI
import Foundation
import os

/// Signposter for Instruments profiling of MIDI input parsing.
private let midiSignposter = OSSignposter(subsystem: "com.survibe", category: "MIDIInput")

/// Direct-wire a raw MIDI 1.0 byte triplet into the sampler's render
/// cycle via `AUAudioUnit.scheduleMIDIEventBlock`. RT-safe; callable
/// from CoreMIDI's high-priority thread.
///
/// Does nothing if the sampler has not been started (block is nil).
/// Apple documents this API as the lowest-latency path to inject MIDI
/// events into an AU music device. See spec §5.
@inline(__always)
private func scheduleToSampler(status: UInt8, data1: UInt8, data2: UInt8) {
    guard let schedule = samplerMIDIScheduleBlock else { return }
    // Cable 0 is the default virtual cable for single-endpoint messages.
    schedule(AUEventSampleTimeImmediate, 0, 3, [status, data1, data2])
}

// MARK: - Source Refresh & Classification

extension MIDIInputManager {
    // MARK: - Source Refresh

    /// Re-enumerate physical CoreMIDI sources and connect to them.
    ///
    /// Safe to call from any thread. CoreMIDI operations (`MIDIGetSource`,
    /// `MIDIPortConnectSource`) are thread-safe. Observable UI state is
    /// updated via `Task { @MainActor in }` at the end.
    func refreshSources() {
        // Refresh device inventory for multi-device management
        deviceManager.refreshDevices()

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
                Self.logEndpointProperties(source, tag: "MIDI-SRC")
            } else {
                Self.logger.error(
                    "MIDIPortConnectSource failed for source \(i): OSStatus=\(connectStatus)"
                )
            }
        }

        return (newSources, firstName)
    }

    // MARK: - CoreMIDI Read Callback (static — runs on CoreMIDI thread)

    /// Parse a `MIDIEventList` (Universal MIDI Packets) and dispatch events.
    ///
    /// Static method -- accesses no instance state. `box`, `callbacks`, and
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
    ///   - callbacks: Bundled callback boxes for all MIDI message types.
    ///   - deJitter: Filter that suppresses duplicate note-on events from switch bounce.
    ///   - router: Optional fan-out router for MIDI event consumers.
    static func parseEventList(
        _ eventList: UnsafePointer<MIDIEventList>,
        into box: ContinuationBox<MIDIInputEvent>,
        callbacks: MIDICallbackSet,
        deJitter: MIDIDeJitterFilter,
        router: MidiRouter? = nil
    ) {
        let count = Int(eventList.pointee.numPackets)
        guard count > 0 else { return }

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
                    box: box, callbacks: callbacks,
                    deJitter: deJitter,
                    router: router
                )

                packetPtr = MIDIEventPacketNext(packetPtr)
            }
        }
    }

    /// Legacy overload for backward compatibility with existing call sites.
    static func parseEventList(
        _ eventList: UnsafePointer<MIDIEventList>,
        into box: ContinuationBox<MIDIInputEvent>,
        callback: NoteCallbackBox,
        ccCallback: CCCallbackBox,
        deJitter: MIDIDeJitterFilter,
        router: MidiRouter? = nil
    ) {
        let set = MIDICallbackSet(note: callback, cc: ccCallback)
        parseEventList(eventList, into: box, callbacks: set, deJitter: deJitter, router: router)
    }

    // swiftlint:disable function_parameter_count

    /// Parse UMP words from a single `MIDIEventPacket` and dispatch events.
    ///
    /// Handles all MIDI 1.0 Channel Voice message types (0x80-0xE0) and
    /// dispatches MIDI 2.0 Channel Voice messages to `parseMIDI2ChannelVoice`.
    private static func parsePacketWords(
        packet: MIDIEventPacket,
        wordCount: Int,
        hardwareTimestamp: MIDITimeStamp,
        box: ContinuationBox<MIDIInputEvent>,
        callbacks: MIDICallbackSet,
        deJitter: MIDIDeJitterFilter,
        router: MidiRouter? = nil
    ) {
        let signpostID = midiSignposter.makeSignpostID()
        let signpostState = midiSignposter.beginInterval("UMPParsing", id: signpostID)

        withUnsafeBytes(of: packet.words) { rawWords in
            let words = rawWords.bindMemory(to: UInt32.self)
            var wordIndex = 0

            while wordIndex < wordCount {
                let word = words[wordIndex]
                wordIndex += 1

                let umpMessageType = UInt8((word >> 28) & 0x0F)

                // Handle MIDI 2.0 Channel Voice (type 0x4) — 64-bit, two words.
                if umpMessageType == 0x04, wordIndex < wordCount {
                    let word2 = words[wordIndex]
                    wordIndex += 1
                    parseMIDI2ChannelVoice(
                        word, word2: word2, timestamp: hardwareTimestamp,
                        box: box, callbacks: callbacks,
                        deJitter: deJitter, router: router
                    )
                    continue
                }

                // 0x2 = MIDI 1.0 Channel Voice Message (single word).
                guard umpMessageType == 0x02 else { continue }

                parseMIDI1ChannelVoice(
                    word, timestamp: hardwareTimestamp,
                    box: box, callbacks: callbacks,
                    deJitter: deJitter, router: router
                )
            }
        }

        midiSignposter.endInterval("UMPParsing", signpostState)
    }

    /// Parse a MIDI 1.0 Channel Voice word (UMP type 0x2, 32-bit).
    ///
    /// Handles note-on, note-off, CC, aftertouch, program change, and pitch bend.
    private static func parseMIDI1ChannelVoice(
        _ word: UInt32,
        timestamp: MIDITimeStamp,
        box: ContinuationBox<MIDIInputEvent>,
        callbacks: MIDICallbackSet,
        deJitter: MIDIDeJitterFilter,
        router: MidiRouter? = nil
    ) {
        let channel = UInt8((word >> 24) & 0x0F)
        let statusByte = UInt8((word >> 16) & 0xFF)
        let data1 = UInt8((word >> 8) & 0x7F)
        let data2 = UInt8(word & 0x7F)
        let messageType = statusByte & 0xF0

        switch messageType {
        case 0x90:  // Note-On (velocity=0 means Note-Off)
            if data2 > 0, deJitter.shouldSuppress(note: data1, timestamp: timestamp) { return }
            var token = ProbeToken()
            token.stamp(.inputReceived)
            let event = MIDIInputEvent(
                noteNumber: data1, velocity: data2,
                channel: channel, midiTimestamp: timestamp, probeToken: token
            )
            callbacks.note.fire(event)
            box.yield(event)
            router?.routeNote(event)
            // Direct-wire to sampler for sub-6 ms audible echo (spec §5).
            scheduleToSampler(status: statusByte, data1: data1, data2: data2)

        case 0x80:  // Note-Off (explicit)
            var token = ProbeToken()
            token.stamp(.inputReceived)
            let event = MIDIInputEvent(
                noteNumber: data1, velocity: 0,
                channel: channel, midiTimestamp: timestamp, probeToken: token
            )
            callbacks.note.fire(event)
            box.yield(event)
            router?.routeNote(event)
            scheduleToSampler(status: statusByte, data1: data1, data2: data2)

        case 0xB0:  // Control Change
            let ccEvent = MIDIControlChangeEvent(
                controller: data1, value: data2,
                channel: channel, midiTimestamp: timestamp
            )
            callbacks.cc.fire(ccEvent)
            router?.routeCC(ccEvent)

        case 0xA0:  // Polyphonic Key Pressure (Aftertouch)
            let pressureEvent = MIDIPressureEvent(
                noteNumber: data1, pressure: UInt32(data2) << 25,
                channel: channel, midiTimestamp: timestamp
            )
            callbacks.pressure.fire(pressureEvent)
            router?.routePressure(pressureEvent)

        case 0xC0:  // Program Change
            let pgmEvent = MIDIProgramChangeEvent(
                program: data1, channel: channel, midiTimestamp: timestamp
            )
            callbacks.programChange.fire(pgmEvent)
            router?.routeProgramChange(pgmEvent)

        case 0xD0:  // Channel Pressure (Aftertouch)
            let pressureEvent = MIDIPressureEvent(
                noteNumber: nil, pressure: UInt32(data1) << 25,
                channel: channel, midiTimestamp: timestamp
            )
            callbacks.pressure.fire(pressureEvent)
            router?.routePressure(pressureEvent)

        case 0xE0:  // Pitch Bend Change
            let bendValue = Int32(data2) << 7 | Int32(data1)
            let signedBend = Int32(bendValue) - 8192
            let bendEvent = MIDIPitchBendEvent(
                value: signedBend, channel: channel,
                midiTimestamp: timestamp, resolution: .midi1
            )
            callbacks.pitchBend.fire(bendEvent)
            router?.routePitchBend(bendEvent)

        default:
            break
        }
    }

    // swiftlint:enable function_parameter_count

    // swiftlint:disable function_parameter_count cyclomatic_complexity

    /// Parse a MIDI 2.0 Channel Voice message (UMP type 0x4, 64-bit).
    ///
    /// Handles note-on/off, CC, aftertouch, program change, and pitch bend.
    /// Controller and management messages are dispatched via `parseMIDI2Controller`.
    private static func parseMIDI2ChannelVoice(
        _ word1: UInt32,
        word2: UInt32,
        timestamp: MIDITimeStamp,
        box: ContinuationBox<MIDIInputEvent>,
        callbacks: MIDICallbackSet,
        deJitter: MIDIDeJitterFilter,
        router: MidiRouter? = nil
    ) {
        let channel = UInt8((word1 >> 24) & 0x0F)
        let statusNibble = UInt8((word1 >> 16) & 0xF0)
        let noteNumber = UInt8((word1 >> 8) & 0x7F)

        switch statusNibble {
        case 0x90:  // Note-On
            let velocity16 = UInt16((word2 >> 16) & 0xFFFF)
            let velocity = UInt8(velocity16 >> 9)
            if velocity > 0 {
                if deJitter.shouldSuppress(note: noteNumber, timestamp: timestamp) { return }
                var token = ProbeToken()
                token.stamp(.inputReceived)
                let event = MIDIInputEvent(
                    noteNumber: noteNumber, velocity: velocity,
                    channel: channel, midiTimestamp: timestamp,
                    probeToken: token, velocity16Bit: velocity16
                )
                callbacks.note.fire(event)
                box.yield(event)
                router?.routeNote(event)
            } else {
                var token = ProbeToken()
                token.stamp(.inputReceived)
                let event = MIDIInputEvent(
                    noteNumber: noteNumber, velocity: 0,
                    channel: channel, midiTimestamp: timestamp, probeToken: token
                )
                callbacks.note.fire(event)
                box.yield(event)
                router?.routeNote(event)
            }

        case 0x80:  // Note-Off
            var token = ProbeToken()
            token.stamp(.inputReceived)
            let event = MIDIInputEvent(
                noteNumber: noteNumber, velocity: 0,
                channel: channel, midiTimestamp: timestamp, probeToken: token
            )
            callbacks.note.fire(event)
            box.yield(event)
            router?.routeNote(event)

        case 0xB0:  // Control Change
            let ccIndex = UInt8((word1 >> 8) & 0x7F)
            let ccValue7 = UInt8(word2 >> 25)
            let ccEvent = MIDIControlChangeEvent(
                controller: ccIndex, value: ccValue7,
                channel: channel, midiTimestamp: timestamp
            )
            callbacks.cc.fire(ccEvent)
            router?.routeCC(ccEvent)

        case 0xA0:  // Poly Pressure
            let pressureEvent = MIDIPressureEvent(
                noteNumber: noteNumber, pressure: word2,
                channel: channel, midiTimestamp: timestamp
            )
            callbacks.pressure.fire(pressureEvent)
            router?.routePressure(pressureEvent)

        case 0xC0:  // Program Change
            let bankValid = (word1 & 0x01) != 0
            let program = UInt8((word2 >> 24) & 0x7F)
            let bankMSB = UInt8((word2 >> 8) & 0x7F)
            let bankLSB = UInt8(word2 & 0x7F)
            let pgmEvent = MIDIProgramChangeEvent(
                program: program, bankMSB: bankMSB, bankLSB: bankLSB,
                bankIsValid: bankValid, channel: channel, midiTimestamp: timestamp
            )
            callbacks.programChange.fire(pgmEvent)
            router?.routeProgramChange(pgmEvent)

        case 0xD0:  // Channel Pressure
            let pressureEvent = MIDIPressureEvent(
                noteNumber: nil, pressure: word2,
                channel: channel, midiTimestamp: timestamp
            )
            callbacks.pressure.fire(pressureEvent)
            router?.routePressure(pressureEvent)

        case 0xE0:  // Pitch Bend (channel-wide)
            let rawBend = Int32(bitPattern: word2)
            let bendEvent = MIDIPitchBendEvent(
                value: rawBend, channel: channel,
                midiTimestamp: timestamp, resolution: .midi2
            )
            callbacks.pitchBend.fire(bendEvent)
            router?.routePitchBend(bendEvent)

        case 0x60:  // Per-Note Pitch Bend
            let rawBend = Int32(bitPattern: word2)
            let bendEvent = MIDIPitchBendEvent(
                value: rawBend, noteNumber: noteNumber,
                channel: channel, midiTimestamp: timestamp, resolution: .midi2
            )
            callbacks.pitchBend.fire(bendEvent)
            router?.routePitchBend(bendEvent)

        default:
            // Controller and management messages (0x00–0x50, 0xF0) — router only.
            parseMIDI2Controller(
                word1, word2: word2, statusNibble: statusNibble,
                noteNumber: noteNumber, channel: channel,
                timestamp: timestamp, router: router
            )
        }
    }

    // swiftlint:enable function_parameter_count cyclomatic_complexity

    /// Parse MIDI 2.0 controller and management messages (router-only).
    ///
    /// Handles per-note controllers (0x00, 0x10), RPN/NRPN (0x20–0x50),
    /// and per-note management (0xF0). These are dispatched only through
    /// the router — no callback box needed for these rare message types.
    private static func parseMIDI2Controller(
        _ word1: UInt32,
        word2: UInt32,
        statusNibble: UInt8,
        noteNumber: UInt8,
        channel: UInt8,
        timestamp: MIDITimeStamp,
        router: MidiRouter?
    ) {
        switch statusNibble {
        case 0x00:  // Registered Per-Note Controller
            let index = UInt8(word1 & 0xFF)
            let pncEvent = MIDIPerNoteControlEvent(
                noteNumber: noteNumber, index: index, value: word2,
                controlType: .registered, channel: channel, midiTimestamp: timestamp
            )
            router?.routePerNoteControl(pncEvent)

        case 0x10:  // Assignable Per-Note Controller
            let index = UInt8(word1 & 0xFF)
            let pncEvent = MIDIPerNoteControlEvent(
                noteNumber: noteNumber, index: index, value: word2,
                controlType: .assignable, channel: channel, midiTimestamp: timestamp
            )
            router?.routePerNoteControl(pncEvent)

        case 0x20:  // Registered Controller (RPN)
            let bank = UInt8((word1 >> 8) & 0x7F)
            let index = UInt8(word1 & 0x7F)
            let rcEvent = MIDIRegisteredControlEvent(
                bank: bank, index: index, value: word2,
                controlType: .registered, channel: channel, midiTimestamp: timestamp
            )
            router?.routeRegisteredControl(rcEvent)

        case 0x30:  // Assignable Controller (NRPN)
            let bank = UInt8((word1 >> 8) & 0x7F)
            let index = UInt8(word1 & 0x7F)
            let rcEvent = MIDIRegisteredControlEvent(
                bank: bank, index: index, value: word2,
                controlType: .assignable, channel: channel, midiTimestamp: timestamp
            )
            router?.routeRegisteredControl(rcEvent)

        case 0x40:  // Relative Registered Controller
            let bank = UInt8((word1 >> 8) & 0x7F)
            let index = UInt8(word1 & 0x7F)
            let rcEvent = MIDIRegisteredControlEvent(
                bank: bank, index: index, value: word2,
                controlType: .relativeRegistered, channel: channel, midiTimestamp: timestamp
            )
            router?.routeRegisteredControl(rcEvent)

        case 0x50:  // Relative Assignable Controller
            let bank = UInt8((word1 >> 8) & 0x7F)
            let index = UInt8(word1 & 0x7F)
            let rcEvent = MIDIRegisteredControlEvent(
                bank: bank, index: index, value: word2,
                controlType: .relativeAssignable, channel: channel, midiTimestamp: timestamp
            )
            router?.routeRegisteredControl(rcEvent)

        case 0xF0:  // Per-Note Management
            let optionFlags = UInt8(word1 & 0xFF)
            let detach = (optionFlags & 0x02) != 0
            let reset = (optionFlags & 0x01) != 0
            let pnmEvent = MIDIPerNoteManagementEvent(
                noteNumber: noteNumber, detach: detach, reset: reset,
                channel: channel, midiTimestamp: timestamp
            )
            router?.routePerNoteManagement(pnmEvent)

        default:
            break
        }
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
    ///
    /// USB class-compliant keyboards (e.g. Yamaha PSR-I400) expose the endpoint's
    /// `kMIDIPropertyDisplayName` as a generic descriptor like "Digital Keyboard"
    /// — often the device's `kMIDIPropertyName` is also generic. Compose the best
    /// label we can from manufacturer + model + name on the parent device, and
    /// fall back to the endpoint's display name for virtual sources (IAC, Network
    /// Session) that have no parent device.
    static func sourceName(_ endpoint: MIDIEndpointRef) -> String {
        var entity: MIDIEntityRef = 0
        var device: MIDIDeviceRef = 0
        if MIDIEndpointGetEntity(endpoint, &entity) == noErr, entity != 0,
            MIDIEntityGetDevice(entity, &device) == noErr, device != 0
        {
            let deviceName = cfStringProperty(device, kMIDIPropertyName)
            let manufacturer = cfStringProperty(device, kMIDIPropertyManufacturer)
            let model = cfStringProperty(device, kMIDIPropertyModel)
            let composed = composeDeviceLabel(
                name: deviceName, manufacturer: manufacturer, model: model
            )
            if let composed { return composed }
        }
        if let endpointDisplay = cfStringProperty(endpoint, kMIDIPropertyDisplayName) {
            return endpointDisplay
        }
        return "Unknown Device"
    }

    /// Combine device properties into a user-friendly label. Prefers the most
    /// specific brand + model pairing available; returns nil if every property
    /// is empty so the caller can fall back to endpoint display name.
    private static func composeDeviceLabel(
        name: String?, manufacturer: String?, model: String?
    ) -> String? {
        let trimmedName = name?.trimmingCharacters(in: .whitespaces)
        let trimmedManufacturer = manufacturer?.trimmingCharacters(in: .whitespaces)
        let trimmedModel = model?.trimmingCharacters(in: .whitespaces)

        if let manufacturer = trimmedManufacturer, !manufacturer.isEmpty {
            if let model = trimmedModel, !model.isEmpty {
                return model.localizedCaseInsensitiveContains(manufacturer)
                    ? model : "\(manufacturer) \(model)"
            }
            if let name = trimmedName, !name.isEmpty {
                return name.localizedCaseInsensitiveContains(manufacturer)
                    ? name : "\(manufacturer) \(name)"
            }
            return manufacturer
        }
        if let model = trimmedModel, !model.isEmpty { return model }
        if let name = trimmedName, !name.isEmpty { return name }
        return nil
    }

    /// Fetch a string CoreMIDI property, trimmed/empty-coalesced to nil.
    private static func cfStringProperty(
        _ object: MIDIObjectRef, _ key: CFString
    ) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, key, &value) == noErr,
            let resolved = value?.takeRetainedValue() as String?,
            !resolved.isEmpty
        else { return nil }
        return resolved
    }

    /// Fetch an Int32 CoreMIDI property; returns nil if unset.
    private static func cfIntegerProperty(
        _ object: MIDIObjectRef, _ key: CFString
    ) -> Int32? {
        var value: Int32 = 0
        guard MIDIObjectGetIntegerProperty(object, key, &value) == noErr else { return nil }
        return value
    }

    /// Walk every currently-connected CoreMIDI source and emit its full
    /// property set. Call this at Play-Along start so the container log
    /// carries the identity of devices that were plugged in BEFORE
    /// diagnostics became enabled (normal refreshSources path writes
    /// while diagnostics are still disabled and lines are dropped).
    public static func logAllConnectedSources(tag: String = "MIDI-SRC") {
        let count = MIDIGetNumberOfSources()
        guard count > 0 else {
            MIDIDiagBridge.recordLine("[\(tag)] (no sources)")
            return
        }
        for i in 0..<count {
            let source = MIDIGetSource(i)
            guard source != 0 else { continue }
            guard isPhysicalSource(source) else { continue }
            logEndpointProperties(source, tag: tag)
        }
    }

    /// Dump every CoreMIDI property we care about for an endpoint and its parent
    /// entity/device. Tagged lines are appended to `midi_diag.log` so container
    /// pulls show the full runtime identity without Console.app.
    static func logEndpointProperties(_ endpoint: MIDIEndpointRef, tag: String) {
        var entity: MIDIEntityRef = 0
        var device: MIDIDeviceRef = 0
        let hasEntity = MIDIEndpointGetEntity(endpoint, &entity) == noErr && entity != 0
        let hasDevice = hasEntity
            && MIDIEntityGetDevice(entity, &device) == noErr && device != 0

        // Endpoint-level identity (Swift array of (key, value) pairs)
        let endpointStrings: [(String, String)] = [
            ("name", cfStringProperty(endpoint, kMIDIPropertyName) ?? "-"),
            ("display", cfStringProperty(endpoint, kMIDIPropertyDisplayName) ?? "-"),
            ("manufacturer", cfStringProperty(endpoint, kMIDIPropertyManufacturer) ?? "-"),
            ("model", cfStringProperty(endpoint, kMIDIPropertyModel) ?? "-"),
        ]
        let endpointInts: [(String, Int32?)] = [
            ("uniqueID", cfIntegerProperty(endpoint, kMIDIPropertyUniqueID)),
            ("deviceID", cfIntegerProperty(endpoint, kMIDIPropertyDeviceID)),
            ("protocolID", cfIntegerProperty(endpoint, kMIDIPropertyProtocolID)),
            ("offline", cfIntegerProperty(endpoint, kMIDIPropertyOffline)),
            ("receiveChannels", cfIntegerProperty(endpoint, kMIDIPropertyReceiveChannels)),
            ("transmitChannels", cfIntegerProperty(endpoint, kMIDIPropertyTransmitChannels)),
            ("transmitsNotes", cfIntegerProperty(endpoint, kMIDIPropertyTransmitsNotes)),
            ("transmitsProgramChanges", cfIntegerProperty(endpoint, kMIDIPropertyTransmitsProgramChanges)),
            ("transmitsClock", cfIntegerProperty(endpoint, kMIDIPropertyTransmitsClock)),
            ("transmitsMTC", cfIntegerProperty(endpoint, kMIDIPropertyTransmitsMTC)),
            ("maxSysExSpeed", cfIntegerProperty(endpoint, kMIDIPropertyMaxSysExSpeed)),
        ]
        logKV(tag: "\(tag)-EP", strings: endpointStrings, ints: endpointInts)

        // Device-level identity + capability flags
        guard hasDevice else {
            MIDIDiagBridge.recordLine("[\(tag)-DEV] (no parent device — virtual endpoint)")
            return
        }
        let deviceStrings: [(String, String)] = [
            ("name", cfStringProperty(device, kMIDIPropertyName) ?? "-"),
            ("display", cfStringProperty(device, kMIDIPropertyDisplayName) ?? "-"),
            ("manufacturer", cfStringProperty(device, kMIDIPropertyManufacturer) ?? "-"),
            ("model", cfStringProperty(device, kMIDIPropertyModel) ?? "-"),
            ("driverOwner", cfStringProperty(device, kMIDIPropertyDriverOwner) ?? "-"),
        ]
        let deviceInts: [(String, Int32?)] = [
            ("uniqueID", cfIntegerProperty(device, kMIDIPropertyUniqueID)),
            ("protocolID", cfIntegerProperty(device, kMIDIPropertyProtocolID)),
            ("driverVersion", cfIntegerProperty(device, kMIDIPropertyDriverVersion)),
            ("supportsMMC", cfIntegerProperty(device, kMIDIPropertySupportsMMC)),
            ("supportsGeneralMIDI", cfIntegerProperty(device, kMIDIPropertySupportsGeneralMIDI)),
            ("supportsShowControl", cfIntegerProperty(device, kMIDIPropertySupportsShowControl)),
            ("isMixer", cfIntegerProperty(device, kMIDIPropertyIsMixer)),
            ("isSampler", cfIntegerProperty(device, kMIDIPropertyIsSampler)),
            ("isEffectUnit", cfIntegerProperty(device, kMIDIPropertyIsEffectUnit)),
            ("isDrumMachine", cfIntegerProperty(device, kMIDIPropertyIsDrumMachine)),
            ("offline", cfIntegerProperty(device, kMIDIPropertyOffline)),
        ]
        logKV(tag: "\(tag)-DEV", strings: deviceStrings, ints: deviceInts)
    }

    /// Format a tagged key/value dump as a single line in the diag log.
    private static func logKV(
        tag: String, strings: [(String, String)], ints: [(String, Int32?)]
    ) {
        var parts: [String] = []
        for (k, v) in strings { parts.append("\(k)='\(v)'") }
        for (k, v) in ints {
            parts.append("\(k)=\(v.map { String($0) } ?? "-")")
        }
        let msg = "[\(tag)] " + parts.joined(separator: " ")
        logger.info("\(msg, privacy: .public)")
        MIDIDiagBridge.recordLine(msg)
    }
}
