// SurVibeTests/PlayAlong/ArrangementPlayerTests.swift
import Foundation
import SVAudio
import SVCore
import Testing

@testable import SurVibe

/// Unit tests for `ArrangementPlayer` (Wave 3 Task C1).
///
/// `ArrangementPlayer` wraps `MultiTrackSamplerGraphProtocol` and exposes
/// transport / tempo / state for the Learn-a-Song play-along flow. C1
/// covers load + start + pause + resume + stop + setTempoScale forwarding.
/// Count-in (C2), loop (C3), and hand isolation (C4) layer on top in
/// later tasks.
@MainActor
@Suite("ArrangementPlayer")
struct ArrangementPlayerTests {

    // MARK: - Helpers

    /// Build a minimal valid `PartSplit` for tests. The accompaniment Data
    /// is a 14-byte SMF header — it is stored on the player but never
    /// loaded into a real `AVAudioSequencer` because the mock graph
    /// records `loadMIDICalled` without parsing the bytes.
    private func makeSplit() -> PartSplit {
        // Minimal SMF header: "MThd" + length(6) + format(0) + tracks(0) + division(480)
        let bytes: [UInt8] = [
            0x4D, 0x54, 0x68, 0x64,
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,
            0x00, 0x00,
            0x01, 0xE0,
        ]
        let learner = LearnerScore(notes: [], originalBPM: 120, beatsPerMeasure: 4)
        return PartSplit(
            learner: learner,
            accompaniment: Data(bytes),
            learnerInstrumentLabel: "Piano",
            accompanimentInstruments: [],
            learnerTrackIndices: [],
            learnerStaves: [],
            lyricsStaffTrackIndex: nil
        )
    }

    // MARK: - Tests

    @Test func loadAcceptsPartSplit() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        #expect(mock.loadMIDICalled)
        #expect(mock.lastSetTempoScale == 1.0)
    }

    @Test func setTempoScaleForwardsToGraph() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        player.setTempoScale(0.75)
        #expect(mock.lastSetTempoScale == 0.75)
    }

    @Test func startSetsIsPlayingAndStartHostTime() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        player.start()
        #expect(player.isPlaying)
        #expect(player.startHostTime != nil)
        #expect(mock.playCalled)
    }

    @Test func startWithoutCountInBaseBeginsAtBeatZero() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        player.start()
        // C1 base has no count-in scheduling (added in C2). currentBeat
        // remains at 0 immediately after start.
        #expect(player.currentBeat == 0)
        #expect(mock.scheduledMetronomeClicks.isEmpty)
    }

    @Test func pauseFlipsIsPlayingFalse() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        player.start()
        player.pause()
        #expect(player.isPlaying == false)
        #expect(mock.pauseCalled)
    }

    @Test func resumeFlipsIsPlayingTrue() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        player.start()
        player.pause()
        player.resume()
        #expect(player.isPlaying)
        #expect(mock.resumeCalled)
    }

    @Test func stopResetsIsPlayingFalse() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        player.start()
        player.stop()
        #expect(player.isPlaying == false)
        #expect(mock.stopCalled)
    }
}

// MARK: - MockGraph

/// Test double for `MultiTrackSamplerGraphProtocol`. Records all call
/// invocations so tests can assert forwarding without spinning up
/// `AVAudioEngine`.
@MainActor
final class MockGraph: MultiTrackSamplerGraphProtocol {

    // Recorded state
    var loadMIDICalled = false
    var lastLoadedMIDI: RenderedMIDI?
    var lastSetTempoScale: Float?
    var scheduledMetronomeClicks: [(Double, UInt8)] = []
    var lastSeekBeat: Double?
    var mutedTrackIndices: Set<Int> = []
    var playCalled = false
    var pauseCalled = false
    var resumeCalled = false
    var stopCalled = false

    // Stubbed properties
    var currentPositionInBeats: Double = 0
    private var internalIsPlaying = false
    var isPlaying: Bool { internalIsPlaying }

    func loadMIDI(_ rendered: RenderedMIDI) throws {
        loadMIDICalled = true
        lastLoadedMIDI = rendered
    }

    func setTempoScale(_ rate: Float) {
        lastSetTempoScale = rate
    }

    func play() throws {
        playCalled = true
        internalIsPlaying = true
    }

    func pause() {
        pauseCalled = true
        internalIsPlaying = false
    }

    func stop() {
        stopCalled = true
        internalIsPlaying = false
    }

    func resume() throws {
        resumeCalled = true
        internalIsPlaying = true
    }

    func seek(toBeat beat: Double) {
        lastSeekBeat = beat
    }

    func setMutedTracks(_ indices: Set<Int>) {
        mutedTrackIndices = indices
    }

    func scheduleMetronomeClick(at beat: Double, channel: UInt8) {
        scheduledMetronomeClicks.append((beat, channel))
    }
}
