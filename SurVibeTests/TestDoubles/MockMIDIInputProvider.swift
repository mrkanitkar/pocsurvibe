import SVAudio

/// Test double for `MIDIInputProviding` that simulates MIDI keyboard input
/// without requiring real hardware.
/// Test double — `@unchecked Sendable` is permitted per CLAUDE.md for test doubles.
/// All mutable state is only accessed from tests running on `@MainActor`.
final class MockMIDIInputProvider: MIDIInputProviding, @unchecked Sendable {
    /// Whether to report as connected when `start()` is called.
    var simulateConnected: Bool = false

    /// Device name to report when connected.
    var simulatedDeviceName: String? = "Mock MIDI Keyboard"

    // MARK: - MIDIInputProviding

    @MainActor
    var isConnected: Bool = false
    @MainActor
    var connectedDeviceName: String?

    /// Direct low-latency callback (mirrors production `MIDIInputManager`).
    var onNoteEvent: (@Sendable (MIDIInputEvent) -> Void)?

    /// Direct low-latency callback for Control Change events.
    var onControlChangeEvent: (@Sendable (MIDIControlChangeEvent) -> Void)?

    var noteOnStream: AsyncStream<MIDIInputEvent> {
        if let stream = _noteOnStream { return stream }
        let (stream, cont) = AsyncStream<MIDIInputEvent>.makeStream()
        _noteOnStream = stream
        continuation = cont
        return stream
    }

    var connectionStateStream: AsyncStream<Bool> {
        if let stream = _connectionStateStream { return stream }
        let (stream, cont) = AsyncStream<Bool>.makeStream()
        _connectionStateStream = stream
        connectionContinuation = cont
        return stream
    }

    private var _noteOnStream: AsyncStream<MIDIInputEvent>?
    private(set) var continuation: AsyncStream<MIDIInputEvent>.Continuation?
    private var _connectionStateStream: AsyncStream<Bool>?
    private(set) var connectionContinuation: AsyncStream<Bool>.Continuation?

    private(set) var startCallCount: Int = 0
    private(set) var stopCallCount: Int = 0

    func start() {
        startCallCount += 1
        let connected = simulateConnected
        let name = simulateConnected ? simulatedDeviceName : nil
        Task { @MainActor in
            self.isConnected = connected
            self.connectedDeviceName = name
        }
        if connected {
            connectionContinuation?.yield(true)
        }
        // Ensure streams exist
        _ = noteOnStream
        _ = connectionStateStream
    }

    func stop() {
        stopCallCount += 1
        Task { @MainActor in
            self.isConnected = false
            self.connectedDeviceName = nil
        }
        continuation?.finish()
        continuation = nil
        _noteOnStream = nil
        connectionContinuation?.finish()
        connectionContinuation = nil
        _connectionStateStream = nil
    }

    // MARK: - Test Helpers

    /// Simulate a note-on event arriving from the MIDI keyboard.
    ///
    /// - Parameters:
    ///   - noteNumber: MIDI note number (0–127).
    ///   - velocity: Note velocity (1–127).
    func simulateNoteOn(noteNumber: UInt8, velocity: UInt8 = 64) {
        // Ensure stream is initialized
        _ = noteOnStream
        let event = MIDIInputEvent(noteNumber: noteNumber, velocity: velocity)
        // Fire the direct callback first (matches production behaviour).
        onNoteEvent?(event)
        // Also yield into the AsyncStream for any test that uses it.
        continuation?.yield(event)
    }

    /// Simulate a note-off event arriving from the MIDI keyboard.
    ///
    /// - Parameter noteNumber: MIDI note number (0–127).
    func simulateNoteOff(noteNumber: UInt8) {
        _ = noteOnStream
        let event = MIDIInputEvent(noteNumber: noteNumber, velocity: 0)
        onNoteEvent?(event)
        continuation?.yield(event)
    }

    /// Simulate a Control Change event arriving from the MIDI keyboard.
    ///
    /// - Parameters:
    ///   - controller: MIDI controller number (0-127). 64 = sustain pedal.
    ///   - value: Controller value (0-127). For CC64: >= 64 = down, < 64 = up.
    ///   - channel: MIDI channel (0-15).
    func simulateControlChange(controller: UInt8, value: UInt8, channel: UInt8 = 0) {
        let event = MIDIControlChangeEvent(controller: controller, value: value, channel: channel)
        onControlChangeEvent?(event)
    }

    /// Simulate a hot-plug connection state change (connect or disconnect).
    ///
    /// - Parameter connected: `true` = keyboard connected, `false` = disconnected.
    @MainActor
    func simulateConnectionChange(connected: Bool) {
        isConnected = connected
        connectedDeviceName = connected ? simulatedDeviceName : nil
        _ = connectionStateStream
        connectionContinuation?.yield(connected)
    }

    /// Reset all recorded state.
    @MainActor
    func reset() {
        isConnected = false
        connectedDeviceName = nil
        startCallCount = 0
        stopCallCount = 0
        simulateConnected = false
        onNoteEvent = nil
        onControlChangeEvent = nil
    }
}
