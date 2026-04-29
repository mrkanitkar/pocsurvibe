import Foundation
import SVAudio

@testable import SurVibe

/// Records every interaction so tests can assert what the VM did.
final class MockPlayTabAudioEngine: PlayTabAudioEngine, @unchecked Sendable {
    var loadProgramCalls: [(index: Int, program: UInt8, isPercussion: Bool)] = []
    var playTouchNoteCalls: [(midi: UInt8, velocity: UInt8)] = []
    var stopTouchNoteCalls: [UInt8] = []
    var stopAllTouchNotesCallCount = 0
    var loadProgramShouldThrow: Error?

    enum MockError: Error { case loadFailed }

    func loadProgram(into index: Int, program: UInt8, isPercussion: Bool) throws {
        loadProgramCalls.append((index, program, isPercussion))
        if let err = loadProgramShouldThrow { throw err }
    }
    func playTouchNote(_ midiNote: UInt8, velocity: UInt8) {
        playTouchNoteCalls.append((midiNote, velocity))
    }
    func stopTouchNote(_ midiNote: UInt8) { stopTouchNoteCalls.append(midiNote) }
    func stopAllTouchNotes() { stopAllTouchNotesCallCount += 1 }
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
