import CoreMIDI
import Foundation
import Synchronization
import os

// MARK: - OutputState

/// All mutable state for `MIDIOutputManager` consolidated in one Mutex-protected struct.
///
/// Thread safety: every field is accessed exclusively inside `Mutex.withLock` closures.
/// No field is ever read or written outside a lock scope.
private struct OutputState: Sendable {
    var midiClient: MIDIClientRef = 0
    var outputPort: MIDIPortRef = 0
    var virtualSource: MIDIEndpointRef = 0
    var destinationRef: MIDIEndpointRef = 0
    var isStarted: Bool = false
}

/// Snapshot of CoreMIDI refs captured during `stop()` for disposal outside the lock.
private struct StopRefs: Sendable {
    var virtualSource: MIDIEndpointRef
    var outputPort: MIDIPortRef
    var midiClient: MIDIClientRef
}

/// Snapshot of CoreMIDI refs captured in `sendWords(_:)` for use outside the lock.
private struct SendRefs: Sendable {
    var outputPort: MIDIPortRef
    var destinationRef: MIDIEndpointRef
    var virtualSource: MIDIEndpointRef
    var isStarted: Bool
}

// MARK: - MIDIOutputManager

/// Manages MIDI output to hardware destinations and a virtual MIDI source.
///
/// Creates one CoreMIDI client, one output port (for hardware keyboards), and one
/// virtual MIDI source visible to other apps (e.g., GarageBand, DAWs). All send
/// methods are thread-safe via `Mutex<OutputState>`.
///
/// ## Usage
///
/// ```swift
/// let output = MIDIOutputManager()
/// try output.start()
/// output.noteOn(note: 60, velocity: 100, channel: 0)
/// output.noteOff(note: 60, channel: 0)
/// output.stop()
/// ```
///
/// ## MIDI 2.0 Protocol
///
/// All messages are sent using Universal MIDI Packets (UMP) via
/// `MIDIEventList`. Both the hardware output port (`MIDISendEventList`) and
/// the virtual source (`MIDIReceivedEventList`) receive every packet so that
/// connected hardware and listening apps stay in sync.
public final class MIDIOutputManager: Sendable {

    // MARK: - Properties

    private let state = Mutex<OutputState>(OutputState())
    private static let logger = Logger.survibe(category: "MIDIOutput")

    // MARK: - Initialization

    /// Create a new MIDI output manager.
    ///
    /// Does not start the CoreMIDI session — call `start()` before sending messages.
    public init() {}

    // MARK: - Lifecycle

    /// Start the CoreMIDI session, creating the client, output port, and virtual source.
    ///
    /// Creates:
    /// - A `MIDIClientRef` named `"com.survibe.MIDIOutputManager"`.
    /// - An output port for sending to hardware destinations.
    /// - A virtual MIDI source (`"SurVibe"`) visible to other apps via CoreMIDI.
    ///
    /// Safe to call multiple times — returns immediately if already started.
    ///
    /// - Throws: `MIDIOutputError.clientCreationFailed` if CoreMIDI setup fails.
    public func start() throws {
        let alreadyStarted = state.withLock { $0.isStarted }
        guard !alreadyStarted else { return }

        var clientRef: MIDIClientRef = 0
        let clientStatus = MIDIClientCreateWithBlock(
            "com.survibe.MIDIOutputManager" as CFString,
            &clientRef,
            nil
        )
        guard clientStatus == noErr else {
            Self.logger.error("MIDIClientCreateWithBlock failed: OSStatus=\(clientStatus)")
            throw MIDIOutputError.clientCreationFailed(clientStatus)
        }

        var portRef: MIDIPortRef = 0
        let portStatus = MIDIOutputPortCreate(clientRef, "SurVibe Output Port" as CFString, &portRef)
        guard portStatus == noErr else {
            Self.logger.error("MIDIOutputPortCreate failed: OSStatus=\(portStatus)")
            MIDIClientDispose(clientRef)
            throw MIDIOutputError.portCreationFailed(portStatus)
        }

        var sourceRef: MIDIEndpointRef = 0
        let sourceStatus = MIDISourceCreateWithProtocol(
            clientRef,
            "SurVibe" as CFString,
            MIDIProtocolID._2_0,
            &sourceRef
        )
        guard sourceStatus == noErr else {
            Self.logger.error("MIDISourceCreateWithProtocol failed: OSStatus=\(sourceStatus)")
            MIDIPortDispose(portRef)
            MIDIClientDispose(clientRef)
            throw MIDIOutputError.virtualSourceCreationFailed(sourceStatus)
        }

        // Select the first available hardware destination (if any).
        let destinationCount = MIDIGetNumberOfDestinations()
        let destination: MIDIEndpointRef = destinationCount > 0 ? MIDIGetDestination(0) : 0

        state.withLock { s in
            s.midiClient = clientRef
            s.outputPort = portRef
            s.virtualSource = sourceRef
            s.destinationRef = destination
            s.isStarted = true
        }

        Self.logger.info("MIDIOutputManager started — \(destinationCount) destination(s) found")
    }

    /// Stop the MIDI session, disposing all CoreMIDI resources.
    ///
    /// After calling `stop()`, call `start()` again to resume output.
    /// Safe to call multiple times.
    public func stop() {
        let refs = state.withLock { s -> StopRefs in
            guard s.isStarted else {
                return StopRefs(virtualSource: 0, outputPort: 0, midiClient: 0)
            }
            let r = StopRefs(
                virtualSource: s.virtualSource,
                outputPort: s.outputPort,
                midiClient: s.midiClient
            )
            s.virtualSource = 0
            s.outputPort = 0
            s.midiClient = 0
            s.destinationRef = 0
            s.isStarted = false
            return r
        }
        if refs.virtualSource != 0 { MIDIEndpointDispose(refs.virtualSource) }
        if refs.outputPort != 0 { MIDIPortDispose(refs.outputPort) }
        if refs.midiClient != 0 { MIDIClientDispose(refs.midiClient) }
        Self.logger.info("MIDIOutputManager stopped")
    }

    // MARK: - Destination Management

    /// Select a hardware MIDI destination by index.
    ///
    /// Updates the active destination for all subsequent send calls.
    /// Index is clamped to available destinations — a missing index is a no-op.
    ///
    /// - Parameter index: Zero-based index into CoreMIDI's destination list.
    public func selectDestination(at index: Int) {
        let count = MIDIGetNumberOfDestinations()
        guard index >= 0 && index < count else {
            Self.logger.warning("selectDestination: index \(index) out of range (count=\(count))")
            return
        }
        let dest = MIDIGetDestination(index)
        state.withLock { $0.destinationRef = dest }
        Self.logger.debug("Selected MIDI destination at index \(index)")
    }

    // MARK: - Send Methods

    /// Send a MIDI Note On message.
    ///
    /// Builds a UMP Note On packet using `MIDI2MessageBuilder.noteOn` and
    /// delivers it to both the hardware destination and virtual source.
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0–127).
    ///   - velocity: Note velocity (0–127). Values are scaled to MIDI 2.0 16-bit range internally.
    ///   - channel: MIDI channel (0–15).
    public func noteOn(note: UInt8, velocity: UInt8, channel: UInt8) {
        let words = MIDI2MessageBuilder.noteOn(note: note, velocity: velocity, channel: channel)
        sendWords(words)
    }

    /// Send a MIDI Note Off message.
    ///
    /// Builds a UMP Note Off packet and delivers it to both the hardware
    /// destination and virtual source.
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0–127).
    ///   - channel: MIDI channel (0–15).
    public func noteOff(note: UInt8, channel: UInt8) {
        let words = MIDI2MessageBuilder.noteOff(note: note, velocity: 0, channel: channel)
        sendWords(words)
    }

    /// Send a MIDI Control Change (CC) message.
    ///
    /// Builds a MIDI 1.0 UP CC packet wrapped in a UMP and delivers it to
    /// both the hardware destination and virtual source.
    ///
    /// - Parameters:
    ///   - controller: CC number (0–127).
    ///   - value: CC value (0–127).
    ///   - channel: MIDI channel (0–15).
    public func controlChange(controller: UInt8, value: UInt8, channel: UInt8) {
        let words = MIDI2MessageBuilder.controlChange(controller: controller, value: value, channel: channel)
        sendWords(words)
    }

    /// Send a MIDI Pitch Bend message.
    ///
    /// Builds a MIDI 2.0 pitch bend UMP and delivers it to both the hardware
    /// destination and virtual source.
    ///
    /// - Parameters:
    ///   - value: 32-bit pitch bend value. Center (no bend) is `0x80000000`.
    ///   - channel: MIDI channel (0–15).
    public func pitchBend(value: UInt32, channel: UInt8) {
        let words = MIDI2MessageBuilder.pitchBend(value: value, channel: channel)
        sendWords(words)
    }

    /// Send a MIDI Program Change message.
    ///
    /// Builds a MIDI 2.0 program change UMP and delivers it to both the hardware
    /// destination and virtual source.
    ///
    /// - Parameters:
    ///   - program: Program number (0–127).
    ///   - channel: MIDI channel (0–15).
    public func programChange(program: UInt8, channel: UInt8) {
        let words = MIDI2MessageBuilder.programChange(program: program, channel: channel)
        sendWords(words)
    }

    // MARK: - Private Helpers

    /// Build a `MIDIEventList` from UMP words and send to hardware + virtual source.
    ///
    /// Allocates the event list on the stack via `MIDIEventListInit` / `MIDIEventListAdd`,
    /// then dispatches to both `MIDISendEventList` (hardware) and
    /// `MIDIReceivedEventList` (virtual source). A missing destination is silently
    /// skipped — virtual source delivery still proceeds.
    ///
    /// - Parameter words: One or two UInt32 UMP words for a single MIDI message.
    private func sendWords(_ words: [UInt32]) {
        guard !words.isEmpty else { return }

        let refs = state.withLock { s -> SendRefs in
            SendRefs(
                outputPort: s.outputPort,
                destinationRef: s.destinationRef,
                virtualSource: s.virtualSource,
                isStarted: s.isStarted
            )
        }
        guard refs.isStarted else { return }
        let port = refs.outputPort
        let destination = refs.destinationRef
        let virtualSrc = refs.virtualSource

        var eventList = MIDIEventList()
        var packetPtr = MIDIEventListInit(&eventList, MIDIProtocolID._2_0)

        words.withUnsafeBufferPointer { buf in
            guard let basePtr = buf.baseAddress else { return }
            packetPtr = MIDIEventListAdd(
                &eventList,
                MemoryLayout<MIDIEventList>.size,
                packetPtr,
                0,
                words.count,
                basePtr
            )
        }

        // Send to hardware destination (best-effort; missing destination is a no-op).
        if destination != 0 {
            let status = MIDISendEventList(port, destination, &eventList)
            if status != noErr {
                Self.logger.warning("MIDISendEventList failed: OSStatus=\(status)")
            }
        }

        // Broadcast through the virtual source so other apps (e.g. GarageBand) receive it.
        if virtualSrc != 0 {
            let status = MIDIReceivedEventList(virtualSrc, &eventList)
            if status != noErr {
                Self.logger.warning("MIDIReceivedEventList failed: OSStatus=\(status)")
            }
        }
    }
}

// MARK: - MIDIOutputError

/// Errors thrown by `MIDIOutputManager.start()`.
public enum MIDIOutputError: Error, Sendable {
    /// CoreMIDI client creation failed.
    case clientCreationFailed(OSStatus)
    /// Output port creation failed.
    case portCreationFailed(OSStatus)
    /// Virtual MIDI source creation failed.
    case virtualSourceCreationFailed(OSStatus)
}
