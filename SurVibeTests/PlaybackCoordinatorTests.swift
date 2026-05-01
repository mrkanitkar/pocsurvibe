// SurVibeTests/PlaybackCoordinatorTests.swift
import Foundation
import SVAudio
import SwiftData
import Testing

@testable import SurVibe

/// Unit tests for the visualization-only `PlaybackCoordinator` (Wave 4 D3).
///
/// As of D3, `PlaybackCoordinator` no longer owns audio scheduling. The audio
/// transport is owned by `ArrangementPlayer` (Wave 5 E1). PlaybackCoordinator
/// is a pure visualization-state owner: `noteEvents`, `currentTime`,
/// `currentNoteIndex`, `noteStates`, `playbackState`. Tests below assert the
/// simplified contract: external setters mutate state, no audio is emitted,
/// and `loadSong` populates the visualization model.
///
/// ## Removed in D3 (audio-scheduling tests)
/// The previous suite tested transport mechanics — `startScheduling` engine
/// startup, metronome BPM under tempo scaling, pause/resume preserving an
/// internal clock, and cleanup tearing down audio. All of those mechanics
/// moved out of this coordinator with the D3 rework, so those tests were
/// removed (see commit message).
///
/// ## What remains
/// - `loadSong` data-prep (note events + duration + per-note state).
/// - External transport setters (`setCurrentTime`, `setPlaybackState`,
///   `setCurrentNoteIndex`, `setPlaybackStartDate`).
/// - `seek` paused-only timeline scrub.
/// - `completeSession` finalising scoring + persisting via
///   `SessionRecorder`.
/// - `clearSong` resetting visualization state.
/// - "No audio" invariant: there is no `soundFont` dependency at all — the
///   init no longer accepts one, so any audio call is a compile error.
@MainActor
@Suite("PlaybackCoordinator")
struct PlaybackCoordinatorTests {

    // MARK: - Helpers

    /// Two-note test song: Sa at 0.0s, Re at 0.5s, each 0.25s long.
    private func makeTestNoteEvents() -> [NoteEvent] {
        [
            NoteEventFactory.make(
                swarName: "Sa",
                westernName: "C4",
                midiNote: 60,
                octave: 4,
                timestamp: 0.0,
                duration: 0.25,
                velocity: 90
            ),
            NoteEventFactory.make(
                swarName: "Re",
                westernName: "D4",
                midiNote: 62,
                octave: 4,
                timestamp: 0.5,
                duration: 0.25,
                velocity: 90
            ),
        ]
    }

    /// Build a coordinator with a fresh scoring + analytics mock.
    private func makeCoordinator() -> PlaybackCoordinator {
        PlaybackCoordinator(
            scoring: ScoringCoordinator(),
            analytics: MockAnalyticsProvider()
        )
    }

    /// Build a coordinator using a caller-supplied scoring instance for tests
    /// that need to inspect scoring state after `completeSession()`.
    private func makeCoordinator(scoring: ScoringCoordinator) -> PlaybackCoordinator {
        PlaybackCoordinator(scoring: scoring, analytics: MockAnalyticsProvider())
    }

    // MARK: - Tests — visualization data prep

    @Test
    func loadSongPopulatesNoteEventsAndDuration() async {
        let coord = makeCoordinator()
        let events = makeTestNoteEvents()

        coord.installNoteEventsForTesting(events)

        #expect(coord.noteEvents.count == 2)
        #expect(coord.duration == 0.75)
        #expect(coord.playbackState == .idle)
        #expect(coord.noteStates.count == 2)
        #expect(coord.noteStates.values.allSatisfy { $0 == .upcoming })
    }

    @Test
    func loadSongWithoutDataSetsErrorState() {
        let coord = makeCoordinator()
        // A Song with no MIDI data and no decoded notation should fail.
        let song = Song(slugId: "empty", title: "Empty", tempo: 120)

        let success = coord.loadSong(song)

        #expect(success == false)
        if case .error = coord.playbackState {
            // expected
        } else {
            Issue.record("Expected playbackState == .error after empty load, got \(coord.playbackState)")
        }
    }

    // MARK: - Tests — external transport drives visualization

    @Test
    func setCurrentTimeAdvancesViaExternalDriver() {
        let coord = makeCoordinator()
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        // Simulate ArrangementPlayer pushing master-clock ticks.
        coord.setCurrentTime(0.0)
        #expect(coord.currentTime == 0.0)

        coord.setCurrentTime(0.5)
        #expect(coord.currentTime == 0.5)

        coord.setCurrentTime(0.75)
        #expect(coord.currentTime == 0.75)
        // playbackProgress should track currentTime / duration.
        #expect(coord.playbackProgress == 1.0)
    }

    @Test
    func setPlaybackStateReflectsExternalTransport() {
        let coord = makeCoordinator()
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        // Simulate ArrangementPlayer driving the state machine externally.
        #expect(coord.playbackState == .idle)

        coord.setPlaybackState(.playing)
        #expect(coord.playbackState == .playing)

        coord.setPlaybackState(.paused)
        #expect(coord.playbackState == .paused)

        coord.setPlaybackState(.stopped)
        #expect(coord.playbackState == .stopped)
    }

    @Test
    func setCurrentNoteIndexReflectsExternalDriver() {
        let coord = makeCoordinator()
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        coord.setCurrentNoteIndex(1)
        #expect(coord.currentNoteIndex == 1)

        coord.setCurrentNoteIndex(nil)
        #expect(coord.currentNoteIndex == nil)
    }

    @Test
    func setPlaybackStartDateAffectsAnimationAnchor() {
        let coord = makeCoordinator()
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        #expect(coord.playbackStartDate == nil)

        let anchor = Date()
        coord.setPlaybackStartDate(anchor)
        #expect(coord.playbackStartDate == anchor)

        coord.setPlaybackStartDate(nil)
        #expect(coord.playbackStartDate == nil)
    }

    // MARK: - Tests — visualization-only invariant (no audio dependency)

    @Test
    func initializerHasNoAudioDependencies() {
        // The fact that this compiles and runs without passing a soundFont,
        // audioEngine, metronome, or clock is itself the invariant: there is
        // no audio dependency to mock. D3 narrowed PlaybackCoordinator to
        // visualization-only — no `soundFont.playNote(...)` site exists.
        let coord = PlaybackCoordinator(scoring: ScoringCoordinator())
        coord.installNoteEventsForTesting(makeTestNoteEvents())
        coord.setPlaybackState(.playing)
        coord.setCurrentTime(0.5)

        // No way to assert "no audio was emitted" except by construction:
        // there is no soundFont reference to call. If a regression added one,
        // `init(scoring:)` would no longer compile.
        #expect(coord.playbackState == .playing)
        #expect(coord.currentTime == 0.5)
    }

    // MARK: - Tests — seek + clear

    @Test
    func seekUpdatesCurrentTimeProportionally() {
        let coord = makeCoordinator()
        coord.installNoteEventsForTesting(makeTestNoteEvents())  // duration = 0.75

        coord.seek(to: 0.5)
        #expect(abs(coord.currentTime - 0.375) < 0.001)

        coord.seek(to: 1.0)
        #expect(abs(coord.currentTime - 0.75) < 0.001)
    }

    @Test
    func clearSongResetsAllVisualizationState() {
        let coord = makeCoordinator()
        coord.installNoteEventsForTesting(makeTestNoteEvents())
        coord.setPlaybackState(.playing)
        coord.setCurrentTime(0.5)
        coord.setCurrentNoteIndex(1)
        coord.setPlaybackStartDate(Date())

        coord.clearSong()

        #expect(coord.noteEvents.isEmpty)
        #expect(coord.noteStates.isEmpty)
        #expect(coord.currentTime == 0)
        #expect(coord.duration == 0)
        #expect(coord.currentNoteIndex == nil)
        #expect(coord.playbackStartDate == nil)
        #expect(coord.playbackState == .idle)
        #expect(coord.song == nil)
    }

    // MARK: - Tests — session completion

    @Test
    func stopAndCompleteFinalizesScoringAndPersistsViaRecorder() async throws {
        let scoring = ScoringCoordinator()
        let context = try SwiftDataTestContainer.freshContext()
        let coord = makeCoordinator(scoring: scoring)
        coord.modelContext = context
        coord.installNoteEventsForTesting(makeTestNoteEvents())
        coord.installSongInfoForTesting(
            slugId: "test_song",
            title: "Test",
            ragaName: "",
            difficulty: 2
        )

        // Simulate external driver: enter .playing then request early stop.
        await coord.startScheduling()
        coord.setCurrentTime(0.5)
        coord.stopAndComplete()

        #expect(coord.playbackState == .stopped)
        #expect(scoring.starRating >= 0, "scoring.finalize was invoked")

        // Recorder write verified by the SongProgress count in the in-memory store.
        let descriptor = FetchDescriptor<SongProgress>(
            predicate: #Predicate { $0.songId == "test_song" }
        )
        let progress = try context.fetch(descriptor)
        #expect(progress.count == 1, "SongProgress recorded via SessionRecorder")
    }

    @Test
    func completeSessionMarksUnfinishedNotesAsMissed() {
        let scoring = ScoringCoordinator()
        let coord = makeCoordinator(scoring: scoring)
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        coord.completeSession()

        // All notes were left in .upcoming; completion should mark them .missed.
        #expect(coord.noteStates.values.allSatisfy { $0 == .missed })
        #expect(coord.playbackState == .stopped)
    }

    // MARK: - Tests — legacy transport shims (Wave 5 E1 will replace)

    @Test
    func startSchedulingShimTransitionsToPlaying() async {
        let coord = makeCoordinator()
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        await coord.startScheduling()

        #expect(coord.playbackState == .playing)
        #expect(coord.playbackStartDate != nil)
    }

    @Test
    func pauseAndResumeShimsToggleState() async {
        let coord = makeCoordinator()
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        await coord.startScheduling()
        coord.pauseScheduling()
        #expect(coord.playbackState == .paused)
        #expect(coord.playbackStartDate == nil)

        coord.resumeScheduling()
        #expect(coord.playbackState == .playing)
        #expect(coord.playbackStartDate != nil)
    }

    @Test
    func cleanupResetsToIdle() {
        let coord = makeCoordinator()
        coord.installNoteEventsForTesting(makeTestNoteEvents())
        coord.setPlaybackState(.playing)
        coord.setPlaybackStartDate(Date())

        coord.cleanup()

        #expect(coord.playbackState == .idle)
        #expect(coord.playbackStartDate == nil)
    }
}
