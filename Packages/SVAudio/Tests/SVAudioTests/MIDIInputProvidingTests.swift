import Foundation
import Testing

@testable import SVAudio

@Suite("MIDIInputProviding Protocol Tests")
struct MIDIInputProvidingTests {

    // MARK: - isReplaySource Default

    @Test("MIDIInputManager isReplaySource defaults to false")
    func liveInputIsNotReplaySource() async {
        let manager = await MIDIInputManager.shared
        let isReplay = await manager.isReplaySource
        #expect(isReplay == false)
    }

    // MARK: - ReplayMIDISource Protocol

    @Test("ReplayMIDISource protocol can be conformed to")
    func replaySourceConformance() {
        // Verify the protocol compiles and has the expected shape.
        // A real conformance would be PracticeReplayEngine; here we just
        // verify the protocol definition is accessible.
        let _: any ReplayMIDISource.Type = MockReplaySource.self
    }
}

// MARK: - Test Doubles

/// Minimal mock for verifying ReplayMIDISource conformance compiles.
private final class MockReplaySource: ReplayMIDISource, @unchecked Sendable {
    @MainActor var isConnected: Bool = false
    @MainActor var connectedDeviceName: String? = nil
    var onNoteEvent: (@Sendable (MIDIInputEvent) -> Void)?
    var onControlChangeEvent: (@Sendable (MIDIControlChangeEvent) -> Void)?
    var noteOnStream: AsyncStream<MIDIInputEvent> { AsyncStream { _ in } }
    var connectionStateStream: AsyncStream<Bool> { AsyncStream { _ in } }
    var isReplaySource: Bool { true }
    func start() {}
    func stop() {}
    func seek(to timestamp: Double) {}
}
