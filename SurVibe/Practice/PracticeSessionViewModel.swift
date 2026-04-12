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
/// `PracticeSessionRecorder`) and direct access to `Song` (@Model).
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
    private(set) var noteScores: [NoteScore] = []

    /// Latest pitch detection result (for live UI feedback).
    private(set) var currentPitch: PitchResult?

    /// Index of the current note being practiced (0-based).
    private(set) var currentPracticeNoteIndex: Int = 0

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
    private(set) var liveAccuracySum: Double = 0

    /// AUD-017: Current streak of consecutive non-miss notes.
    /// Maintained incrementally so `PracticeHUD` never calls `PracticeScoring.longestStreak`.
    private(set) var liveStreak: Int = 0

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
    private(set) var elapsedPracticeTime: TimeInterval = 0

    /// Whether the listen phase is currently playing.
    var isListenPlaying: Bool {
        playbackEngine.playbackState == .playing
    }

    /// The playback engine (exposed for listen phase UI binding).
    let playbackEngine = SongPlaybackEngine()

    // MARK: - Private Properties

    /// Audio processor for microphone pitch detection.
    private let audioProcessor = PracticeAudioProcessor()

    /// Metronome engine for beat-keeping during practice.
    private let metronomeEngine: MetronomeEngine

    /// Raga scoring context, built from the song's ragaName. nil for non-raga songs.
    private var ragaScoringContext: RagaScoringContext?

    /// Raga-aware note mapper for enriching pitch results. nil for non-raga songs.
    private var ragaMapper: RagaAwareMapper?

    /// Recorder for persisting practice results to SwiftData.
    private var recorder: PracticeSessionRecorder?

    /// Gamification service for XP awards, rang progression, and achievements.
    private var gamificationService: GamificationService?

    /// Task that consumes the pitch stream and scores notes.
    private var pitchMonitoringTask: Task<Void, Never>?

    /// Task that updates elapsed practice time.
    private var practiceTimerTask: Task<Void, Never>?

    /// Wall-clock time when practice started, used for elapsed time.
    private var practiceStartTime: Date?

    /// Whether first-pitch achievement has been fired this session.
    private var hasTrackedFirstPitch: Bool = false

    private static let logger = Logger(
        subsystem: "com.survibe",
        category: "PracticeSessionVM"
    )

    // MARK: - Initialization

    /// Create a practice session view model.
    ///
    /// - Parameters:
    ///   - modelContext: SwiftData model context for persisting results.
    ///   - gamificationService: Optional gamification service for XP/achievement wiring.
    init(modelContext: ModelContext, gamificationService: GamificationService? = nil) {
        self.metronomeEngine = MetronomeEngine(bpm: 60.0, volume: 0.5)
        self.recorder = PracticeSessionRecorder(modelContext: modelContext)
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
        self.song = song
        phase = .loading

        // Decode sargam notes for scoring
        sargamNotes = song.decodedSargamNotes ?? []
        if sargamNotes.isEmpty {
            Self.logger.warning(
                "Song '\(song.title)' has no sargam notation — scoring will be limited"
            )
        }

        // Set metronome to song tempo
        metronomeBPM = Double(song.tempo)
        metronomeEngine.updateBPM(metronomeBPM)

        // Load the SoundFont for playback
        do {
            try await SoundFontManager.shared.loadBundledPiano()
        } catch {
            Self.logger.error("SoundFont load failed: \(error.localizedDescription)")
        }

        // Load song into playback engine
        await playbackEngine.load(song: song)

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
        Self.logger.info("Song loaded for practice: \(song.title)")
    }

    /// Start the listen-first playback phase.
    ///
    /// Plays the song through the playback engine so the user can hear
    /// it before practicing. No-op if the song lacks MIDI data or the
    /// phase is not `.listenFirst`.
    func startListenPhase() {
        guard phase == .listenFirst else { return }
        if playbackEngine.hasPlayableContent {
            playbackEngine.play()
        }
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
                "Audio processor failed to start: \(error.localizedDescription)"
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

        Self.logger.info("Practice started: \(self.song?.title ?? "unknown")")
    }

    /// Complete the practice session and compute results.
    ///
    /// Stops audio processing, computes aggregate scores, persists results
    /// via `PracticeSessionRecorder`, and transitions to the completed phase.
    func completePractice() {
        guard phase == .practiceAlong else { return }

        // Stop monitoring
        pitchMonitoringTask?.cancel()
        pitchMonitoringTask = nil
        practiceTimerTask?.cancel()
        practiceTimerTask = nil
        audioProcessor.stop()
        metronomeEngine.stop()

        // Score any remaining unscored notes as misses
        while currentPracticeNoteIndex < sargamNotes.count {
            let note = sargamNotes[currentPracticeNoteIndex]
            noteScores.append(
                NoteScoreCalculator.missedNote(expectedNote: note.note)
            )
            currentPracticeNoteIndex += 1
        }

        // Compute session results
        sessionAccuracy = PracticeScoring.averageAccuracy(scores: noteScores)
        starRating = PracticeScoring.starRating(accuracy: sessionAccuracy)
        let grades = noteScores.map(\.grade)
        longestStreak = PracticeScoring.longestStreak(grades: grades)
        xpEarned = PracticeScoring.xpEarned(
            accuracy: sessionAccuracy,
            difficulty: song?.difficulty ?? 1
        )

        // Calculate duration in minutes
        let durationMinutes = max(1, Int(elapsedPracticeTime / 60.0))

        // Persist results
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

        // Award XP via gamification service (creates XPEntry records + triggers rang/achievements)
        let songMastered = starRating >= 3
        gamificationService?.handlePracticeCompleted(
            xp: xpEarned,
            songId: song?.slugId ?? "",
            songMastered: songMastered
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
        if playbackEngine.playbackState == .playing
            || playbackEngine.playbackState == .paused
        {
            playbackEngine.stop()
        }
        SoundFontManager.shared.stopAllNotes()
        waitModeEngine.reset()
    }

    /// Toggle Wait Mode on or off during a practice session.
    func toggleWaitMode() {
        isWaitModeEnabled.toggle()
    }

    // MARK: - Private Methods

    /// Start the elapsed practice time tracker.
    ///
    /// Updates `elapsedPracticeTime` every second via `Task.sleep`.
    private func startPracticeTimer() {
        practiceTimerTask?.cancel()
        practiceTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let startTime = self.practiceStartTime else {
                    return
                }
                self.elapsedPracticeTime = Date().timeIntervalSince(startTime)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Start the pitch monitoring loop.
    ///
    /// Consumes pitch results from the audio processor's async stream,
    /// compares each detected note against the expected sargam note,
    /// and produces `NoteScore` values. Automatically completes the
    /// session when all notes have been played.
    private func startPitchMonitoring() {
        pitchMonitoringTask?.cancel()
        pitchMonitoringTask = Task { [weak self] in
            guard let self else { return }
            for await pitch in self.audioProcessor.pitchStream {
                guard !Task.isCancelled, self.phase == .practiceAlong else { break }
                guard self.currentPracticeNoteIndex < self.sargamNotes.count else {
                    self.completePractice()
                    break
                }

                // Enrich with raga context when mapper is available
                let enrichedPitch = self.enrichPitchWithRagaContext(pitch)
                self.currentPitch = enrichedPitch

                guard enrichedPitch.amplitude >= PracticeConstants.silenceThreshold,
                      enrichedPitch.confidence >= PracticeConstants.confidenceThreshold
                else { continue }

                // Track first valid pitch for "First Note" achievement
                if !self.hasTrackedFirstPitch {
                    self.hasTrackedFirstPitch = true
                    self.gamificationService?.handleFirstPitchDetected()
                }

                if self.processDetectedPitch(enrichedPitch) { break }
            }
        }
    }

    /// Enrich a pitch result with raga-aware mapping when available.
    ///
    /// When a `RagaAwareMapper` is configured, re-maps the detected frequency
    /// to get JI cents offset and in-raga status. Falls through to the
    /// original pitch result when no mapper is available.
    ///
    /// - Parameter pitch: The raw pitch result from the audio processor.
    /// - Returns: Enriched pitch result with `isInRaga` and `ragaCentsOffset`.
    private func enrichPitchWithRagaContext(_ pitch: PitchResult) -> PitchResult {
        guard let mapper = ragaMapper else { return pitch }
        do {
            // referencePitch is A4 (440 Hz), matching the audio processor's convention
            let mapping = try mapper.mapFrequency(pitch.frequency, referencePitch: 440.0)
            return PitchResult(
                frequency: pitch.frequency,
                amplitude: pitch.amplitude,
                noteName: mapping.noteName,
                octave: mapping.octave,
                centsOffset: pitch.centsOffset,
                confidence: pitch.confidence,
                isInRaga: mapping.isInRaga,
                ragaCentsOffset: mapping.ragaCentsOffset
            )
        } catch {
            return pitch
        }
    }

    /// Score a detected pitch against the current expected note. Returns `true` if session is complete.
    private func processDetectedPitch(_ pitch: PitchResult) -> Bool {
        let expected = sargamNotes[currentPracticeNoteIndex]
        let expectedName = expected.modifier.map { "\($0.capitalized) \(expected.note)" } ?? expected.note

        // Use JI cents deviation when raga context is available, otherwise 12ET
        let centsDeviation: Double
        if let ragaCents = pitch.ragaCentsOffset {
            centsDeviation = abs(ragaCents)
        } else {
            centsDeviation = abs(pitch.centsOffset)
        }

        let score = NoteScoreCalculator.score(
            expectedNote: expectedName, detectedNote: pitch.noteName,
            pitchDeviationCents: centsDeviation,
            timingDeviationSeconds: 0.05, durationDeviation: 0.1,
            ragaPitchDeviationCents: pitch.ragaCentsOffset.map { abs($0) },
            ragaContext: ragaScoringContext
        )
        noteScores.append(score)
        // AUD-017: Maintain live counters incrementally — O(1) per note.
        liveAccuracySum += score.accuracy
        liveStreak = score.grade == .miss ? 0 : liveStreak + 1
        if pitch.noteName == expectedName && pitch.octave == expected.octave {
            currentPracticeNoteIndex += 1
            if currentPracticeNoteIndex >= sargamNotes.count {
                completePractice()
                return true
            }
        }
        return false
    }

    /// Configure raga-aware scoring context from the song's raga name.
    ///
    /// When a valid raga name is provided, creates a `RagaScoringContext` for
    /// score penalties and a `RagaAwareMapper` for JI note snapping.
    /// When raga name is empty or unknown, clears both to fall back to 12ET.
    ///
    /// - Parameter ragaName: The raga name from the song, or empty string.
    private func configureRagaContext(ragaName: String) {
        guard !ragaName.isEmpty else {
            ragaScoringContext = nil
            ragaMapper = nil
            return
        }

        ragaScoringContext = RagaScoringContext.from(ragaName: ragaName)
        if let ragaContext = RagaTuningProvider.context(for: ragaName) {
            ragaMapper = RagaAwareMapper(ragaContext: ragaContext)
            Self.logger.info("Raga context configured: \(ragaName) (\(ragaContext.scaleDegrees.count) degrees)")
        } else {
            ragaMapper = nil
            Self.logger.info("Unknown raga '\(ragaName)' — using equal temperament")
        }
    }
}
