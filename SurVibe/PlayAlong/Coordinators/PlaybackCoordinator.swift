// SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift
import Foundation
import SVAudio
import SVCore
import SVLearning
import SwiftData
import os.log

/// Visualization-only coordinator for the play-along / Learn-a-Song timeline.
///
/// Wave 4 D3 rework: PlaybackCoordinator no longer owns audio scheduling. It
/// is now a pure visualization-state owner — it keeps `noteEvents`,
/// `currentTime`, `currentNoteIndex`, `noteStates`, and `playbackState` in
/// sync with whatever external transport drives the session (Wave 5 E1 will
/// wire `ArrangementPlayer` as that driver). The coordinator is observed by
/// falling-notes / sheet rendering and by `NoteRouter` for input dispatch.
///
/// ## Removed in D3 (visualization-only narrowing)
/// - `soundFont` dependency and the scheduled-note `playNote(...)` path.
/// - `audioEngine.start/stop` lifecycle (ArrangementPlayer owns this).
/// - `metronome` lifecycle (ArrangementPlayer owns this).
/// - `clock` + drift-corrected scheduling loop (`runPlaybackLoop`).
/// - Internal display-link `Task` (`playbackStartDate` is set externally now).
/// - `PlayAlongWaitController` ownership (Wave 5 E1 will reattach if needed).
///
/// ## Public surface (visualization-only)
/// - `loadSong(_:)` — parse song into `noteEvents`; pure data prep.
/// - `clearSong()` — drop song + reset visualization to `.idle`.
/// - `setCurrentTime(_:)` — external driver (ArrangementPlayer) pushes time.
/// - `setPlaybackState(_:)` — external driver pushes transport state.
/// - `setCurrentNoteIndex(_:)` — external driver pushes the active index.
/// - `seek(to:)` — paused-only timeline scrub.
/// - `completeSession()` — finalise scoring + persist (still owned here
///   because it's a visualization-domain decision: "this song run is over").
/// - `cleanup()` — drop transient state.
///
/// Legacy transport methods (`startScheduling`, `pauseScheduling`,
/// `resumeScheduling`, `stopAndComplete`) are kept as thin no-op-style state
/// transitions so existing callers (`PlayAlongViewModel.startSession` etc.)
/// continue to compile. Wave 5 E1 (`ArrangementPlayer` wiring) replaces these
/// with direct `setPlaybackState(_:)` calls from the audio driver.
///
/// ## Latency invariants
/// - Never calls into `AudioEngineManager`.
/// - Never emits MIDI / SoundFont notes — there is no audio dependency at all.
@Observable
@MainActor
final class PlaybackCoordinator {
    // MARK: - Observed visualization state

    /// Current playback state (driven externally by the audio transport).
    private(set) var playbackState: PlaybackState = .idle

    /// Ordered note events for the loaded song. Used by falling-notes /
    /// sheet rendering and by `NoteRouter` for input dispatch.
    var noteEvents: [NoteEvent] = []

    /// Index of the note currently being played or evaluated.
    var currentNoteIndex: Int?

    /// Per-note state for the falling-notes / sheet view, keyed by `NoteEvent.id`.
    var noteStates: [UUID: FallingNotesLayoutEngine.NoteState] = [:]

    /// Current playback position in seconds from song start (driven externally).
    private(set) var currentTime: TimeInterval = 0

    /// Total duration of the loaded song in seconds.
    private(set) var duration: TimeInterval = 0

    /// Wall-clock Date adjusted to represent "when time=0 was", used by
    /// `FallingNotesView` to self-drive animation via `TimelineView`. Set by
    /// the external audio driver (E1: ArrangementPlayer) when it starts.
    private(set) var playbackStartDate: Date?

    /// Human-readable error message when `playbackState` is `.error`.
    private(set) var errorMessage: String?

    /// The loaded Song model (for tempo, ragaName, difficulty).
    private(set) var song: Song?

    // MARK: - Settable transport / display flags

    /// Tempo scaling factor (1.0 = original, 0.5 = half speed). Read by the
    /// external audio driver; this coordinator no longer reacts to changes.
    var tempoScale: Double = 1.0

    /// Whether wait mode is enabled for this session. Read by `NoteRouter`
    /// and by the external audio driver (E1).
    var isWaitModeEnabled: Bool = false

    /// Whether the song's playback audio is enabled. Read by the external
    /// audio driver and by tanpura UI; this coordinator does not emit audio.
    var isSoundEnabled: Bool = true

    // MARK: - Persistence

    /// Model context for persisting session results via `SessionRecorder`.
    /// Set by the facade from `SongPlayAlongView.onAppear`.
    var modelContext: ModelContext?

    // MARK: - Computed

    /// Normalized playback progress (0.0 to 1.0) for the timeline scrubber.
    var playbackProgress: Double {
        guard duration > 0 else { return 0 }
        return min(1.0, max(0.0, currentTime / duration))
    }

    /// Total playback duration in seconds, exposed for the toolbar timeline.
    var playbackDuration: TimeInterval { duration }

    // MARK: - Dependencies (injected)

    private let scoring: ScoringCoordinator
    private let analytics: (any AnalyticsProviding)?

    private static let logger = Logger.survibe(category: "PlaybackCoordinator")

    // MARK: - Initialization

    /// Create a visualization-only playback coordinator.
    ///
    /// - Parameters:
    ///   - scoring: Scoring coordinator (SP-3a) — used by `completeSession()`
    ///     to finalise + persist the run.
    ///   - analytics: Analytics provider (nil → falls back to
    ///     `AnalyticsManager.shared` at call time per SP-0 nil-sentinel).
    init(
        scoring: ScoringCoordinator,
        analytics: (any AnalyticsProviding)? = nil
    ) {
        self.scoring = scoring
        self.analytics = analytics
    }

    // MARK: - Public methods — song lifecycle

    /// Parse the song into `noteEvents`, compute duration, initialize per-note
    /// state. Pure data prep — no audio or input wiring.
    ///
    /// - Returns: `true` on success, `false` if neither MIDI nor notation
    ///   data was available (in which case `playbackState` is set to `.error`).
    @discardableResult
    func loadSong(_ song: Song) -> Bool {
        playbackState = .loading
        self.song = song

        // T5': JSON-blob notation fallback (`song.decodedSargamNotes` /
        // `decodedWesternNotes`) removed. The canonical pipeline is now
        // `midiData` only. Songs without `midiData` fall through to the
        // error branch.
        let result: Bool
        if let midiData = song.midiData, !midiData.isEmpty,
            case .success(let midiEvents) = MIDIParser.parse(data: midiData)
        {
            noteEvents = NoteEvent.fromMIDI(events: midiEvents)
            result = true
        } else {
            errorMessage = "No playable notation found"
            playbackState = .error("No playable notation")
            Self.logger.error("loadSong failed: no MIDI data")
            return false
        }

        if let last = noteEvents.last {
            duration = last.timestamp + last.duration
        }
        for event in noteEvents {
            noteStates[event.id] = .upcoming
        }

        currentNoteIndex = noteEvents.isEmpty ? nil : 0
        playbackState = .idle
        Self.logger.info(
            "Song loaded: \(self.noteEvents.count) events, duration=\(String(format: "%.1f", self.duration))s"
        )
        return result
    }

    /// Replace `noteEvents` with a pre-built array (from LearnerScore).
    ///
    /// Used by Wave 5 E1.5: when `PartSplitter` produces a learner score
    /// from a freshly-rendered MXL, the resulting `ExpectedNote` array is
    /// converted to `NoteEvent`s and seeded directly so visualization has
    /// data even when the legacy `MIDIParser.parse(midiData)` path
    /// produces zero events.
    ///
    /// - Parameter events: Pre-built note events.
    func setNoteEvents(_ events: [NoteEvent]) {
        noteEvents = events
        if let last = events.last {
            duration = last.timestamp + last.duration
        }
        noteStates = [:]
        for event in events { noteStates[event.id] = .upcoming }
        currentNoteIndex = events.isEmpty ? nil : 0
        if case .error = playbackState {
            playbackState = .idle
            errorMessage = nil
        }
        Self.logger.info(
            "setNoteEvents: \(events.count) events, duration=\(String(format: "%.1f", self.duration))s"
        )
    }

    /// Drop the loaded song and reset all visualization state to `.idle`.
    func clearSong() {
        song = nil
        noteEvents = []
        noteStates = [:]
        currentNoteIndex = nil
        currentTime = 0
        duration = 0
        playbackStartDate = nil
        errorMessage = nil
        playbackState = .idle
    }

    /// Seek to a normalized position (0.0 to 1.0). Only effective when paused —
    /// matches the prior behavior; full mid-playback seek is the audio driver's
    /// responsibility (E1: ArrangementPlayer).
    func seek(to progress: Double) {
        guard duration > 0 else { return }
        currentTime = progress * duration
    }

    // MARK: - External transport setters (driven by ArrangementPlayer in E1)

    /// Push the master clock's current time into the visualization model.
    ///
    /// Called by the external audio driver (E1: `ArrangementPlayer`) on every
    /// display tick. Visualization observers (`FallingNotesView`,
    /// `currentTime`-bound UI) react automatically through `@Observable`.
    func setCurrentTime(_ time: TimeInterval) {
        currentTime = time
    }

    /// Push a new transport state from the external audio driver.
    ///
    /// Idempotent: setting to the same state is a no-op.
    func setPlaybackState(_ state: PlaybackState) {
        playbackState = state
    }

    /// Push the active note index from the external audio driver.
    func setCurrentNoteIndex(_ index: Int?) {
        currentNoteIndex = index
    }

    /// Set the wall-clock anchor used by `FallingNotesView` self-driving
    /// animation. The external audio driver sets this on `start()` / `resume()`
    /// and clears to `nil` on `pause()`.
    func setPlaybackStartDate(_ date: Date?) {
        playbackStartDate = date
    }

    // MARK: - Legacy transport shims (Wave 5 E1 will replace with direct setters)

    /// Legacy entry point preserved so existing facade callers compile during
    /// the Wave 4 → Wave 5 transition. Performs only a state transition; audio
    /// is owned by ArrangementPlayer (E1).
    ///
    /// TODO(E1): replace facade calls with `ArrangementPlayer.start()` and
    /// remove this shim.
    func startScheduling() async {
        guard playbackState == .idle || playbackState == .stopped else { return }
        guard !noteEvents.isEmpty else { return }
        reset()
        playbackStartDate = Date()
        playbackState = .playing
        track(
            .songPlaybackStarted,
            properties: [
                "song_title": song?.title ?? "",
                "tempo_scale": tempoScale,
                "wait_mode": isWaitModeEnabled,
            ]
        )
    }

    /// Legacy pause shim. State transition only — audio pause is the driver's
    /// responsibility (E1).
    ///
    /// TODO(E1): replace with `ArrangementPlayer.pause()` + `setPlaybackState(.paused)`.
    func pauseScheduling() {
        guard playbackState == .playing else { return }
        playbackState = .paused
        playbackStartDate = nil
        track(.songPlaybackPaused, properties: ["song_title": song?.title ?? ""])
    }

    /// Legacy resume shim. State transition only — audio resume is the driver's
    /// responsibility (E1).
    ///
    /// TODO(E1): replace with `ArrangementPlayer.resume()` + `setPlaybackState(.playing)`.
    func resumeScheduling() {
        guard playbackState == .paused else { return }
        playbackStartDate = Date(timeIntervalSinceNow: -currentTime)
        playbackState = .playing
    }

    /// Stop the session early and complete with whatever has been scored so far.
    func stopAndComplete() {
        guard playbackState == .playing || playbackState == .paused else { return }
        completeSession()
    }

    // MARK: - Public — Session completion

    /// Complete the session: mark unfinished notes as missed, finalize scoring,
    /// persist results, fire analytics.
    ///
    /// AUD-028/034: noteStates mutations batched into a single dictionary
    /// snapshot — one Canvas redraw instead of N individual property sets.
    func completeSession() {
        let scoredNames = Set(scoring.noteScores.map(\.expectedNote))
        var updatedStates = noteStates
        var missedScores: [NoteScore] = []

        for event in noteEvents {
            let state = updatedStates[event.id]
            if state == .active || state == .upcoming {
                updatedStates[event.id] = .missed
                if !scoredNames.contains(event.swarName) {
                    missedScores.append(
                        NoteScoreCalculator.missedNote(expectedNote: event.swarName)
                    )
                }
            }
        }

        noteStates = updatedStates
        missedScores.forEach { scoring.record($0) }

        scoring.finalize(songDifficulty: song?.difficulty ?? 1)

        playbackState = .stopped
        playbackStartDate = nil

        persistSessionResults()
        trackSessionCompletion()
    }

    /// Tear down transient visualization resources. Audio teardown is the
    /// external driver's responsibility (E1: `ArrangementPlayer.stop()`).
    func cleanup() {
        playbackState = .idle
        playbackStartDate = nil
        Self.logger.info("PlaybackCoordinator cleanup complete (visualization-only)")
    }

    // MARK: - Internal helpers

    /// Reset visualization state for a fresh run. Does NOT touch
    /// NoteRouter-territory state.
    func reset() {
        scoring.reset()
        currentNoteIndex = noteEvents.isEmpty ? nil : 0
        currentTime = 0
        errorMessage = nil
        for event in noteEvents {
            noteStates[event.id] = .upcoming
        }
    }

    // MARK: - Test seams (internal — do not call from production code)

    /// Install raw `NoteEvent`s for tests, bypassing the full `loadSong` flow.
    func installNoteEventsForTesting(_ events: [NoteEvent]) {
        noteEvents = events
        if let last = events.last {
            duration = last.timestamp + last.duration
        }
        for event in events {
            noteStates[event.id] = .upcoming
        }
        currentNoteIndex = events.isEmpty ? nil : 0
    }

    /// Install a synthetic song with the given tempo for tempo-scale tests.
    func installSongTempoForTesting(_ tempo: Int) {
        song = Song(tempo: tempo)
    }

    /// Install a synthetic song with persistence-relevant fields for completion tests.
    func installSongInfoForTesting(
        slugId: String,
        title: String,
        ragaName: String,
        difficulty: Int
    ) {
        song = Song(slugId: slugId, title: title, difficulty: difficulty, ragaName: ragaName)
    }

    // MARK: - Private — Analytics

    /// Dispatch an event via the injected analytics, falling back to the
    /// shared singleton (nil-sentinel per SP-0 D-SP0-1).
    private func track(_ event: AnalyticsEvent, properties: [String: any Sendable]?) {
        let provider: any AnalyticsProviding = analytics ?? AnalyticsManager.shared
        provider.track(event, properties: properties)
    }

    // MARK: - Private — Persistence

    private func persistSessionResults() {
        guard let modelContext, let song else { return }
        let recorder = SessionRecorder(modelContext: modelContext)
        let songInfo = SessionSongInfo(
            songId: song.slugId.isEmpty ? song.id.uuidString : song.slugId,
            songTitle: song.title,
            ragaName: song.ragaName,
            difficulty: song.difficulty
        )
        let durationMinutes = max(1, Int(currentTime / 60))
        recorder.recordSession(
            songInfo: songInfo,
            durationMinutes: durationMinutes,
            noteScores: scoring.noteScores
        )
        Self.logger.info("Session persisted via SessionRecorder")
    }

    private func trackSessionCompletion() {
        track(
            .songPlaybackCompleted,
            properties: [
                "song_title": song?.title ?? "",
                "accuracy": scoring.accuracy,
                "star_rating": scoring.starRating,
                "xp_earned": scoring.xpEarned,
                "tempo_scale": tempoScale,
            ]
        )
        Self.logger.info(
            "Session completed: accuracy=\(String(format: "%.0f", self.scoring.accuracy * 100))%"
        )
    }
}
