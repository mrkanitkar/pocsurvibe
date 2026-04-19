// SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift
import Foundation
import SVAudio
import SVCore
import SVLearning
import SwiftData
import os.log

/// Owns the play-along transport state machine: scheduling, tempo, wait-mode,
/// session completion, and `PracticeSessionRecorder`-mediated SwiftData writes.
///
/// Extracted from `PlayAlongViewModel` in SP-3b. The facade
/// (`PlayAlongViewModel`) holds `let playback = PlaybackCoordinator(...)` and
/// re-exposes every owned property as a delegating computed property so
/// existing views/tests continue to read `viewModel.playbackState` etc.
/// unchanged (spec AD-1 facade).
///
/// ## Public surface (Option B per spec §11 D-SP3b-1)
/// - `loadSong(_:)` — parse song into `noteEvents` + `noteStates`; pure data prep.
/// - `startScheduling()` — engine.start + metronome + reset + display-link + schedule.
/// - `pauseScheduling()` — save `pauseElapsed`, cancel tasks, stop metronome.
/// - `resumeScheduling()` — advance start time by `pauseElapsed`, restart tasks.
/// - `stopAndComplete()` — early stop → `completeSession()`.
/// - `seek(to:)` — set `currentTime` (only effective when paused; matches VM's prior behavior).
/// - `cleanup()` — playback-side resources only (engine.stop, metronome.stop, sound off, tasks cancel).
///
/// ## Out of scope (still on VM facade until SP-3d)
/// - Pitch detection (mic + chord), MIDI input routing, guided-play state,
///   patience timer, raga-aware mapping. The VM composes `playback.startScheduling()`
///   with those still-on-VM hooks; SP-3d collapses them into NoteRouter.
///
/// ## Latency invariants (non-negotiable)
/// - Never calls `AudioEngineManager.shared.noteOn(...)` — that's NoteRouter's site.
/// - Only calls `soundFont.playNote(...)` for scheduled playback notes (the song's notes,
///   not user-input notes).
/// - No new `await` on the MIDI → noteOn path (path is entirely outside this class).
@Observable
@MainActor
final class PlaybackCoordinator {
    // MARK: - Observed playback state

    /// Current playback state of the play-along session.
    private(set) var playbackState: PlaybackState = .idle

    /// Ordered note events for the loaded song.
    var noteEvents: [NoteEvent] = []

    /// Index of the note currently being played or evaluated.
    var currentNoteIndex: Int?

    /// Per-note state for the falling-notes / sheet view, keyed by `NoteEvent.id`.
    ///
    /// Exposed as `var` (not `private(set)`) for SP-3b transitional convenience —
    /// still-on-VM NoteRouter-territory code (`skipGuidedNote`, `processNoteInput`)
    /// writes via `playback.noteStates[id] = .missed`. SP-3d locks this down once
    /// NoteRouter owns the writers.
    var noteStates: [UUID: FallingNotesLayoutEngine.NoteState] = [:]

    /// Current playback position in seconds from song start.
    private(set) var currentTime: TimeInterval = 0

    /// Total duration of the loaded song in seconds.
    private(set) var duration: TimeInterval = 0

    /// Wall-clock Date adjusted to represent "when time=0 was", used by
    /// `FallingNotesView` to self-drive animation via `TimelineView`.
    private(set) var playbackStartDate: Date?

    /// Human-readable error message when `playbackState` is `.error`.
    private(set) var errorMessage: String?

    /// The loaded Song model (for tempo, ragaName, difficulty).
    ///
    /// Internal write so the test seam can install a song info without
    /// running the full `loadSong` notation-parsing flow.
    private(set) var song: Song?

    // MARK: - Observed transport-control state (settable from facade/UI)

    /// Tempo scaling factor (1.0 = original, 0.5 = half speed). Updates the
    /// metronome BPM live when playing.
    var tempoScale: Double = 1.0 {
        didSet {
            if metronome.isPlaying, let song {
                metronome.setBPM(Double(song.tempo) * tempoScale)
            }
        }
    }

    /// Whether wait mode is enabled for this session. Read at `startScheduling`
    /// time to construct the `waitController`.
    var isWaitModeEnabled: Bool = false

    /// Whether SoundFont playback is enabled (controls whether scheduled notes
    /// trigger `soundFont.playNote`).
    var isSoundEnabled: Bool = true

    // MARK: - Persistence

    /// Model context for persisting session results via `PracticeSessionRecorder`.
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

    private let soundFont: any SoundFontPlaying
    private let audioEngine: any AudioEngineProviding
    private let metronome: any MetronomePlaying
    private let clock: any ClockProviding
    private let scoring: ScoringCoordinator
    private let analytics: (any AnalyticsProviding)?

    // MARK: - Internal scheduling state

    private var waitController: PlayAlongWaitController?
    private var playbackTask: Task<Void, Never>?
    private var displayLinkTask: Task<Void, Never>?
    private var playbackStartTime: ContinuousClock.Instant?
    private var pauseElapsed: TimeInterval = 0

    private static let logger = Logger.survibe(category: "PlaybackCoordinator")

    // MARK: - Initialization

    /// Create a playback coordinator with injectable dependencies.
    ///
    /// - Parameters:
    ///   - soundFont: SoundFont player for scheduled playback notes.
    ///   - audioEngine: Audio engine for `start()` / `stop()` lifecycle.
    ///   - metronome: Metronome player driven by `tempoScale` × `song.tempo`.
    ///   - clock: Drift-corrected clock for scheduling.
    ///   - scoring: Scoring coordinator (SP-3a) for `record/updateStreak/finalize/reset`.
    ///   - analytics: Analytics provider (nil → falls back to `AnalyticsManager.shared`
    ///     at call time per SP-0 D-SP0-1 / SP-1 D-SP1-1 nil-sentinel pattern).
    init(
        soundFont: any SoundFontPlaying,
        audioEngine: any AudioEngineProviding,
        metronome: any MetronomePlaying,
        clock: any ClockProviding,
        scoring: ScoringCoordinator,
        analytics: (any AnalyticsProviding)? = nil
    ) {
        self.soundFont = soundFont
        self.audioEngine = audioEngine
        self.metronome = metronome
        self.clock = clock
        self.scoring = scoring
        self.analytics = analytics
    }

    // MARK: - Public methods (transport state machine)

    /// Parse the song into `noteEvents`, compute duration, initialize per-note
    /// state. Pure data prep — no audio or input wiring.
    ///
    /// - Returns: `true` on success, `false` if neither MIDI nor notation
    ///   data was available (in which case `playbackState` is set to `.error`).
    @discardableResult
    func loadSong(_ song: Song) -> Bool {
        playbackState = .loading
        self.song = song

        if let midiData = song.midiData, !midiData.isEmpty,
            case .success(let midiEvents) = MIDIParser.parse(data: midiData)
        {
            noteEvents = NoteEvent.fromMIDI(events: midiEvents)
        } else if let sargam = song.decodedSargamNotes,
            let western = song.decodedWesternNotes
        {
            noteEvents = NoteEvent.fromNotation(
                sargamNotes: sargam,
                westernNotes: western,
                tempo: song.tempo
            )
        } else {
            errorMessage = "No playable notation found"
            playbackState = .error("No playable notation")
            Self.logger.error("loadSong failed: no MIDI or notation data")
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
        return true
    }

    /// Seek to a normalized position (0.0 to 1.0). Only effective when paused —
    /// matches the existing VM behavior; full mid-playback seek is out of scope
    /// for SP-3b (would require re-anchoring `playbackStartTime` and rescheduling).
    func seek(to progress: Double) {
        guard duration > 0 else { return }
        currentTime = progress * duration
    }

    /// Start scheduling the loaded song from the beginning. Idempotent guard:
    /// only starts from `.idle` or `.stopped` with non-empty `noteEvents`.
    ///
    /// Sequence:
    /// 1. Engine `start()` (in playAndRecord — caller already configured session).
    /// 2. Metronome setBPM + start at `tempoScale × song.tempo`.
    /// 3. `reset()` clears scoring + position.
    /// 4. `playbackStartTime` = `clock.now`; `playbackStartDate` = `Date()`.
    /// 5. Transition to `.playing`, start display link, kick off the playback loop.
    /// 6. If `isWaitModeEnabled`, construct the `waitController`.
    /// 7. Fire `songPlaybackStarted` analytics.
    func startScheduling() async {
        guard playbackState == .idle || playbackState == .stopped else { return }
        guard !noteEvents.isEmpty else { return }

        do {
            try audioEngine.start()
        } catch {
            Self.logger.error("Engine start failed: \(error.localizedDescription)")
            errorMessage = "Audio engine failed to start"
            playbackState = .error("Audio engine failed to start")
            return
        }

        let scaledBPM = Double(song?.tempo ?? 120) * tempoScale
        metronome.setBPM(scaledBPM)
        metronome.start()

        reset()

        playbackStartTime = clock.now
        playbackStartDate = Date()
        playbackState = .playing

        startDisplayLink()
        startPlayback()

        if isWaitModeEnabled {
            waitController = PlayAlongWaitController(noteEvents: noteEvents)
        } else {
            waitController = nil
        }

        track(
            .songPlaybackStarted,
            properties: [
                "song_title": song?.title ?? "",
                "tempo_scale": tempoScale,
                "wait_mode": isWaitModeEnabled,
            ]
        )

        Self.logger.info("Playback scheduling started")
    }

    /// Pause the active scheduling. Records elapsed time for seamless resume,
    /// cancels the playback + display-link tasks, stops sounding notes and
    /// metronome.
    func pauseScheduling() {
        guard playbackState == .playing else { return }

        if let startTime = playbackStartTime {
            let elapsed = clock.now - startTime
            pauseElapsed = elapsedSeconds(from: elapsed)
        }

        playbackState = .paused
        playbackStartDate = nil

        cancelPlaybackTasks()
        soundFont.stopAllNotes()
        metronome.stop()

        track(.songPlaybackPaused, properties: ["song_title": song?.title ?? ""])
        Self.logger.info("Scheduling paused at \(String(format: "%.1f", self.pauseElapsed))s")
    }

    /// Resume from the paused position. Adjusts the clock reference so elapsed
    /// computation continues from the pause offset, restarts display link +
    /// playback loop + metronome.
    func resumeScheduling() {
        guard playbackState == .paused else { return }

        playbackStartTime = clock.now.advanced(by: .seconds(-pauseElapsed))
        playbackStartDate = Date(timeIntervalSinceNow: -pauseElapsed)
        playbackState = .playing

        startDisplayLink()
        startPlaybackFromCurrentPosition()
        metronome.start()

        Self.logger.info("Scheduling resumed from \(String(format: "%.1f", self.pauseElapsed))s")
    }

    // MARK: - Private — Scheduling

    private func startPlayback() {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.runPlaybackLoop(fromIndex: 0, timeOffset: 0)
        }
    }

    private func startPlaybackFromCurrentPosition() {
        playbackTask?.cancel()
        let offset = pauseElapsed
        let startIndex =
            noteEvents.firstIndex { event in
                (event.timestamp / tempoScale) >= offset
            } ?? noteEvents.count

        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.runPlaybackLoop(fromIndex: startIndex, timeOffset: 0)
        }
    }

    private func runPlaybackLoop(fromIndex: Int, timeOffset: TimeInterval) async {
        guard let startTime = playbackStartTime else { return }

        for index in fromIndex..<noteEvents.count {
            let event = noteEvents[index]
            let scaledTimestamp = event.timestamp / tempoScale
            let targetTime = startTime.advanced(by: .seconds(scaledTimestamp))

            let sleepDuration = targetTime - clock.now
            if sleepDuration > .zero {
                do {
                    try await clock.sleep(for: sleepDuration)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }

            playNoteSound(event: event)

            currentNoteIndex = index
            noteStates[event.id] = .active
            markPreviousNotesAsMissed(beforeIndex: index)

            do {
                if try await awaitWaitModeResolution(index: index) {
                    return
                }
            } catch {
                return
            }
        }

        await awaitLastNoteCompletion()
        guard !Task.isCancelled else { return }
        completeSession()
    }

    private func playNoteSound(event: NoteEvent) {
        guard isSoundEnabled else { return }
        soundFont.playNote(
            midiNote: event.midiNote,
            velocity: event.velocity,
            channel: 0
        )
        let scaledDuration = event.duration / tempoScale
        Task { [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(for: .seconds(scaledDuration))
            self.soundFont.stopNote(midiNote: event.midiNote, channel: 0)
        }
    }

    private func markPreviousNotesAsMissed(beforeIndex index: Int) {
        for prevIndex in 0..<index {
            let prevEvent = noteEvents[prevIndex]
            if noteStates[prevEvent.id] == .active {
                noteStates[prevEvent.id] = .missed
                scoring.record(NoteScoreCalculator.missedNote(expectedNote: prevEvent.swarName))
                scoring.updateStreak(grade: .miss)
            }
        }
    }

    private func awaitWaitModeResolution(index: Int) async throws -> Bool {
        guard isWaitModeEnabled, let waitCtrl = waitController else { return false }
        waitCtrl.setCurrentNoteIndex(index)
        while waitCtrl.isWaitingForNote, !Task.isCancelled {
            try? await clock.sleep(for: .milliseconds(50))
        }
        return Task.isCancelled
    }

    private func awaitLastNoteCompletion() async {
        guard let last = noteEvents.last else { return }
        let endTime = (last.timestamp + last.duration) / tempoScale
        let startTime = playbackStartTime ?? clock.now
        let targetEnd = startTime.advanced(by: .seconds(endTime))
        let remaining = targetEnd - clock.now
        if remaining > .zero {
            try? await clock.sleep(for: remaining)
        }
    }

    // MARK: - Private — Display Link

    private func startDisplayLink() {
        displayLinkTask?.cancel()
        displayLinkTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.playbackState == .playing else { return }
                if let startTime = self.playbackStartTime {
                    let elapsed = self.clock.now - startTime
                    self.currentTime = self.elapsedSeconds(from: elapsed) * self.tempoScale
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
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

    // MARK: - Internal helpers (placeholders for Tasks 4 + 5)

    /// Cancel scheduled playback tasks (does NOT touch pitch/MIDI tasks —
    /// those are the facade's responsibility until SP-3d).
    func cancelPlaybackTasks() {
        playbackTask?.cancel()
        playbackTask = nil
        displayLinkTask?.cancel()
        displayLinkTask = nil
    }

    /// Reset playback-domain state for a fresh scheduling pass. Called by
    /// `startScheduling()`. Does NOT reset NoteRouter-territory state
    /// (`expectedMidiNote`, `guidedPlayState`, `patienceTimerTask`) — those
    /// stay on the facade until SP-3d.
    func reset() {
        scoring.reset()
        currentNoteIndex = nil
        currentTime = 0
        pauseElapsed = 0
        errorMessage = nil
        for event in noteEvents {
            noteStates[event.id] = .upcoming
        }
    }

    /// Convert a `Duration` to seconds as a `TimeInterval`.
    func elapsedSeconds(from duration: Duration) -> TimeInterval {
        Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    }

    // MARK: - Private — Analytics

    /// Dispatch an event via the injected analytics, falling back to the
    /// shared singleton (nil-sentinel per SP-0 D-SP0-1).
    private func track(_ event: AnalyticsEvent, properties: [String: any Sendable]?) {
        let provider: any AnalyticsProviding = analytics ?? AnalyticsManager.shared
        provider.track(event, properties: properties)
    }

    // MARK: - Public — Session completion

    /// Stop scheduling early and complete the session with whatever notes
    /// have been scored so far. Triggers results overlay.
    func stopAndComplete() {
        guard playbackState == .playing || playbackState == .paused else { return }
        completeSession()
    }

    /// Complete the session: mark unfinished notes as missed, finalize scoring,
    /// stop sound, persist results, fire analytics.
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

        cancelPlaybackTasks()
        soundFont.stopAllNotes()
        playbackState = .stopped

        persistSessionResults()
        trackSessionCompletion()
    }

    /// Tear down playback resources. Does NOT touch pitch/MIDI tasks — those
    /// are the facade's responsibility until SP-3d.
    func cleanup() {
        cancelPlaybackTasks()
        soundFont.stopAllNotes()
        SoundFontManager.shared.resetLoadedState()
        audioEngine.stop()
        metronome.stop()
        waitController?.reset()
        waitController = nil
        playbackState = .idle
        Self.logger.info("PlaybackCoordinator cleanup complete")
    }

    // MARK: - Private — Persistence

    private func persistSessionResults() {
        guard let modelContext, let song else { return }
        let recorder = PracticeSessionRecorder(modelContext: modelContext)
        let songInfo = SessionSongInfo(
            songId: song.slugId.isEmpty ? song.id.uuidString : song.slugId,
            songTitle: song.title,
            ragaName: song.ragaName,
            difficulty: song.difficulty
        )
        let durationMinutes = max(1, Int(pauseElapsed / 60))
        recorder.recordSession(
            songInfo: songInfo,
            durationMinutes: durationMinutes,
            noteScores: scoring.noteScores
        )
        Self.logger.info("Session persisted via PracticeSessionRecorder")
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
