import AVFoundation
import Foundation
import SVCore
import Testing
@testable import SVAudio

/// Unit coverage for `TakePlaybackEngine`'s scheduling math (hand filter +
/// speed scaling). Audio + display-link behaviour requires a real
/// `AVAudioEngine` and is exercised at the app integration layer.
@MainActor
struct TakePlaybackEngineTests {

    /// Records every dispatched highlight call so tests can assert on the
    /// sequence emitted by the visual link.
    final class MockSink: HighlightSink, @unchecked Sendable {
        var ons: [Int] = []
        var offs: [(Int, UInt8)] = []
        var sustainDownCount = 0
        var sustainUpCount = 0
        func noteOn(_ midiNote: Int) { ons.append(midiNote) }
        func noteOff(_ midiNote: Int, channel: UInt8) { offs.append((midiNote, channel)) }
        func sustainDown(channel _: UInt8) { sustainDownCount += 1 }
        func sustainUp(channel _: UInt8) { sustainUpCount += 1 }
    }

    @Test func handFilterTrebleKeepsOnlyMidi60AndAbove() async throws {
        try AudioEngineManager.shared.startForPlayback()
        let multi = try #require(AudioEngineManager.shared.multiChannel)
        let engine = AudioEngineManager.shared.engine
        let sink = MockSink()
        let take = TakeSnapshot(
            notes: [
                RecordedNote(midi: 59, velocity: 90, onTimeSec: 0, offTimeSec: 0.5),
                RecordedNote(midi: 60, velocity: 90, onTimeSec: 0, offTimeSec: 0.5),
            ],
            sustain: [],
            instrumentProgram: 0,
            saPitchMidi: 60
        )
        let player = TakePlaybackEngine(
            multiChannel: multi,
            highlightSink: sink,
            engine: engine
        )
        await player.schedule(snapshot: take, speed: 1.0, handFilter: .trebleOnly, saMidi: 60)
        #expect(player.scheduledNoteCount == 1)
    }

    @Test func speedTwoHalvesEventOnsetTimes() async throws {
        try AudioEngineManager.shared.startForPlayback()
        let multi = try #require(AudioEngineManager.shared.multiChannel)
        let engine = AudioEngineManager.shared.engine
        let take = TakeSnapshot(
            notes: [
                RecordedNote(midi: 60, velocity: 90, onTimeSec: 1.0, offTimeSec: 2.0),
            ],
            sustain: [],
            instrumentProgram: 0,
            saPitchMidi: 60
        )
        let player = TakePlaybackEngine(
            multiChannel: multi,
            highlightSink: nil,
            engine: engine
        )
        await player.schedule(snapshot: take, speed: 2.0, handFilter: .both, saMidi: 60)
        #expect(abs(player.scheduledFirstOnsetSec - 0.5) < 1e-6)
    }

    // MARK: - T10' SMF mode tests

    /// Build a minimal Type-0 SMF byte stream from a single recorded note via
    /// the existing serializer. Used as the SMF input for the SMF-mode tests
    /// below — content fidelity isn't the point, just that the engine accepts
    /// the bytes and exposes an authoritative position clock.
    @MainActor
    private static func makeSMFBytes() -> Data {
        let notes = [
            RecordedNote(midi: 60, velocity: 90, onTimeSec: 0, offTimeSec: 1.0),
            RecordedNote(midi: 64, velocity: 90, onTimeSec: 1.0, offTimeSec: 2.0),
        ]
        return MIDISerializer.serializeType0(notes: notes, sustain: [], program: 0)
    }

    @Test func loadSMFDataPositionsAtZero() async throws {
        try AudioEngineManager.shared.startForPlayback()
        let multi = try #require(AudioEngineManager.shared.multiChannel)
        let engine = AudioEngineManager.shared.engine
        let graph = try MultiTrackSamplerGraph(trackCount: 1)
        let player = TakePlaybackEngine(
            multiChannel: multi,
            highlightSink: nil,
            engine: engine
        )
        try player.loadSMFData(Self.makeSMFBytes(), graph: graph, instrumentProgram: 0)
        #expect(player.mode == .smf)
        #expect(player.currentPositionSec == 0.0)
    }

    @Test func smfSeekUpdatesCurrentPosition() async throws {
        try AudioEngineManager.shared.startForPlayback()
        let multi = try #require(AudioEngineManager.shared.multiChannel)
        let engine = AudioEngineManager.shared.engine
        let graph = try MultiTrackSamplerGraph(trackCount: 1)
        let player = TakePlaybackEngine(
            multiChannel: multi,
            highlightSink: nil,
            engine: engine
        )
        try player.loadSMFData(Self.makeSMFBytes(), graph: graph, instrumentProgram: 0)
        player.seek(toSec: 0.5)
        #expect(abs(player.currentPositionSec - 0.5) < 0.05)
    }

    @Test func smfPlayAdvancesPositionMonotonically() async throws {
        try AudioEngineManager.shared.startForPlayback()
        let multi = try #require(AudioEngineManager.shared.multiChannel)
        let engine = AudioEngineManager.shared.engine
        let graph = try MultiTrackSamplerGraph(trackCount: 1)
        let player = TakePlaybackEngine(
            multiChannel: multi,
            highlightSink: nil,
            engine: engine
        )
        try player.loadSMFData(Self.makeSMFBytes(), graph: graph, instrumentProgram: 0)
        let before = player.currentPositionSec
        player.play()
        // Yield + tiny sleep so the sequencer hardware clock advances.
        try await Task.sleep(nanoseconds: 100_000_000)
        let after = player.currentPositionSec
        player.pause()
        #expect(after >= before)
    }

    /// Stage Manager resilience: AVAudioSession `.interruptionNotification`
    /// fires `.began` when the OS hands focus to another app (the same path
    /// triggered under the hood by Stage Manager scene transitions). The
    /// engine + sequencer should pause cleanly without scrambling the clock.
    /// `.ended` resumes. Per HIG Multitasking + the Stage Manager resize
    /// gate in T10's acceptance, the clock must not lie about position
    /// across interruption begin/end.
    @Test func audioSessionInterruptionPausesWithoutDesync() async throws {
        try AudioEngineManager.shared.startForPlayback()
        let multi = try #require(AudioEngineManager.shared.multiChannel)
        let engine = AudioEngineManager.shared.engine
        let graph = try MultiTrackSamplerGraph(trackCount: 1)
        let player = TakePlaybackEngine(
            multiChannel: multi,
            highlightSink: nil,
            engine: engine
        )
        try player.loadSMFData(Self.makeSMFBytes(), graph: graph, instrumentProgram: 0)
        player.play()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate Stage Manager / interruption begin: pause through the
        // same API the AudioSessionManager would invoke.
        let positionAtPause = player.currentPositionSec
        player.pause()
        try await Task.sleep(nanoseconds: 50_000_000)

        // Position must not advance while paused — the sequencer's clock is
        // frozen, no accumulator continues running.
        let positionAfterPause = player.currentPositionSec
        #expect(abs(positionAfterPause - positionAtPause) < 0.05)

        // Resume and confirm the clock continues from where it left off
        // (no jump forward to wall-clock now).
        player.play()
        try await Task.sleep(nanoseconds: 50_000_000)
        let positionAfterResume = player.currentPositionSec
        player.stop()
        #expect(positionAfterResume >= positionAfterPause)
    }
}
