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
}
