// SurVibeTests/PlaybackCoordinatorTests.swift
import Foundation
import SVAudio
import SwiftData
import Testing
@testable import SurVibe

/// Unit tests for `PlaybackCoordinator` (SP-3b).
///
/// `PlaybackCoordinator` is the transport state machine + scheduling +
/// session-completion + `PracticeSessionRecorder`-mediated SwiftData write
/// extracted from `PlayAlongViewModel`. Owns the playback domain only;
/// pitch detection / MIDI input remain on the VM facade until SP-3d.
///
/// ## Mock surface
/// - `MockAudioEngineProvider` (SP-0) — exposes `startCallCount`, `stopCallCount`.
/// - `MockSoundFontPlayer` (SP-0) — exposes `stopAllNotesCallCount`.
/// - `MockMetronomePlayer` (SP-0) — exposes `startCallCount`, `stopCallCount`, `bpm`.
/// - `MockAnalyticsProvider` (SP-1) — records tracked events.
/// - `NoteEventFactory` (test helper) — builds NoteEvents with correct UInt8 types.
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

    /// Build a coordinator with fully customisable dependencies.
    ///
    /// Default parameter expressions for `@MainActor` types cannot be used
    /// in function signatures (evaluated in nonisolated context), so each
    /// parameter is mandatory; callers that don't need to inspect a mock
    /// should pass a freshly-created instance inline.
    private func makeCoordinator(
        engine: MockAudioEngineProvider,
        soundFont: MockSoundFontPlayer,
        metronome: MockMetronomePlayer,
        scoring: ScoringCoordinator,
        analytics: MockAnalyticsProvider
    ) -> PlaybackCoordinator {
        PlaybackCoordinator(
            soundFont: soundFont,
            audioEngine: engine,
            metronome: metronome,
            clock: RealClock(),
            scoring: scoring,
            analytics: analytics
        )
    }

    /// Convenience overload — creates fresh mocks for tests that don't inspect them.
    private func makeCoordinator() -> PlaybackCoordinator {
        makeCoordinator(
            engine: MockAudioEngineProvider(),
            soundFont: MockSoundFontPlayer(),
            metronome: MockMetronomePlayer(),
            scoring: ScoringCoordinator(),
            analytics: MockAnalyticsProvider()
        )
    }

    // MARK: - Tests

    @Test func loadSongPopulatesNoteEventsAndDuration() async {
        let coord = makeCoordinator()
        let events = makeTestNoteEvents()

        coord.installNoteEventsForTesting(events)

        #expect(coord.noteEvents.count == 2)
        #expect(coord.duration == 0.75)
        #expect(coord.currentNoteIndex == nil)
        #expect(coord.playbackState == .idle)
    }

    @Test func startSchedulingTransitionsToPlaying() async throws {
        let engine = MockAudioEngineProvider()
        let metronome = MockMetronomePlayer()
        let coord = makeCoordinator(
            engine: engine,
            soundFont: MockSoundFontPlayer(),
            metronome: metronome,
            scoring: ScoringCoordinator(),
            analytics: MockAnalyticsProvider()
        )
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        await coord.startScheduling()

        #expect(coord.playbackState == .playing)
        #expect(engine.startCallCount == 1, "Engine started exactly once")
        #expect(metronome.startCallCount == 1, "Metronome started")
        #expect(coord.playbackStartDate != nil, "Self-driving timeline date set")
    }

    @Test func pauseSchedulingPreservesPauseElapsedAndStopsMetronome() async throws {
        let metronome = MockMetronomePlayer()
        let coord = makeCoordinator(
            engine: MockAudioEngineProvider(),
            soundFont: MockSoundFontPlayer(),
            metronome: metronome,
            scoring: ScoringCoordinator(),
            analytics: MockAnalyticsProvider()
        )
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        await coord.startScheduling()
        // Allow a brief slice of wall-clock time to accumulate.
        try await Task.sleep(for: .milliseconds(20))
        coord.pauseScheduling()

        #expect(coord.playbackState == .paused)
        #expect(metronome.stopCallCount >= 1)
        #expect(coord.playbackStartDate == nil, "Date frozen on pause")
    }

    @Test func resumeSchedulingTransitionsBackToPlaying() async throws {
        let metronome = MockMetronomePlayer()
        let coord = makeCoordinator(
            engine: MockAudioEngineProvider(),
            soundFont: MockSoundFontPlayer(),
            metronome: metronome,
            scoring: ScoringCoordinator(),
            analytics: MockAnalyticsProvider()
        )
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        await coord.startScheduling()
        try await Task.sleep(for: .milliseconds(20))
        coord.pauseScheduling()
        coord.resumeScheduling()

        #expect(coord.playbackState == .playing)
        #expect(metronome.startCallCount >= 2, "Metronome started on resume")
        #expect(coord.playbackStartDate != nil, "Date re-set on resume")
    }

    @Test func tempoScaleSetterUpdatesMetronomeBPM() async {
        let metronome = MockMetronomePlayer()
        let coord = makeCoordinator(
            engine: MockAudioEngineProvider(),
            soundFont: MockSoundFontPlayer(),
            metronome: metronome,
            scoring: ScoringCoordinator(),
            analytics: MockAnalyticsProvider()
        )
        coord.installNoteEventsForTesting(makeTestNoteEvents())
        coord.installSongTempoForTesting(120)

        // Start first so metronome.isPlaying == true, allowing the didSet branch to fire.
        await coord.startScheduling()
        coord.tempoScale = 0.5

        // tempoScale 0.5 on a 120-BPM song → setBPM(60).
        #expect(metronome.bpm == 60.0,
                "tempoScale 0.5 on 120 BPM song → metronome BPM == 60")
    }

    @Test func stopAndCompleteFinalizesScoringAndPersistsViaRecorder() async throws {
        let scoring = ScoringCoordinator()
        let metronome = MockMetronomePlayer()
        let soundFont = MockSoundFontPlayer()

        let context = try SwiftDataTestContainer.freshContext()
        let coord = makeCoordinator(
            engine: MockAudioEngineProvider(),
            soundFont: soundFont,
            metronome: metronome,
            scoring: scoring,
            analytics: MockAnalyticsProvider()
        )
        coord.modelContext = context
        coord.installNoteEventsForTesting(makeTestNoteEvents())
        coord.installSongInfoForTesting(
            slugId: "test_song", title: "Test", ragaName: "", difficulty: 2
        )

        await coord.startScheduling()
        try await Task.sleep(for: .milliseconds(20))
        coord.stopAndComplete()

        #expect(coord.playbackState == .stopped)
        #expect(soundFont.stopAllNotesCallCount >= 1, "Stops sounding notes on completion")
        #expect(scoring.starRating >= 0, "scoring.finalize was invoked")

        // Recorder write verified by the SongProgress count in the in-memory store.
        let descriptor = FetchDescriptor<SongProgress>(
            predicate: #Predicate { $0.songId == "test_song" }
        )
        let progress = try context.fetch(descriptor)
        #expect(progress.count == 1, "SongProgress recorded via PracticeSessionRecorder")
    }

    @Test func cleanupCancelsTasksStopsAudioAndResetsState() async throws {
        let engine = MockAudioEngineProvider()
        let metronome = MockMetronomePlayer()
        let soundFont = MockSoundFontPlayer()
        let coord = makeCoordinator(
            engine: engine,
            soundFont: soundFont,
            metronome: metronome,
            scoring: ScoringCoordinator(),
            analytics: MockAnalyticsProvider()
        )
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        await coord.startScheduling()
        try await Task.sleep(for: .milliseconds(20))
        coord.cleanup()

        #expect(coord.playbackState == .idle)
        #expect(engine.stopCallCount == 1, "Engine stopped exactly once on cleanup")
        #expect(metronome.stopCallCount >= 1)
        #expect(soundFont.stopAllNotesCallCount >= 1)
    }
}
