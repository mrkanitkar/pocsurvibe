import Foundation
import SwiftData
import SVAudio
import SVCore
import SVLearning
import os.log

/// Phases of a practice session.
///
/// The session flows linearly: listen first -> practice along -> completed.
/// Users can skip the listen phase to go directly to practice.
enum PracticePhase: Equatable, Sendable {
    /// Song is being loaded and prepared.
    case loading
    /// Listen-first phase: song plays back for the user to hear.
    case listenFirst
    /// Active practice: user plays along while pitch is monitored.
    case practiceAlong
    /// Session complete: results computed, ready for summary display.
    case completed
    /// An error occurred during the session.
    case error(String)
}

/// Orchestrates the complete practice session lifecycle.
///
/// Manages three phases: listen-first playback, practice-along with real-time
/// pitch monitoring and scoring, and session completion with result persistence.
///
/// ## Lifecycle
/// ```
/// loadSong() -> startListenPhase() -> startPractice() -> [pitch monitoring] -> completePractice()
/// ```
///
/// ## Architecture
/// Lives in the main app target because it requires `ModelContext` (for
/// `SessionRecorder`) and direct access to `Song` (@Model).
/// Pure scoring computation delegates to `SVLearning` types.
@Observable
@MainActor
final class PracticeSessionViewModel {
    // MARK: - Public Properties

    /// Current phase of the practice session.
    private(set) var phase: PracticePhase = .loading

    /// The song being practiced.
    private(set) var song: Song?

    /// Sargam notes decoded from the song, used for scoring.
    private(set) var sargamNotes: [SargamNote] = []

    /// Accumulated note scores from the practice phase.
    var noteScores: [NoteScore] = []

    /// Latest pitch detection result (for live UI feedback).
    var currentPitch: PitchResult?

    /// Index of the current note being practiced (0-based).
    var currentPracticeNoteIndex: Int = 0

    /// Overall session accuracy (0.0-1.0), computed at completion.
    private(set) var sessionAccuracy: Double = 0.0

    /// Star rating (1-5), computed at completion.
    private(set) var starRating: Int = 0

    /// XP earned, computed at completion.
    private(set) var xpEarned: Int = 0

    /// Longest streak of non-miss notes.
    private(set) var longestStreak: Int = 0

    /// AUD-017: Running accuracy sum for O(1) average computation.
    /// Avoids `PracticeScoring.averageAccuracy` O(n) reduce on every HUD render.
    var liveAccuracySum: Double = 0

    /// AUD-017: Current streak of consecutive non-miss notes.
    /// Maintained incrementally so `PracticeHUD` never calls `PracticeScoring.longestStreak`.
    var liveStreak: Int = 0

    /// Wait Mode engine for note-by-note practice.
    private(set) var waitModeEngine = WaitModeEngine()

    /// Whether Wait Mode is active for this session.
    var isWaitModeEnabled: Bool = false {
        didSet {
            waitModeEngine.configuration.isEnabled = isWaitModeEnabled
            AnalyticsManager.shared.track(
                .waitModeToggled,
                properties: ["enabled": isWaitModeEnabled]
            )
        }
    }

    /// Whether the tanpura drone is enabled.
    var isTanpuraEnabled: Bool = false {
        didSet {
            if isTanpuraEnabled {
                do {
                    try tanpuraEngine.start()
                } catch {
                    Self.logger.error(
                        "Tanpura start failed: \(error.localizedDescription, privacy: .public)"
                    )
                    isTanpuraEnabled = false
                }
            } else {
                tanpuraEngine.stop()
            }
        }
    }

    /// Whether the metronome is enabled.
    var isMetronomeEnabled: Bool = false {
        didSet {
            if isMetronomeEnabled {
                metronomeEngine.start()
            } else {
                metronomeEngine.stop()
            }
        }
    }

    /// Current metronome BPM.
    var metronomeBPM: Double = 60.0 {
        didSet {
            metronomeEngine.updateBPM(metronomeBPM)
        }
    }

    /// Elapsed practice time in seconds.
    var elapsedPracticeTime: TimeInterval = 0

    /// Whether the listen phase is currently playing.
    var isListenPlaying: Bool {
        playbackEngine.playbackState == .playing
    }

    /// The playback engine (exposed for listen phase UI binding).
    let playbackEngine = SongPlaybackEngine()

    // MARK: - Private Properties

    /// Audio processor for microphone pitch detection.
    let audioProcessor = PracticeAudioProcessor()

    /// Metronome engine for beat-keeping during practice.
    let metronomeEngine: MetronomeEngine

    /// Tanpura engine for Sa-Pa drone reference during practice.
    let tanpuraEngine: TanpuraEngine

    /// Raga scoring context, built from the song's ragaName. nil for non-raga songs.
    var ragaScoringContext: RagaScoringContext?

    /// Raga-aware note mapper for enriching pitch results. nil for non-raga songs.
    var ragaMapper: RagaAwareMapper?

    /// Recorder for persisting practice results to SwiftData.
    private var recorder: SessionRecorder?

    /// Gamification service for XP awards, rang progression, and achievements.
    var gamificationService: GamificationService?

    /// Task that consumes the pitch stream and scores notes.
    var pitchMonitoringTask: Task<Void, Never>?

    /// Task that updates elapsed practice time.
    var practiceTimerTask: Task<Void, Never>?

    /// Wall-clock time when practice started, used for elapsed time.
    var practiceStartTime: Date?

    /// Whether first-pitch achievement has been fired this session.
    var hasTrackedFirstPitch: Bool = false

    static let logger = Logger.survibe(category: "PracticeSessionVM")

    // MARK: - Initialization

    /// Create a practice session view model.
    ///
    /// - Parameters:
    ///   - modelContext: SwiftData model context for persisting results.
    ///   - gamificationService: Optional gamification service for XP/achievement wiring.
    init(modelContext: ModelContext, gamificationService: GamificationService? = nil) {
        self.metronomeEngine = MetronomeEngine(bpm: 60.0, volume: 0.5)
        self.tanpuraEngine = TanpuraEngine(saFrequency: 261.63, volume: 0.3)
        self.recorder = SessionRecorder(modelContext: modelContext)
        self.gamificationService = gamificationService
    }

    // MARK: - Session Lifecycle

    /// Load a song and prepare for practice.
    ///
    /// Decodes sargam notation, loads the song into the playback engine,
    /// loads the SoundFont, and transitions to the listen-first phase.
    ///
    /// - Parameter song: The song to practice.
    func loadSong(_ song: Song) async {
        MultiChannelLog.shared.log(.info, ">>> PracticeSessionViewModel.loadSong(\(song.title))")
        self.song = song
        phase = .loading

        // Decode sargam notes for scoring
        sargamNotes = song.decodedSargamNotes ?? []
        MultiChannelLog.shared.log(
            .info, "... PracticeSessionViewModel.loadSong: sargam decoded count=\(sargamNotes.count)"
        )
        if sargamNotes.isEmpty {
            Self.logger.warning(
                "Song '\(song.title, privacy: .public)' has no sargam notation — scoring will be limited"
            )
        }

        // Set metronome to song tempo
        metronomeBPM = Double(song.tempo)
        metronomeEngine.updateBPM(metronomeBPM)
        MultiChannelLog.shared.log(
            .info, "... PracticeSessionViewModel.loadSong: metronome BPM set to \(song.tempo)"
        )

        // Ensure the audio engine is running. Lazy-constructs
        // AudioEngineManager.shared.multiChannel which preloads
        // Acoustic Grand into samplers[0] for touch playback.
        // Song playback (this VM's playbackEngine) routes through
        // the same multiChannel — see SongPlaybackEngine migration.
        MultiChannelLog.shared.log(
            .info, "... PracticeSessionViewModel.loadSong: about to startForPlayback()"
        )
        do {
            try AudioEngineManager.shared.startForPlayback()
            MultiChannelLog.shared.log(
                .info, "... PracticeSessionViewModel.loadSong: startForPlayback() returned"
            )
        } catch {
            MultiChannelLog.shared.log(
                .info,
                "... PracticeSessionViewModel.loadSong: startForPlayback() THREW: \(error.localizedDescription)"
            )
            Self.logger.error("Audio engine start failed: \(error.localizedDescription, privacy: .public)")
        }

        // Load song into playback engine
        MultiChannelLog.shared.log(
            .info, "... PracticeSessionViewModel.loadSong: about to await playbackEngine.load"
        )
        await playbackEngine.load(song: song)
        MultiChannelLog.shared.log(
            .info, "... PracticeSessionViewModel.loadSong: playbackEngine.load returned"
        )

        // Reset scoring state
        noteScores = []
        currentPracticeNoteIndex = 0
        currentPitch = nil
        sessionAccuracy = 0
        starRating = 0
        xpEarned = 0
        longestStreak = 0
        liveAccuracySum = 0
        liveStreak = 0
        elapsedPracticeTime = 0

        // Configure raga-aware scoring if song has a raga
        configureRagaContext(ragaName: song.ragaName)

        phase = .listenFirst
        Self.logger.info("Song loaded for practice: \(song.title, privacy: .public)")
        MultiChannelLog.shared.log(.info, "<<< PracticeSessionViewModel.loadSong DONE")
    }

    /// Start the listen-first playback phase.
    ///
    /// Plays the song through the playback engine so the user can hear
    /// it before practicing. No-op if the song lacks MIDI data or the
    /// phase is not `.listenFirst`.
    func startListenPhase() {
        MultiChannelLog.shared.log(
            .info,
            ">>> PracticeSessionViewModel.startListenPhase phase=\(phase) hasPlayableContent=\(playbackEngine.hasPlayableContent)"
        )
        guard phase == .listenFirst else { return }
        if playbackEngine.hasPlayableContent {
            MultiChannelLog.shared.log(.info, "... startListenPhase: calling play")
            playbackEngine.play()
        }
        MultiChannelLog.shared.log(.info, "<<< PracticeSessionViewModel.startListenPhase")
    }

    /// Pause the listen-first playback.
    func pauseListenPhase() {
        playbackEngine.pause()
    }

    /// Resume the listen-first playback.
    func resumeListenPhase() {
        playbackEngine.resume()
    }

    /// Skip the listen phase and go directly to practice.
    ///
    /// Stops any active playback and begins the practice-along phase.
    func skipListenPhase() {
        if playbackEngine.playbackState == .playing
            || playbackEngine.playbackState == .paused
        {
            playbackEngine.stop()
        }
        startPractice()
    }

    /// Begin the practice-along phase.
    ///
    /// Starts the audio processor for pitch detection, begins the elapsed
    /// time tracker, and launches the pitch monitoring loop that scores
    /// each note as the user plays.
    func startPractice() {
        guard phase == .listenFirst || phase == .loading else { return }

        // Stop any listen phase playback
        if playbackEngine.playbackState == .playing
            || playbackEngine.playbackState == .paused
        {
            playbackEngine.stop()
        }

        phase = .practiceAlong
        practiceStartTime = Date()
        currentPracticeNoteIndex = 0
        noteScores = []

        // Start audio processor for mic input
        do {
            try audioProcessor.start()
        } catch {
            Self.logger.error(
                "Audio processor failed to start: \(error.localizedDescription, privacy: .public)"
            )
            phase = .error(
                "Microphone not available. Check permissions in Settings."
            )
            return
        }

        // Start elapsed time tracker
        startPracticeTimer()

        // Start pitch monitoring
        startPitchMonitoring()

        // Initialize Wait Mode if enabled
        if isWaitModeEnabled {
            waitModeEngine.configuration.isEnabled = true
            waitModeEngine.reset()
            if !sargamNotes.isEmpty {
                waitModeEngine.waitForNote()
            }
        }

        AnalyticsManager.shared.track(
            .practiceSessionStarted,
            properties: [
                "song_title": song?.title ?? "",
                "song_difficulty": song?.difficulty ?? 0,
            ]
        )

        Self.logger.info("Practice started: \(self.song?.title ?? "unknown", privacy: .public)")
    }

    /// Complete the practice session and compute results.
    ///
    /// Stops audio processing, computes aggregate scores, persists results
    /// via `SessionRecorder`, and transitions to the completed phase.
    func completePractice() {
        guard phase == .practiceAlong else { return }

        stopMonitoring()
        scoreRemainingNotesAsMisses()
        computeSessionResults()
        persistResults()

        // Award XP via gamification service
        let songProficient = starRating >= 3
        gamificationService?.handlePracticeCompleted(
            xp: xpEarned,
            songId: song?.slugId ?? "",
            songProficient: songProficient
        )

        phase = .completed

        AnalyticsManager.shared.track(
            .practiceSessionCompleted,
            properties: [
                "song_title": song?.title ?? "",
                "accuracy": Int(sessionAccuracy * 100),
                "stars": starRating,
                "xp_earned": xpEarned,
                "notes_played": noteScores.count,
            ]
        )

        Self.logger.info(
            "Practice completed: accuracy=\(self.sessionAccuracy) stars=\(self.starRating) xp=\(self.xpEarned)"
        )
    }

    /// Restart the practice session from the beginning.
    ///
    /// Cleans up the current session (audio, timers), resets all scoring
    /// state, and re-enters the practice-along phase.
    func restartPractice() {
        // Clean up current session
        pitchMonitoringTask?.cancel()
        pitchMonitoringTask = nil
        practiceTimerTask?.cancel()
        practiceTimerTask = nil
        audioProcessor.stop()
        metronomeEngine.stop()
        tanpuraEngine.stop()

        // Reset state
        noteScores = []
        currentPracticeNoteIndex = 0
        currentPitch = nil
        sessionAccuracy = 0
        starRating = 0
        xpEarned = 0
        longestStreak = 0
        liveAccuracySum = 0
        liveStreak = 0
        elapsedPracticeTime = 0

        AnalyticsManager.shared.track(
            .practiceSessionRestarted,
            properties: ["song_title": song?.title ?? ""]
        )

        // Restart practice
        startPractice()
    }

    /// Clean up all resources when leaving the practice screen.
    ///
    /// Cancels all background tasks, stops audio processing and metronome,
    /// halts any active playback, and silences all sounding notes.
    func cleanup() {
        pitchMonitoringTask?.cancel()
        pitchMonitoringTask = nil
        practiceTimerTask?.cancel()
        practiceTimerTask = nil
        audioProcessor.stop()
        metronomeEngine.stop()
        tanpuraEngine.stop()
        if playbackEngine.playbackState == .playing
            || playbackEngine.playbackState == .paused
        {
            playbackEngine.stop()
        }
        AudioEngineManager.shared.multiChannel?.stopAllTouchNotes()
        waitModeEngine.reset()
    }

    /// Toggle Wait Mode on or off during a practice session.
    func toggleWaitMode() {
        isWaitModeEnabled.toggle()
    }

    // MARK: - Private Methods

    /// Cancel monitoring tasks and stop audio/metronome/tanpura.
    private func stopMonitoring() {
        pitchMonitoringTask?.cancel()
        pitchMonitoringTask = nil
        practiceTimerTask?.cancel()
        practiceTimerTask = nil
        audioProcessor.stop()
        metronomeEngine.stop()
        tanpuraEngine.stop()
    }

    /// Mark all remaining unscored notes as misses.
    private func scoreRemainingNotesAsMisses() {
        while currentPracticeNoteIndex < sargamNotes.count {
            let note = sargamNotes[currentPracticeNoteIndex]
            noteScores.append(
                NoteScoreCalculator.missedNote(expectedNote: note.note)
            )
            currentPracticeNoteIndex += 1
        }
    }

    /// Compute aggregate session results from note scores.
    private func computeSessionResults() {
        sessionAccuracy = PracticeScoring.averageAccuracy(scores: noteScores)
        starRating = PracticeScoring.starRating(accuracy: sessionAccuracy)
        let grades = noteScores.map(\.grade)
        longestStreak = PracticeScoring.longestStreak(grades: grades)
        xpEarned = PracticeScoring.xpEarned(
            accuracy: sessionAccuracy,
            difficulty: song?.difficulty ?? 1
        )
    }

    /// Persist session results to SwiftData via the recorder.
    private func persistResults() {
        let durationMinutes = max(1, Int(elapsedPracticeTime / 60.0))
        let songInfo = SessionSongInfo(
            songId: song?.slugId ?? "",
            songTitle: song?.title ?? "",
            ragaName: song?.ragaName ?? "",
            difficulty: song?.difficulty ?? 1
        )
        recorder?.recordSession(
            songInfo: songInfo,
            durationMinutes: durationMinutes,
            noteScores: noteScores
        )
    }
}
