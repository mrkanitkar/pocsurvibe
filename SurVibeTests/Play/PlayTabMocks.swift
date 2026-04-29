import Foundation
import SVAudio

@testable import SurVibe

/// Records every interaction so tests can assert what the VM did.
///
/// Mutable arrays are guarded by an unfair lock so the nonisolated touch
/// methods (mirroring the real engine's nonisolated hot path) can record
/// calls from any actor context safely.
final class MockPlayTabAudioEngine: PlayTabAudioEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var _loadProgramCalls: [(index: Int, program: UInt8, isPercussion: Bool)] = []
    private var _playTouchNoteCalls: [(midi: UInt8, velocity: UInt8)] = []
    private var _stopTouchNoteCalls: [UInt8] = []
    private var _stopAllTouchNotesCallCount = 0
    private var _loadProgramShouldThrow: Error?

    var loadProgramCalls: [(index: Int, program: UInt8, isPercussion: Bool)] {
        get { lock.withLock { _loadProgramCalls } }
        set { lock.withLock { _loadProgramCalls = newValue } }
    }
    var playTouchNoteCalls: [(midi: UInt8, velocity: UInt8)] {
        get { lock.withLock { _playTouchNoteCalls } }
        set { lock.withLock { _playTouchNoteCalls = newValue } }
    }
    var stopTouchNoteCalls: [UInt8] {
        get { lock.withLock { _stopTouchNoteCalls } }
        set { lock.withLock { _stopTouchNoteCalls = newValue } }
    }
    var stopAllTouchNotesCallCount: Int {
        get { lock.withLock { _stopAllTouchNotesCallCount } }
        set { lock.withLock { _stopAllTouchNotesCallCount = newValue } }
    }
    var loadProgramShouldThrow: Error? {
        get { lock.withLock { _loadProgramShouldThrow } }
        set { lock.withLock { _loadProgramShouldThrow = newValue } }
    }

    enum MockError: Error { case loadFailed }

    @MainActor
    func loadProgram(into index: Int, program: UInt8, isPercussion: Bool) throws {
        lock.withLock { _loadProgramCalls.append((index, program, isPercussion)) }
        if let err = lock.withLock({ _loadProgramShouldThrow }) { throw err }
    }
    nonisolated func playTouchNote(_ midiNote: UInt8, velocity: UInt8) {
        lock.withLock { _playTouchNoteCalls.append((midiNote, velocity)) }
    }
    nonisolated func stopTouchNote(_ midiNote: UInt8) {
        lock.withLock { _stopTouchNoteCalls.append(midiNote) }
    }
    nonisolated func stopAllTouchNotes() {
        lock.withLock { _stopAllTouchNotesCallCount += 1 }
    }
}

/// Mock conforming to the real SVAudio `MIDIInputProviding`. Most members are
/// satisfied by the protocol's default implementations; we only store the
/// stateful bits the VM tests need.
final class MockMIDIInputProviding: MIDIInputProviding, @unchecked Sendable {
    // Stateful storage for the pieces the VM/tests touch.
    @MainActor
    var isConnected: Bool = false
    @MainActor
    var connectedDeviceName: String?
    var onNoteEvent: (@Sendable (MIDIInputEvent) -> Void)?
    var onControlChangeEvent: (@Sendable (MIDIControlChangeEvent) -> Void)?

    // `noteOnStream` and `connectionStateStream` must be conformed to but are
    // unused by the VM under test. Provide finite, immediately-finishing
    // streams to keep the protocol satisfied without leaking continuations.
    let noteOnStream: AsyncStream<MIDIInputEvent> = AsyncStream { $0.finish() }
    let connectionStateStream: AsyncStream<Bool> = AsyncStream { $0.finish() }

    func start() {}
    func stop() {}

    /// Test helper: simulates an inbound MIDI event by invoking the closure synchronously.
    func fire(_ event: MIDIInputEvent) {
        onNoteEvent?(event)
    }
}
