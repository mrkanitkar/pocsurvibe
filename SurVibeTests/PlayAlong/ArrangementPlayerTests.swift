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
    /// Build a `PartSplit` with a learner score of `measureCount`
    /// measures of empty 4/4. Used by C3 loop tests.
    private func makeSplitWithMeasures(_ measureCount: Int) -> PartSplit {
        _ = measureCount
        // The learner note list is irrelevant for loop-controller tests —
        // only `learner.beatsPerMeasure` is consulted by `setLoop(_:)`.
        // The accompaniment SMF is the same 14-byte minimal header.
        return makeSplit()
    }

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

    @Test func startWithDefaultCountInSchedulesOneBarOfClicks() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        player.start()
        // Default countInBars is 1; with beatsPerMeasure=4 we expect 4
        // metronome clicks at beats [-4, -3, -2, -1] on channel 9 and
        // currentBeat positioned at -4 ready to count up to 0.
        #expect(player.currentBeat == -4)
        #expect(mock.scheduledMetronomeClicks.count == 4)
    }

    @Test func startSchedulesCountInClicksBeforeBeatZero() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        player.start(countInBars: 1)
        let beats = mock.scheduledMetronomeClicks.map(\.0)
        let channels = mock.scheduledMetronomeClicks.map(\.1)
        #expect(beats == [-4, -3, -2, -1])
        #expect(channels == [9, 9, 9, 9])
    }

    @Test func startWithCountInBars2DoublesClicks() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        player.start(countInBars: 2)
        #expect(mock.scheduledMetronomeClicks.count == 8)
        let beats = mock.scheduledMetronomeClicks.map(\.0)
        #expect(beats == [-8, -7, -6, -5, -4, -3, -2, -1])
        #expect(player.currentBeat == -8)
    }

    @Test func startWithCountInBarsZeroSkipsScheduling() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        player.start(countInBars: 0)
        #expect(mock.scheduledMetronomeClicks.isEmpty)
        #expect(player.currentBeat == 0)
    }

    @Test func startSetsCurrentBeatToNegativeCountIn() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        player.start(countInBars: 1)
        #expect(player.currentBeat == -4)
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

    /// Build a `PartSplit` whose learner has two staves (RH + LH) on two
    /// distinct accompaniment-sequencer track indices. Used by the C4
    /// hand-isolation tests.
    private func makeSplitWithTwoStaves() -> PartSplit {
        let bytes: [UInt8] = [
            0x4D, 0x54, 0x68, 0x64,
            0x00, 0x00, 0x00, 0x06,
            0x00, 0x00,
            0x00, 0x00,
            0x01, 0xE0,
        ]
        let learner = LearnerScore(notes: [], originalBPM: 120, beatsPerMeasure: 4)
        let rhStaff = StaffSpec(staffNumber: 1, role: .rightHand, noteIDs: [])
        let lhStaff = StaffSpec(staffNumber: 2, role: .leftHand, noteIDs: [])
        return PartSplit(
            learner: learner,
            accompaniment: Data(bytes),
            learnerInstrumentLabel: "Piano",
            accompanimentInstruments: [],
            learnerTrackIndices: [0, 1],
            learnerStaves: [rhStaff, lhStaff],
            lyricsStaffTrackIndex: nil
        )
    }

    // MARK: - Hand isolation (C4)

    @Test func defaultPracticeModeIsBothNoMutes() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplitWithTwoStaves())
        #expect(player.practiceMode == .both)
        #expect(player.hearOtherHand == true)
        #expect(mock.mutedTrackIndices.isEmpty)
    }

    @Test func bothModeMutesNothing() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplitWithTwoStaves())
        player.hearOtherHand = false
        player.practiceMode = .both
        #expect(mock.mutedTrackIndices.isEmpty)
    }

    @Test func rightHandModeWithHearOtherHandTrueMutesNothing() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplitWithTwoStaves())
        player.practiceMode = .rightHand
        player.hearOtherHand = true
        #expect(mock.mutedTrackIndices.isEmpty)
    }

    @Test func rightHandModeWithHearOtherHandFalseMutesLeftHand() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplitWithTwoStaves())
        player.practiceMode = .rightHand
        player.hearOtherHand = false
        #expect(mock.mutedTrackIndices == [1])
    }

    @Test func leftHandModeWithHearOtherHandFalseMutesRightHand() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplitWithTwoStaves())
        player.practiceMode = .leftHand
        player.hearOtherHand = false
        #expect(mock.mutedTrackIndices == [0])
    }

    @Test func togglingHearOtherHandRevertsMutes() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplitWithTwoStaves())
        player.practiceMode = .rightHand
        player.hearOtherHand = false
        #expect(mock.mutedTrackIndices == [1])
        player.hearOtherHand = true
        #expect(mock.mutedTrackIndices.isEmpty)
    }

    @Test func practiceModeIsCaseIterable() {
        #expect(PracticeMode.allCases.count == 3)
        #expect(PracticeMode.allCases.contains(.both))
        #expect(PracticeMode.allCases.contains(.rightHand))
        #expect(PracticeMode.allCases.contains(.leftHand))
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

    // MARK: - C3: Section Loop

    @Test func setLoopMakesPlayerSeekBackAtEndOfRegion() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplitWithMeasures(20))
        player.setLoop(LoopRegion(startMeasure: 5, endMeasure: 8))
        player.start()
        // Simulate the playback driver advancing past the end of measure 8.
        player.simulateBeatTick(beatsPerMeasure: 4, currentBeat: 32.5)
        // Player should have called graph.seek to start of measure 5
        // (beat (5-1)*4 = 16).
        #expect(mock.lastSeekBeat == 16)
        #expect(player.currentBeat == 16)
    }

    @Test func loopFirstIterationPlaysCountInOnly() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplitWithMeasures(20))
        player.setLoop(LoopRegion(startMeasure: 5, endMeasure: 8))
        player.start()
        let initialClicks = mock.scheduledMetronomeClicks.count
        // Trigger loop wraparound — no NEW count-in clicks should be scheduled.
        player.simulateBeatTick(beatsPerMeasure: 4, currentBeat: 32.5)
        let afterWrap = mock.scheduledMetronomeClicks.count
        #expect(afterWrap == initialClicks)
    }

    @Test func setLoopNilClearsLooping() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplitWithMeasures(20))
        player.setLoop(LoopRegion(startMeasure: 5, endMeasure: 8))
        player.setLoop(nil)
        player.start()
        // With looping cleared, advancing past the former endBeat must NOT
        // trigger a seek.
        player.simulateBeatTick(beatsPerMeasure: 4, currentBeat: 32.5)
        #expect(mock.lastSeekBeat == nil)
        #expect(player.currentBeat == 32.5)
    }

    @Test func setLoopBeforeLoadIsNoOp() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        // No load — setLoop must be a no-op rather than crashing.
        player.setLoop(LoopRegion(startMeasure: 5, endMeasure: 8))
        // Subsequent ticks (post-load, post-start) should not seek because
        // the loop never installed.
        try await player.load(makeSplitWithMeasures(20))
        player.start()
        player.simulateBeatTick(beatsPerMeasure: 4, currentBeat: 32.5)
        #expect(mock.lastSeekBeat == nil)
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
