// swiftlint:disable file_length
// PlayAlongViewModel is intentionally large: @Observable requires all stored
// properties in the primary class declaration; private methods cannot be
// extracted to separate files without losing @Observable synthesis.
import Foundation
import SVAudio
import SVCore
import SVLearning
import SwiftData
import SwiftUI
import os.log

/// Main view model for the play-along experience.
///
/// Orchestrates song loading (dual-path: MIDI or notation), real-time playback
/// scheduling, pitch detection, scoring, and wait mode. All state is @Observable
/// for efficient SwiftUI binding.
///
/// ## Two Loading Paths
/// 1. **MIDI binary** — 2/19 seed songs provide raw MIDI data parsed via `MIDIParser`.
/// 2. **Notation arrays** — 17/19 seed songs store JSON-encoded `SargamNote`/`WesternNote`
///    arrays converted to `NoteEvent` via `NoteEvent.fromNotation(...)`.
///
/// ## Playback Scheduling
/// Uses `ContinuousClock`-based drift-corrected timing via the injected
/// `ClockProviding` dependency. A 30 Hz display-link task updates `currentTime`
/// for smooth UI scrolling.
///
/// ## Scoring
/// Each note attempt is scored via `NoteScoreCalculator` from SVLearning.
/// Session-level aggregates (stars, XP, streaks) use `PracticeScoring`.
///
/// ## Wait Mode
/// When enabled, `PlayAlongWaitController` pauses playback at each note
/// until the user plays the correct pitch.
@Observable
@MainActor
// swiftlint:disable:next type_body_length
final class PlayAlongViewModel {
    // MARK: - Published State

    /// Current playback state of the play-along session.
    private(set) var playbackState: PlaybackState = .idle

    /// Ordered note events for the loaded song.
    private(set) var noteEvents: [NoteEvent] = []

    /// Index of the note currently being played or evaluated.
    private(set) var currentNoteIndex: Int?

    /// Scoring state per note, keyed by NoteEvent.id.
    private(set) var noteStates: [UUID: FallingNotesLayoutEngine.NoteState] = [:]

    /// Accumulated individual note scores for the session.
    private(set) var noteScores: [NoteScore] = []

    /// Count of non-miss note scores. Maintained incrementally to avoid
    /// O(n) `.filter` scans in `SongPlayAlongView.body` on every render pass.
    private(set) var notesHit: Int = 0

    /// Running sum of accuracy values for incremental average computation.
    /// Avoids O(n) `reduce` in `PracticeScoring.averageAccuracy` on every note.
    private var accuracySum: Double = 0

    /// Current playback position in seconds from song start.
    private(set) var currentTime: TimeInterval = 0

    /// Total duration of the song in seconds.
    private(set) var duration: TimeInterval = 0

    /// Normalized playback progress (0.0 to 1.0) for the timeline scrubber.
    var playbackProgress: Double {
        guard duration > 0 else { return 0 }
        return min(1.0, max(0.0, currentTime / duration))
    }

    /// Total playback duration in seconds, exposed for the toolbar timeline.
    var playbackDuration: TimeInterval { duration }

    /// Seek to a normalized position (0.0 to 1.0) in the song.
    ///
    /// Adjusts `currentTime` and `playbackStartDate` so the playback
    /// clock resumes from the new position. Only effective when paused.
    ///
    /// - Parameter progress: Normalized position from 0.0 (start) to 1.0 (end).
    func seek(to progress: Double) {
        guard duration > 0 else { return }
        let targetTime = progress * duration
        currentTime = targetTime
    }

    /// Overall session accuracy (0.0-1.0), updated in real time.
    private(set) var accuracy: Double = 0

    /// Current streak of consecutive non-miss notes.
    private(set) var streak: Int = 0

    /// Longest streak achieved during this session.
    private(set) var longestStreak: Int = 0

    /// Star rating (1-5) computed at session completion.
    private(set) var starRating: Int = 0

    /// XP earned, computed at session completion.
    private(set) var xpEarned: Int = 0

    /// Human-readable error message when playbackState is .error.
    private(set) var errorMessage: String?

    /// Whether wait mode is enabled for this session.
    var isWaitModeEnabled: Bool = false

    /// Tempo scaling factor (1.0 = original tempo, 0.5 = half speed).
    var tempoScale: Double = 1.0 {
        didSet {
            if metronome.isPlaying, let song {
                metronome.setBPM(Double(song.tempo) * tempoScale)
            }
        }
    }

    /// Whether SoundFont playback is enabled.
    var isSoundEnabled: Bool = true

    /// Visual display mode (falling notes vs scrolling sheet).
    var viewMode: PlayAlongViewMode = .fallingNotes

    /// Notation label display mode (Sargam, Western, dual, etc.).
    var notationMode: NotationDisplayMode = .sargam

    /// Latency preset for mic pitch detection (controls FFT buffer size for chord detection).
    ///
    /// Persisted across sessions. Changing this value while detection is active
    /// restarts the pitch detection pipeline with the new buffer size.
    var latencyPreset: LatencyPreset = {
        let raw = UserDefaults.standard.string(forKey: "com.survibe.playAlong.latencyPreset") ?? ""
        return LatencyPreset(rawValue: raw) ?? .fast
    }()
    {
        didSet {
            UserDefaults.standard.set(latencyPreset.rawValue, forKey: "com.survibe.playAlong.latencyPreset")
            // Restart pitch detection with the new buffer size
            if audioProcessor.isActive {
                audioProcessor.stop()
                startPitchDetection()
            }
        }
    }

    /// Latest pitch detection result for live UI feedback (nil when no input detected).
    private(set) var currentPitch: PitchResult?

    /// MIDI notes currently held on the keyboard (empty when no keys pressed).
    ///
    /// Updated on note-on (insert) and note-off (remove) from the MIDI stream.
    /// Microphone detection sets this to a single-element set (one pitch at a time).
    /// The UI reads this to highlight all simultaneously-pressed keys.
    private(set) var detectedMidiNotes: Set<Int> = []

    /// Isolated observable carrying only MIDI key-highlight state.
    ///
    /// Separated from this ViewModel so that CADisplayLink ticks (60–120 Hz) that
    /// update `highlightState.midiHighlightNotes` only re-render `InteractivePianoView`
    /// — NOT the entire `SongPlayAlongView` hierarchy. `SongPlayAlongView.body`
    /// must NEVER read this property; pass it directly to `InteractivePianoView`.
    let highlightState = HighlightState()

    /// The effective set of MIDI notes to highlight on the keyboard.
    ///
    /// Used only by `SongPlayAlongView` for the fallback (mic / on-screen touch /
    /// expected-note highlight). The MIDI keyboard highlight path now goes through
    /// `highlightState.midiHighlightNotes` so it does NOT cause `SongPlayAlongView`
    /// to re-render.
    var effectiveMidiNotes: Set<Int> {
        // Microphone or on-screen touch path
        if !detectedMidiNotes.isEmpty {
            return detectedMidiNotes
        }
        // Fallback: highlight the current expected note during playback
        if let index = currentNoteIndex, index < noteEvents.count {
            return [Int(noteEvents[index].midiNote)]
        }
        return []
    }

    /// Recomputes `highlightState.detectedSwarInfo` from a set of MIDI notes.
    ///
    /// Called at every `detectedMidiNotes` mutation site so `ScrollingSheetView`
    /// observes `HighlightState` directly instead of reading from this ViewModel,
    /// keeping `SongPlayAlongView.body` out of the note-on/off render path.
    private func updateDetectedSwarInfo(from midiNotes: Set<Int>) {
        guard let midiNote = midiNotes.min() else {
            highlightState.detectedSwarInfo = nil
            return
        }
        let fullName = swarNameFromMIDI(UInt8(midiNote))
        let baseName = fullName.components(separatedBy: " ").last ?? fullName
        let octave = (midiNote / 12) - 1
        highlightState.detectedSwarInfo = (name: baseName, octave: octave)
    }

    /// Whether a USB/Bluetooth MIDI keyboard is currently connected.
    ///
    /// When `true`, note input comes from the MIDI keyboard rather than the
    /// microphone. The toolbar shows a green "MIDI Connected" indicator.
    private(set) var isMIDIConnected: Bool = false

    /// Human-readable name of the connected MIDI device, if any.
    private(set) var midiDeviceName: String?

    // MARK: - Guided Free-Play State

    /// State of the guided free-play mode (active when not in timed playback).
    enum GuidedPlayState: Equatable {
        /// Waiting for user to play the expected note.
        case waitingForNote
        /// User just played the correct note — show green flash.
        case correct
        /// User played the wrong note — show red flash.
        case wrong
        /// User has been stuck on a note for too long — show hint.
        case stuck
    }

    /// Current guided play feedback state (only meaningful when playbackState is .idle/.paused).
    private(set) var guidedPlayState: GuidedPlayState = .waitingForNote

    /// The MIDI note the user is expected to play next in guided free-play mode.
    private(set) var expectedMidiNote: Int?

    /// Whether the patience timer has expired and user needs a hint.
    private(set) var isStuck: Bool = false

    // MARK: - Dependencies (injected for testability)

    /// Audio processor for real-time pitch detection from the microphone.
    private let audioProcessor = PracticeAudioProcessor()

    /// MIDI input provider for USB/Bluetooth keyboard detection.
    private let midiInput: any MIDIInputProviding

    /// Model context for persisting session results. Set by SongPlayAlongView on appear.
    var modelContext: ModelContext?

    /// SoundFont player for MIDI note playback.
    private let soundFont: any SoundFontPlaying

    /// Audio engine for mic/playback setup.
    private let audioEngine: any AudioEngineProviding

    /// Metronome player (stopped during play-along to avoid BPM conflict).
    private let metronome: any MetronomePlaying

    /// Drift-corrected clock for scheduling.
    private let clock: any ClockProviding

    // MARK: - Internal State

    /// The loaded Song model.
    private var song: Song?

    /// Ring buffer for accumulating audio samples for FFT chord detection.
    ///
    /// Sized to `latencyPreset.realSamples * 2` on each detection start.
    /// Written by the mic tap callback; read by the DSP loop in `PracticeAudioProcessor`.
    private var ringBuffer: AudioRingBuffer?

    /// Task running the note-by-note playback scheduler.
    private var playbackTask: Task<Void, Never>?

    /// Task reading pitch results from the microphone processor.
    private var pitchDetectionTask: Task<Void, Never>?
    private var chordDetectionTask: Task<Void, Never>?

    /// Task observing MIDI connection state changes (connect/disconnect).
    private var midiConnectionTask: Task<Void, Never>?

    /// Task running the 30 Hz display link for position updates.
    private var displayLinkTask: Task<Void, Never>?

    /// ContinuousClock instant when playback started (or resumed).
    private var playbackStartTime: ContinuousClock.Instant?

    /// Wall-clock Date adjusted to represent "when time=0 was", used by
    /// `FallingNotesView` to self-drive animation via `TimelineView` date.
    /// Set on play/resume, cleared on pause/stop. Accounts for pause offset.
    private(set) var playbackStartDate: Date?

    /// Elapsed time accumulated before the most recent pause.
    private var pauseElapsed: TimeInterval = 0

    /// Wait mode controller, created when wait mode is enabled.
    private var waitController: PlayAlongWaitController?

    /// Task running the patience countdown in guided free-play mode.
    private var patienceTimerTask: Task<Void, Never>?

    /// The last MIDI note that was scored in guided free-play mode.
    /// Used for onset debouncing: only score when the note changes, not on every frame.
    private var lastGuidedMidiNote: Int?

    /// Timestamp of the most recent pitch result that passed both amplitude and confidence
    /// thresholds in the melody detection loop. Used by the chord detection task to avoid
    /// double-scoring a note that the faster autocorrelation path already handled.
    private var lastMelodyDetectionDate: Date = .distantPast

    /// Patience timeout before marking user as "stuck" (from WaitModeSettingsStore).
    private var patienceSeconds: Double {
        let value = UserDefaults.standard.double(forKey: "com.survibe.waitMode.patience")
        return value > 0 ? value : 10.0
    }

    /// Raga scoring context, built from the song's ragaName. nil for non-raga songs.
    private var ragaScoringContext: RagaScoringContext?

    /// Raga-aware note mapper for enriching pitch results. nil for non-raga songs.
    private var ragaMapper: RagaAwareMapper?

    /// CADisplayLink-driven highlight coordinator for MIDI keyboard input.
    ///
    /// Written lock-free on CoreMIDI's high-priority thread; read by SwiftUI
    /// via `effectiveMidiNotes` at display-link cadence. This decouples key
    /// highlighting from the main-actor scheduling delay, eliminating missed
    /// highlights at 120–140 BPM.
    private let highlightCoordinator = MIDINoteHighlightCoordinator()

    /// Off-main-actor scoring engine.
    ///
    /// Runs note matching arithmetic away from `@MainActor` so MIDI scoring never
    /// competes with SwiftUI's render pass. Only the resulting `ScoringDiff` hops
    /// back to update `@Observable` state.
    private let noteMatchingActor = NoteMatchingActor()

    private static let logger = Logger.survibe(category: "PlayAlong")

    // MARK: - Initialization

    /// Create a play-along view model with injectable dependencies.
    ///
    /// All parameters default to production singletons when `nil` is passed.
    /// Tests inject mocks for deterministic behavior without audio hardware.
    ///
    /// - Parameters:
    ///   - soundFont: SoundFont player for note playback. Defaults to `SoundFontManager.shared`.
    ///   - audioEngine: Audio engine for session setup. Defaults to `AudioEngineManager.shared`.
    ///   - metronome: Metronome player (stopped during play-along). Defaults to `MetronomePlayer.shared`.
    ///   - clock: Clock for drift-corrected scheduling. Defaults to `RealClock()`.
    ///   - midiInput: MIDI input provider for USB keyboard detection. Defaults to `MIDIInputManager.shared`.
    init(
        soundFont: (any SoundFontPlaying)? = nil,
        audioEngine: (any AudioEngineProviding)? = nil,
        metronome: (any MetronomePlaying)? = nil,
        clock: (any ClockProviding)? = nil,
        midiInput: (any MIDIInputProviding)? = nil
    ) {
        self.soundFont = soundFont ?? SoundFontManager.shared
        self.audioEngine = audioEngine ?? AudioEngineManager.shared
        self.metronome = metronome ?? MetronomePlayer.shared
        self.clock = clock ?? RealClock()
        self.midiInput = midiInput ?? MIDIInputManager.shared
    }

    // MARK: - Public Methods

    /// Load a song and prepare note events for play-along.
    ///
    /// Implements a dual-path loading strategy:
    /// 1. **MIDI path** — If the song has binary MIDI data, parses it via
    ///    `MIDIParser` and converts to `NoteEvent` via `NoteEvent.fromMIDI(events:)`.
    /// 2. **Notation path** — If the song has Sargam + Western notation arrays,
    ///    converts them to `NoteEvent` via `NoteEvent.fromNotation(...)`.
    ///
    /// Sets `playbackState` to `.error` if neither path produces events.
    ///
    /// - Parameter song: The Song model to load.
    func loadSong(_ song: Song) async {
        playbackState = .loading
        self.song = song

        // Path 1: MIDI binary data (2/19 songs)
        if let midiData = song.midiData, !midiData.isEmpty,
            case .success(let midiEvents) = MIDIParser.parse(data: midiData)
        {
            noteEvents = NoteEvent.fromMIDI(events: midiEvents)
        }
        // Path 2: Notation arrays (17/19 songs)
        else if let sargam = song.decodedSargamNotes,
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
            return
        }

        // Calculate duration from the last note event
        if let last = noteEvents.last {
            duration = last.timestamp + last.duration
        }

        // Initialize all note states as upcoming
        for event in noteEvents {
            noteStates[event.id] = .upcoming
        }

        // Configure raga-aware scoring if the song has a raga
        configureRagaContext(ragaName: song.ragaName)

        playbackState = .idle
        Self.logger.info(
            "Song loaded: \(self.noteEvents.count) events, duration=\(String(format: "%.1f", self.duration))s"
        )

        // Initialize guided free-play: start at note 0 and compute the expected MIDI note.
        currentNoteIndex = noteEvents.isEmpty ? nil : 0
        updateExpectedMidiNote()
        guidedPlayState = .waitingForNote
        isStuck = false

        // Request microphone permission in context before starting the audio engine.
        // Must happen BEFORE startPitchDetection() so the audio session is configured
        // for .playAndRecord with a valid input channel count when installMicTap is called.
        let micGranted = await PermissionManager.shared.requestMicrophoneAccess()
        if !micGranted {
            Self.logger.warning("Microphone permission denied — pitch detection unavailable")
        }

        // Start MIDI detection — checks for connected USB keyboards immediately.
        // Runs in parallel with mic detection; both pipelines are active at the same time.
        startMIDIDetection()

        // Start pitch detection first — this starts the engine in .playAndRecord mode.
        // SoundFont is loaded AFTER so startForPlayback() does not downgrade the session
        // to .playbackOnly and trigger an engine restart that would drop the mic tap.
        startPitchDetection()

        // Load the SoundFont for playback after the engine is already running in
        // .playAndRecord mode. loadBundledPiano() calls startForPlayback() internally,
        // but AudioEngineManager treats playAndRecord as a superset and skips the restart.
        do {
            try await SoundFontManager.shared.loadBundledPiano()
        } catch {
            Self.logger.error(
                "SoundFont load failed: \(error.localizedDescription)"
            )
        }

        // Start patience timer so the user gets a hint if they don't play.
        startPatienceTimer()
    }

    /// Start the play-along session from the beginning.
    ///
    /// Starts the audio engine in playAndRecord mode (to avoid a mode-transition
    /// dropout if the mic is activated later), resets all scoring state, and
    /// begins note playback scheduling.
    ///
    /// Guards: only starts from `.idle` or `.stopped` with non-empty events.
    func startSession() async {
        guard playbackState == .idle || playbackState == .stopped else { return }
        guard !noteEvents.isEmpty else { return }

        // Start engine in playAndRecord mode from the start
        do {
            try audioEngine.start()
        } catch {
            Self.logger.error(
                "Engine start failed: \(error.localizedDescription)"
            )
            playbackState = .error("Audio engine failed to start")
            return
        }

        // Start metronome at scaled BPM (provides rhythm reference during play-along)
        let scaledBPM = Double(song?.tempo ?? 120) * tempoScale
        metronome.setBPM(scaledBPM)
        metronome.start()

        resetScoringState()

        playbackStartTime = clock.now
        // Date reference for FallingNotesView self-timing (no pauseElapsed offset on fresh start)
        playbackStartDate = Date()
        playbackState = .playing

        // Start 30 Hz display link for position updates
        startDisplayLink()

        // Start note playback scheduling
        startPlayback()

        // Pitch detection was started at loadSong — it runs continuously.
        // Re-start it here to handle the case where it was stopped (e.g. after cleanup).
        startPitchDetection()

        // Set up wait controller if wait mode is enabled
        if isWaitModeEnabled {
            waitController = PlayAlongWaitController(noteEvents: noteEvents)
        } else {
            waitController = nil
        }

        AnalyticsManager.shared.track(
            .songPlaybackStarted,
            properties: [
                "song_title": song?.title ?? "",
                "tempo_scale": tempoScale,
                "view_mode": viewMode.rawValue,
                "notation_mode": notationMode.rawValue,
                "wait_mode": isWaitModeEnabled,
            ]
        )

        Self.logger.info("Play-along session started")
    }

    /// Pause the current play-along session.
    ///
    /// Records elapsed time for seamless resume, cancels active playback tasks,
    /// and stops all sounding notes.
    func pauseSession() {
        guard playbackState == .playing else { return }

        if let startTime = playbackStartTime {
            let elapsed = clock.now - startTime
            pauseElapsed = elapsedSeconds(from: elapsed)
        }

        playbackState = .paused
        playbackStartDate = nil  // freeze FallingNotesView animation

        cancelPlaybackTasks()
        soundFont.stopAllNotes()
        metronome.stop()
        // Keep pitch detection running during pause so keyboard highlight stays active.
        // The detection loop checks playbackState == .playing before scoring notes.
        // Re-start pitch detection which was cancelled by cancelPlaybackTasks()
        startPitchDetection()
        // Resume guided free-play patience timer during pause
        updateExpectedMidiNote()
        guidedPlayState = .waitingForNote
        isStuck = false
        startPatienceTimer()

        AnalyticsManager.shared.track(
            .songPlaybackPaused,
            properties: ["song_title": song?.title ?? ""]
        )

        Self.logger.info(
            "Session paused at \(String(format: "%.1f", self.pauseElapsed))s"
        )
    }

    /// Resume the play-along session from the paused position.
    ///
    /// Adjusts the clock reference to account for time spent paused,
    /// then restarts playback from where it left off.
    func resumeSession() {
        guard playbackState == .paused else { return }

        // Adjust start time so elapsed computation continues from pause point
        playbackStartTime = clock.now.advanced(
            by: .seconds(-pauseElapsed)
        )
        // Date reference for FallingNotesView: wind back by pauseElapsed so
        // the view's computed currentTime continues from where it paused.
        playbackStartDate = Date(timeIntervalSinceNow: -pauseElapsed)
        playbackState = .playing

        startDisplayLink()
        startPlaybackFromCurrentPosition()
        metronome.start()
        // Pitch detection keeps running continuously — no need to restart on resume.

        Self.logger.info(
            "Session resumed from \(String(format: "%.1f", self.pauseElapsed))s"
        )
    }

    /// Handle a note detected from pitch detection (microphone input).
    ///
    /// Scores the detected note against the current expected note using
    /// `NoteScoreCalculator`. Uses the full swar name (e.g., "Komal Re")
    /// for comparison, not just the base note.
    ///
    /// - Parameter midiNote: MIDI note number of the detected pitch.
    func handleNoteDetected(midiNote: Int) {
        guard playbackState == .playing else { return }
        Task { await processNoteInput(midiNote: midiNote) }
    }

    /// Handle a keyboard touch (virtual piano input).
    ///
    /// Handle a note-on event from the on-screen piano keyboard.
    ///
    /// Inserts the note into `detectedMidiNotes` so the sheet view highlights
    /// the matching sargam block, then routes to scoring if playback is active
    /// or to guided mode when idle/paused.
    ///
    /// - Parameter midiNote: MIDI note number of the pressed key.
    func handleKeyboardNoteOn(midiNote: Int) {
        detectedMidiNotes.insert(midiNote)
        updateDetectedSwarInfo(from: detectedMidiNotes)
        if playbackState == .playing {
            Task { await processNoteInput(midiNote: midiNote) }
        } else if playbackState == .idle || playbackState == .paused {
            handleGuidedNoteDetected(midiNote: midiNote)
        }
    }

    /// Handle a note-off event from the on-screen piano keyboard.
    ///
    /// Removes the note from `detectedMidiNotes` so the sheet view un-highlights
    /// the sargam block when the finger is lifted.
    ///
    /// - Parameter midiNote: MIDI note number of the released key.
    func handleKeyboardNoteOff(midiNote: Int) {
        detectedMidiNotes.remove(midiNote)
        updateDetectedSwarInfo(from: detectedMidiNotes)
    }

    /// Handle an on-screen keyboard touch (legacy entry point used by tests).
    ///
    /// Awaitable keyboard touch handler for test call sites.
    ///
    /// Unlike `handleKeyboardNoteOn` (which fires scoring in a detached Task),
    /// this method awaits `processNoteInput` so callers can observe state
    /// changes immediately after the call returns.
    ///
    /// - Parameter midiNote: MIDI note number of the touched key.
    func handleKeyboardTouch(midiNote: Int) async {
        detectedMidiNotes.insert(midiNote)
        updateDetectedSwarInfo(from: detectedMidiNotes)
        if playbackState == .playing {
            await processNoteInput(midiNote: midiNote)
        } else if playbackState == .idle || playbackState == .paused {
            handleGuidedNoteDetected(midiNote: midiNote)
        }
    }

    /// Handle an on-screen keyboard touch in guided free-play mode.
    ///
    /// Routes the touch to guided scoring when playback is idle or paused.
    ///
    /// - Parameter midiNote: MIDI note number of the touched key.
    func handleKeyboardTouchGuided(midiNote: Int) {
        guard playbackState == .idle || playbackState == .paused else { return }
        handleGuidedNoteDetected(midiNote: midiNote)
    }

    /// Called when the user toggles wait mode. Updates state and fires analytics.
    func toggleWaitMode() {
        isWaitModeEnabled.toggle()
        AnalyticsManager.shared.track(
            .waitModeToggled,
            properties: [
                "enabled": isWaitModeEnabled,
                "song_title": song?.title ?? "",
            ]
        )
    }

    /// Stop the session early and compute results from notes scored so far.
    ///
    /// Called when the user taps the Stop button during an active session.
    /// Calculates final metrics from whatever notes have been scored,
    /// then transitions to `.stopped` to trigger the results overlay.
    func stopAndComplete() {
        guard playbackState == .playing || playbackState == .paused else { return }
        completeSession()
    }

    /// Clean up all resources and cancel active tasks.
    ///
    /// Call from the view's `onDisappear` to ensure no orphaned tasks
    /// or audio resources remain.
    func cleanup() {
        cancelPlaybackTasks()
        soundFont.stopAllNotes()
        // Reset SoundFont loaded state BEFORE stopping the engine so the sampler
        // will be properly re-loaded into the new engine graph on the next loadSong().
        SoundFontManager.shared.resetLoadedState()
        audioEngine.stop()
        metronome.stop()
        waitController?.reset()
        waitController = nil
        audioProcessor.ringBuffer = nil
        ringBuffer = nil
        audioProcessor.stop()
        pitchDetectionTask?.cancel()
        pitchDetectionTask = nil
        chordDetectionTask?.cancel()
        chordDetectionTask = nil
        midiInput.onNoteEvent = nil
        midiInput.onControlChangeEvent = nil
        midiInput.stop()
        highlightCoordinator.onActiveNotesChanged = nil
        highlightCoordinator.stop()
        highlightState.midiHighlightNotes = []
        midiConnectionTask?.cancel()
        midiConnectionTask = nil
        isMIDIConnected = false
        midiDeviceName = nil
        patienceTimerTask?.cancel()
        patienceTimerTask = nil
        playbackState = .idle
        // Flush diagnostic log to file so it's available when the user
        // closes the song and reconnects to Mac via USB.
        MIDIEventDiagnostics.shared.printSummary()
        Self.logger.info("Play-along cleanup complete")
    }

    /// Skip the current expected note and advance to the next one.
    ///
    /// Called when the user taps the hint skip button after getting stuck.
    func skipGuidedNote() {
        guard let index = currentNoteIndex, index < noteEvents.count else { return }
        noteStates[noteEvents[index].id] = .missed
        appendScore(NoteScoreCalculator.missedNote(expectedNote: noteEvents[index].swarName))
        updateStreakForMiss()
        let nextIndex = index + 1
        if nextIndex < noteEvents.count {
            currentNoteIndex = nextIndex
            updateExpectedMidiNote()
            guidedPlayState = .waitingForNote
            isStuck = false
            startPatienceTimer()
        } else {
            currentNoteIndex = nil
            expectedMidiNote = nil
        }
        accuracy = noteScores.isEmpty ? 0 : accuracySum / Double(noteScores.count)
    }

    /// Reset all scoring, streak, and guided-play state for a fresh session.
    private func resetScoringState() {
        currentNoteIndex = nil
        currentTime = 0
        pauseElapsed = 0
        noteScores.removeAll()
        notesHit = 0
        accuracySum = 0
        accuracy = 0
        streak = 0
        longestStreak = 0
        starRating = 0
        xpEarned = 0
        errorMessage = nil
        expectedMidiNote = nil
        guidedPlayState = .waitingForNote
        isStuck = false
        patienceTimerTask?.cancel()
        patienceTimerTask = nil
        for event in noteEvents {
            noteStates[event.id] = .upcoming
        }
    }

    // MARK: - Private Methods — Pitch Detection

    /// Start live MIDI keyboard detection.
    ///
    /// Starts `MIDIInputManager`, updates `isMIDIConnected` to reflect the
    /// current connection state, and launches a task that reads note-on events
    /// from the MIDI stream. MIDI note events bypass the microphone pipeline
    /// and are routed directly to `handleGuidedNoteDetected` / `handleNoteDetected`.
    ///
    /// When a MIDI keyboard is connected, it takes priority over microphone
    /// detection for note matching. Both pipelines run concurrently —
    /// the mic still updates `currentPitch` for visual feedback.
    private func startMIDIDetection() {
        midiInput.onNoteEvent = nil  // clear any previous callback before re-registering
        midiInput.onControlChangeEvent = nil
        midiConnectionTask?.cancel()
        midiConnectionTask = nil
        highlightCoordinator.start()
        // Relay coordinator highlight changes into the isolated HighlightState
        // observable. Only InteractivePianoView observes HighlightState, so this
        // write never triggers SongPlayAlongView.body to re-evaluate.
        let hs = highlightState
        highlightCoordinator.onActiveNotesChanged = { notes in
            hs.midiHighlightNotes = notes
        }
        midiInput.start()

        // Sync connection state after start
        isMIDIConnected = midiInput.isConnected
        midiDeviceName = midiInput.connectedDeviceName

        if isMIDIConnected {
            Self.logger.info(
                "MIDI keyboard detected: \(self.midiDeviceName ?? "unknown")"
            )
        }

        installMIDINoteCallback()
        startMIDIConnectionMonitoring()
    }

    /// Install the two-phase MIDI note-on/note-off callback on the MIDI input.
    ///
    /// Phase 1 runs on the CoreMIDI thread (lock-free highlight via coordinator).
    /// Phase 2 dispatches scoring to `@MainActor` via a high-priority Task.
    private func installMIDINoteCallback() {
        #if DEBUG
            MIDIEventDiagnostics.shared.reset()
            MIDIEventDiagnostics.shared.isEnabled = true
        #endif

        let coordinator = highlightCoordinator

        // CC callback: sustain pedal (CC64) and other controllers.
        // Runs on CoreMIDI's high-priority thread — no actor hop.
        midiInput.onControlChangeEvent = { event in
            guard event.isSustainPedal else { return }
            if event.isSustainDown {
                coordinator.sustainDown(channel: event.channel)
            } else {
                coordinator.sustainUp(channel: event.channel)
            }
        }

        midiInput.onNoteEvent = { [weak self] event in
            let midiNote = Int(event.noteNumber)

            // Phase 1: CoreMIDI thread — lock-free highlight + diagnostic recording.
            #if DEBUG
                MIDIEventDiagnostics.shared.recordCoremidi(event: event)
            #endif
            if event.isNoteOn {
                coordinator.noteOn(midiNote)
            } else {
                coordinator.noteOff(midiNote, channel: event.channel)
            }

            // Phase 2: MainActor — scoring only.
            Task(priority: .high) { @MainActor [weak self] in
                guard let self else { return }

                #if DEBUG
                    MIDIEventDiagnostics.shared.recordMainActor(event: event)
                #endif

                if event.isNoteOn {
                    if self.playbackState == .playing {
                        self.handleNoteDetected(midiNote: midiNote)
                    } else if self.playbackState == .idle || self.playbackState == .paused {
                        self.handleGuidedNoteDetected(midiNote: midiNote)
                    }
                }
            }
        }
    }

    /// Start monitoring MIDI keyboard connect/disconnect events.
    private func startMIDIConnectionMonitoring() {
        midiConnectionTask = Task { [weak self] in
            guard let self else { return }
            for await connected in self.midiInput.connectionStateStream {
                guard !Task.isCancelled else { return }
                self.isMIDIConnected = connected
                self.midiDeviceName = connected ? self.midiInput.connectedDeviceName : nil
                Self.logger.info(
                    "MIDI connection changed: \(connected ? "connected" : "disconnected", privacy: .public)"
                )
            }
        }
    }

    /// Start real-time pitch detection from the microphone.
    ///
    /// Starts `PracticeAudioProcessor` and launches two concurrent detection tasks:
    /// 1. **Melody task** — reads `PitchResult` from the processor's async stream,
    ///    enriches with raga context, updates `currentPitch`, and routes to scoring.
    /// 2. **Chord task** — accumulates audio samples in an `AudioRingBuffer` sized
    ///    by `latencyPreset`, runs `ChromagramDSP.analyzeChord` every 50 ms, and
    ///    exposes results via `audioProcessor.ringBufferRef` for multi-note display.
    ///
    /// The ring buffer is fed by a secondary tap on `AudioEngineManager` that runs
    /// alongside the `PracticeAudioProcessor` tap (both coexist on different node taps).
    ///
    /// Detection starts at song load so users can play immediately without pressing Play.
    private func startPitchDetection() {
        // Cancel existing consumer tasks. Only restart the processor when it is not
        // yet running — reinstalling the mic tap unnecessarily causes a dropout.
        pitchDetectionTask?.cancel()
        pitchDetectionTask = nil

        // Allocate a fresh ring buffer sized to the current latency preset.
        // Capacity = realSamples * 2 so we always have a full window available.
        let preset = latencyPreset
        let newRingBuffer = AudioRingBuffer(capacity: preset.realSamples * 2)
        ringBuffer = newRingBuffer

        // Give PracticeAudioProcessor the ring buffer reference BEFORE start(),
        // so the tap closure captures it when it is installed during start().
        audioProcessor.ringBuffer = newRingBuffer

        if !audioProcessor.isActive {
            do {
                try audioProcessor.start()
                Self.logger.info("MicDiag: audioProcessor.start() succeeded")
            } catch {
                Self.logger.error(
                    "MicDiag: audioProcessor.start() FAILED: \(error.localizedDescription, privacy: .public)"
                )
                return
            }
        } else {
            Self.logger.info("MicDiag: audioProcessor already active — skipping start()")
        }

        let engineRunning = AudioEngineManager.shared.isRunning
        let hasTap = AudioEngineManager.shared.hasMicTap
        Self.logger.info(
            "MicDiag: engine.isRunning=\(engineRunning) hasMicTap=\(hasTap) isMIDIConnected=\(self.isMIDIConnected)"
        )
        Self.logger.info(
            "Pitch detection started: preset=\(preset.rawValue) realSamples=\(preset.realSamples)"
        )

        // --- Melody detection task ---
        // Reads PitchResult from PracticeAudioProcessor's autocorrelation stream.
        pitchDetectionTask = Task { [weak self] in
            await self?.runMelodyDetectionLoop()
        }

        chordDetectionTask?.cancel()
        chordDetectionTask = Task { [weak self] in
            await self?.runChordDetectionLoop(realSamples: preset.realSamples)
        }
    }

    /// Poll the ring buffer for chromagram chord analysis and route to scoring.
    ///
    /// Runs every 50 ms, gated on minimum RMS amplitude to reject speaker bleed.
    /// Falls back to scoring only when the melody autocorrelation path has not
    /// handled a note in the last 80 ms (avoids double-scoring).
    private func runChordDetectionLoop(realSamples: Int) async {
        let buf = ringBuffer
        let refPitch = 440.0
        let amplitudeGate: Float = 0.01
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            guard let buf,
                let samples = buf.read(count: realSamples)
            else { continue }
            let rms = Self.calculateRMS(samples)
            guard rms >= amplitudeGate else { continue }
            let result = ChromagramDSP.analyzeChord(
                samples: samples,
                sampleRate: 44100,
                referencePitch: refPitch
            )
            guard !result.detectedPitches.isEmpty else { continue }
            guard !isMIDIConnected else { continue }

            let midiNotes = Set(result.detectedPitches.map { $0.midiNote })
            detectedMidiNotes = midiNotes
            updateDetectedSwarInfo(from: midiNotes)

            let melodyAge = Date().timeIntervalSince(lastMelodyDetectionDate)
            guard melodyAge > 0.080 else { continue }
            guard let dominant = result.detectedPitches.max(by: { $0.confidence < $1.confidence }) else {
                continue
            }
            routeNoteToScoring(midiNote: dominant.midiNote)
        }
    }

    /// Route a detected MIDI note to timed scoring or guided free-play.
    private func routeNoteToScoring(midiNote: Int) {
        if playbackState == .playing {
            handleNoteDetected(midiNote: midiNote)
        } else if playbackState == .idle || playbackState == .paused {
            handleGuidedNoteDetected(midiNote: midiNote)
        }
    }

    /// Consume the autocorrelation pitch stream and update UI/scoring state.
    ///
    /// Extracted from `startPitchDetection()` to keep that function within the
    /// SwiftLint `function_body_length` limit. Runs for the lifetime of
    /// `pitchDetectionTask` and exits when the stream ends or the Task is cancelled.
    private func runMelodyDetectionLoop() async {
        var pitchResultCount = 0
        var belowThresholdCount = 0
        Self.logger.info("MicDiag: melody task started — isMIDIConnected=\(self.isMIDIConnected)")
        for await pitchResult in self.audioProcessor.pitchStream {
            guard !Task.isCancelled else {
                Self.logger.info(
                    "MicDiag: melody task cancelled (results=\(pitchResultCount) belowThresh=\(belowThresholdCount))"
                )
                return
            }

            let enriched = self.enrichPitchWithRagaContext(pitchResult)

            let ampStr = String(format: "%.4f", enriched.amplitude)
            let confStr = String(format: "%.3f", enriched.confidence)
            let freqStr = String(format: "%.1f", enriched.frequency)
            let silThresh = String(format: "%.4f", PracticeConstants.silenceThreshold)
            let confThresh = String(format: "%.3f", PracticeConstants.confidenceThreshold)
            let midiConn = self.isMIDIConnected
            Self.logger.info(
                // swiftlint:disable:next line_length
                "MicDiag: pitchStream result #\(pitchResultCount) freq=\(freqStr)Hz note=\(enriched.noteName, privacy: .public)\(enriched.octave) amp=\(ampStr)/\(silThresh) conf=\(confStr)/\(confThresh) midiConnected=\(midiConn)"
            )
            pitchResultCount += 1

            if enriched.amplitude >= PracticeConstants.silenceThreshold,
                enriched.confidence >= PracticeConstants.confidenceThreshold
            {
                processMelodyPitch(enriched)
            } else {
                belowThresholdCount += 1
                clearMelodyHighlight()
            }
        }
        Self.logger.info(
            "MicDiag: melody task stream ended (results=\(pitchResultCount) belowThresh=\(belowThresholdCount))"
        )
    }

    /// Process a pitch that passed amplitude and confidence thresholds.
    private func processMelodyPitch(_ enriched: PitchResult) {
        currentPitch = enriched
        lastMelodyDetectionDate = Date()
        let midiNote = Self.midiNoteFromFrequency(enriched.frequency)
        if !isMIDIConnected {
            Self.logger.info(
                "MicDiag: highlight note=\(midiNote) (\(enriched.noteName, privacy: .public)\(enriched.octave))"
            )
            detectedMidiNotes = [midiNote]
            updateDetectedSwarInfo(from: detectedMidiNotes)
        } else {
            Self.logger.info("MicDiag: MIDI connected — skipping detectedMidiNotes update")
        }
        routeNoteToScoring(midiNote: midiNote)
    }

    /// Clear melody highlight state when pitch falls below threshold.
    private func clearMelodyHighlight() {
        currentPitch = nil
        if !isMIDIConnected {
            detectedMidiNotes = []
            highlightState.detectedSwarInfo = nil
        }
        lastGuidedMidiNote = nil
    }

    /// Calculate RMS amplitude from audio samples.
    ///
    /// - Parameter samples: Float audio samples.
    /// - Returns: Root-mean-square amplitude (0.0–1.0).
    private static func calculateRMS(_ samples: [Float]) -> Float {
        var sum: Float = 0
        for s in samples { sum += s * s }
        return sqrt(sum / Float(samples.count))
    }

    /// Handle a note detected in guided free-play mode (before/after timed playback).
    ///
    /// Compares the detected MIDI note against the expected note at
    /// `currentNoteIndex`. On correct: flash green, advance to next note.
    /// On wrong: flash red, keep waiting. Resets the patience timer on every
    /// detected note so the hint only fires during silence.
    ///
    /// - Parameter midiNote: MIDI note number of the detected pitch.
    private func handleGuidedNoteDetected(midiNote: Int) {
        guard let index = currentNoteIndex, index < noteEvents.count else { return }

        // Debounce: only score when the MIDI note changes (new onset).
        // The mic fires ~20 frames/second while a note is held — without this
        // the note would be scored and the index would advance multiple times
        // before the user releases the key.
        guard midiNote != lastGuidedMidiNote else { return }
        lastGuidedMidiNote = midiNote

        let expectedEvent = noteEvents[index]
        let isCorrect = Int(expectedEvent.midiNote) == midiNote

        // Any note input resets the patience timer (user is actively playing)
        isStuck = false
        startPatienceTimer()

        let detectedSwarName = swarNameFromMIDI(UInt8(clamping: midiNote))
        let centsDeviation: Double
        if let pitch = currentPitch {
            centsDeviation = abs(pitch.ragaCentsOffset ?? pitch.centsOffset)
        } else {
            centsDeviation = isCorrect ? 0 : 50
        }

        if isCorrect {
            handleGuidedCorrectNote(
                event: expectedEvent,
                index: index,
                detectedSwarName: detectedSwarName,
                centsDeviation: centsDeviation
            )
        } else {
            handleGuidedWrongNote(event: expectedEvent)
        }
    }

    /// Score a correct guided-mode note and advance to the next event.
    private func handleGuidedCorrectNote(
        event: NoteEvent,
        index: Int,
        detectedSwarName: String,
        centsDeviation: Double
    ) {
        noteStates[event.id] = .correct
        let score = NoteScoreCalculator.score(
            expectedNote: event.swarName,
            detectedNote: detectedSwarName,
            pitchDeviationCents: centsDeviation,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            ragaPitchDeviationCents: currentPitch?.ragaCentsOffset.map { abs($0) },
            ragaContext: ragaScoringContext
        )
        appendScore(score)
        updateStreakForHit(grade: score.grade)
        accuracy = noteScores.isEmpty ? 0 : accuracySum / Double(noteScores.count)
        guidedPlayState = .correct
        lastGuidedMidiNote = nil

        let nextIndex = index + 1
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(150))
            if nextIndex < self.noteEvents.count {
                self.currentNoteIndex = nextIndex
                self.updateExpectedMidiNote()
                self.guidedPlayState = .waitingForNote
                self.isStuck = false
                self.startPatienceTimer()
            } else {
                self.currentNoteIndex = nil
                self.expectedMidiNote = nil
                self.guidedPlayState = .waitingForNote
            }
        }
    }

    /// Flash wrong feedback and reset debounce for the next attempt.
    private func handleGuidedWrongNote(event: NoteEvent) {
        noteStates[event.id] = .wrong
        guidedPlayState = .wrong
        lastGuidedMidiNote = nil
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(100))
            if self.guidedPlayState == .wrong {
                self.guidedPlayState = .waitingForNote
            }
        }
    }

    /// Update `expectedMidiNote` from the current `currentNoteIndex`.
    private func updateExpectedMidiNote() {
        if let index = currentNoteIndex, index < noteEvents.count {
            expectedMidiNote = Int(noteEvents[index].midiNote)
        } else {
            expectedMidiNote = nil
        }
    }

    /// Start the patience timer for the current expected note.
    ///
    /// After `patienceSeconds` of silence, transitions to `.stuck` state
    /// so the view can show a hint overlay.
    private func startPatienceTimer() {
        patienceTimerTask?.cancel()
        patienceTimerTask = Task { [weak self] in
            guard let self else { return }
            let timeout = self.patienceSeconds
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            // Only mark stuck when in guided mode (not during timed playback)
            if self.playbackState == .idle || self.playbackState == .paused {
                self.isStuck = true
                self.guidedPlayState = .stuck
            }
        }
    }

    /// Enrich a pitch result with raga-aware mapping when a mapper is configured.
    ///
    /// When a `RagaAwareMapper` is available, re-maps the frequency to get JI
    /// cents offset and in-raga status. Falls through to the original result otherwise.
    ///
    /// - Parameter pitch: Raw pitch result from the audio processor.
    /// - Returns: Enriched pitch result with `isInRaga` and `ragaCentsOffset` set.
    private func enrichPitchWithRagaContext(_ pitch: PitchResult) -> PitchResult {
        guard let mapper = ragaMapper else { return pitch }
        do {
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

    /// Configure raga-aware scoring context from the song's raga name.
    ///
    /// Creates a `RagaScoringContext` and `RagaAwareMapper` when a known raga
    /// name is provided. Clears both and falls back to 12ET for unknown ragas.
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
            Self.logger.info("Raga context configured: \(ragaName, privacy: .public)")
        } else {
            ragaMapper = nil
            Self.logger.info("Unknown raga '\(ragaName, privacy: .public)' — using equal temperament")
        }
    }

    /// Convert a frequency in Hz to the nearest MIDI note number.
    ///
    /// Uses the equal-temperament formula relative to A4 = 440 Hz.
    ///
    /// - Parameter frequency: Frequency in Hz. Values <= 0 return middle C (60).
    /// - Returns: MIDI note number (0–127).
    nonisolated private static func midiNoteFromFrequency(_ frequency: Double) -> Int {
        guard frequency > 0 else { return 60 }
        return Int((12.0 * log2(frequency / 440.0) + 69.0).rounded())
    }

    // MARK: - Private Methods — Playback Scheduling

    /// Schedule note-by-note playback from the beginning.
    ///
    /// Creates a single task that iterates through all note events,
    /// sleeping until each note's scheduled time using the injected clock
    /// for drift-corrected timing.
    private func startPlayback() {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.runPlaybackLoop(fromIndex: 0, timeOffset: 0)
        }
    }

    /// Schedule note playback resuming from the current position.
    ///
    /// Finds the next unplayed note after `pauseElapsed` and starts
    /// the playback loop from that point.
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

    /// Core playback loop that schedules notes sequentially.
    ///
    /// For each note event starting at `fromIndex`, sleeps until the
    /// note's tempo-scaled timestamp, plays the note sound, updates
    /// the current note index, and handles wait mode if enabled.
    ///
    /// - Parameters:
    ///   - fromIndex: Index of the first note to schedule.
    ///   - timeOffset: Additional time offset in seconds (unused, reserved).
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
                    return  // Task was cancelled
                }
            }

            guard !Task.isCancelled else { return }

            playNoteSound(event: event)

            currentNoteIndex = index
            noteStates[event.id] = .active
            markPreviousNotesAsMissed(beforeIndex: index)

            do {
                if try await awaitWaitModeResolution(index: index) {
                    return  // Task was cancelled during wait
                }
            } catch {
                return  // Task was cancelled during wait
            }
        }

        await awaitLastNoteCompletion()
        guard !Task.isCancelled else { return }
        completeSession()
    }

    /// Play SoundFont note-on and schedule note-off after scaled duration.
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

    /// Mark all prior notes still in `.active` state as missed.
    private func markPreviousNotesAsMissed(beforeIndex index: Int) {
        for prevIndex in 0..<index {
            let prevEvent = noteEvents[prevIndex]
            if noteStates[prevEvent.id] == .active {
                noteStates[prevEvent.id] = .missed
                appendScore(NoteScoreCalculator.missedNote(expectedNote: prevEvent.swarName))
                updateStreakForMiss()
            }
        }
    }

    /// Block the playback loop in wait mode until the note is resolved.
    ///
    /// - Returns: `true` if the Task was cancelled while waiting (caller should return).
    private func awaitWaitModeResolution(index: Int) async throws -> Bool {
        guard isWaitModeEnabled, let waitCtrl = waitController else { return false }
        waitCtrl.setCurrentNoteIndex(index)
        while waitCtrl.isWaitingForNote, !Task.isCancelled {
            try? await clock.sleep(for: .milliseconds(50))
        }
        return Task.isCancelled
    }

    /// Sleep until the last note's full duration has elapsed, then return.
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

    // MARK: - Private Methods — Display Link

    /// Start a ~30 Hz task to update the current playback position.
    ///
    /// Reads elapsed time from the clock and updates `currentTime`
    /// for smooth UI scrolling and note highlighting.
    private func startDisplayLink() {
        displayLinkTask?.cancel()
        displayLinkTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.playbackState == .playing else { return }
                if let startTime = self.playbackStartTime {
                    let elapsed = self.clock.now - startTime
                    self.currentTime = self.elapsedSeconds(from: elapsed) * self.tempoScale
                }
                // 50 ms (20 Hz) instead of 33 ms (30 Hz).
                // At 200 BPM with 16th notes each note arrives every ~150 ms,
                // so 20 Hz position updates are still smooth while freeing the
                // main actor ~17 ms per cycle for MIDI scoring tasks.
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    // MARK: - Private Methods — Note Input Processing

    /// Process a note input (from either keyboard touch or pitch detection).
    ///
    /// Scoring arithmetic runs on `NoteMatchingActor` (off `@MainActor`) so it never
    /// competes with SwiftUI's falling-notes render pass. Only the resulting
    /// `ScoringDiff` hops back to update `@Observable` state on `@MainActor`.
    ///
    /// Wait-mode evaluation via `PlayAlongWaitController` still happens here on
    /// `@MainActor` (the controller is `@MainActor`-isolated) — the boolean result
    /// is then passed as a `Sendable` value to the actor.
    ///
    /// - Parameter midiNote: MIDI note number of the input.
    private func processNoteInput(midiNote: Int) async {
        guard let index = currentNoteIndex,
            index < noteEvents.count
        else { return }

        let expectedEvent = noteEvents[index]

        // Evaluate wait-mode match here on @MainActor (PlayAlongWaitController is
        // @MainActor-isolated). Pass the Bool result to the actor as a Sendable value.
        let waitModeMatch: Bool?
        if isWaitModeEnabled, let waitCtrl = waitController {
            let detectedSwarName = swarNameFromMIDI(UInt8(clamping: midiNote))
            waitModeMatch = waitCtrl.evaluateAttempt(detectedNoteName: detectedSwarName)
        } else {
            waitModeMatch = nil
        }

        // Snapshot Sendable values before crossing actor boundary.
        let pitch = currentPitch
        let ragaContext = ragaScoringContext

        // Compute timing deviation: difference between actual onset and expected onset.
        // In wait mode, timing is not scored (defaults to 0 via evaluateWaitMode).
        let onsetDeviation = abs(currentTime - expectedEvent.timestamp)

        // Duration deviation requires note-off tracking (not yet implemented).
        // Pass 0 until note-off timestamps are captured in a future task.
        let durDeviation = 0.0

        let diff = await noteMatchingActor.evaluate(
            midiNote: midiNote,
            expectedEvent: expectedEvent,
            currentPitch: pitch,
            ragaScoringContext: ragaContext,
            waitModeMatch: waitModeMatch,
            timingDeviationSeconds: onsetDeviation,
            durationDeviation: durDeviation
        )

        // Apply the diff back on @MainActor — only three writes, no re-render
        // of the full note list.
        noteStates[diff.noteEventID] = diff.newState
        if let score = diff.score {
            appendScore(score)
        }
        switch diff.streakOutcome {
        case .hit(let grade):
            updateStreakForHit(grade: grade)
        case .miss:
            updateStreakForMiss()
        case .noChange:
            break
        }
        accuracy = noteScores.isEmpty ? 0 : accuracySum / Double(noteScores.count)
    }

    /// Derive the full swar name from a MIDI note number.
    ///
    /// Uses the pre-built O(1) `Swar.nameForSemitone` dictionary (AUD-029)
    /// instead of an O(n) `allCases.first` scan per note input event.
    ///
    /// - Parameter midiNote: MIDI note number (0-127).
    /// - Returns: Full swar name string (e.g., "Komal Re"). Falls back to "Sa".
    private func swarNameFromMIDI(_ midiNote: UInt8) -> String {
        let semitone = Int(midiNote) % 12
        return Swar.nameForSemitone[semitone] ?? Swar.sa.rawValue
    }

    // MARK: - Private Methods — Score Bookkeeping

    /// Append a note score and maintain `notesHit` and `accuracySum` incrementally.
    ///
    /// All `noteScores.append` calls MUST go through this helper so counters
    /// stay in sync. After calling this, set
    /// `accuracy = noteScores.isEmpty ? 0 : accuracySum / Double(noteScores.count)`.
    private func appendScore(_ score: NoteScore) {
        noteScores.append(score)
        accuracySum += score.accuracy
        if score.grade != .miss {
            notesHit += 1
        }
    }

    // MARK: - Private Methods — Streak Tracking

    /// Update streak counters after a non-miss note.
    private func updateStreakForHit(grade: NoteGrade) {
        if grade != .miss {
            streak += 1
            longestStreak = max(longestStreak, streak)
        } else {
            streak = 0
        }
    }

    /// Reset the current streak after a missed note.
    private func updateStreakForMiss() {
        streak = 0
    }

    // MARK: - Private Methods — Session Completion

    /// Complete the session and calculate final scores.
    ///
    /// Marks any remaining active notes as missed, computes session-level
    /// metrics (accuracy, stars, XP, streak), and transitions to `.stopped`.
    ///
    /// AUD-028/034: All noteStates mutations are batched into a single dictionary
    /// snapshot write — one Canvas redraw instead of N individual property sets.
    private func completeSession() {
        // AUD-028: Build scored-note set once — O(m) instead of O(n) per event.
        let scoredNames = Set(noteScores.map(\.expectedNote))
        var updatedStates = noteStates  // snapshot — one @Observable mutation at the end
        var missedScores: [NoteScore] = []

        for event in noteEvents {
            let state = updatedStates[event.id]
            if state == .active || state == .upcoming {
                updatedStates[event.id] = .missed
                if !scoredNames.contains(event.swarName) {
                    missedScores.append(NoteScoreCalculator.missedNote(expectedNote: event.swarName))
                }
            }
        }

        // AUD-034: Single @Observable write triggers one Canvas redraw.
        noteStates = updatedStates
        missedScores.forEach { appendScore($0) }

        // Calculate final metrics
        accuracy = noteScores.isEmpty ? 0 : accuracySum / Double(noteScores.count)
        starRating = PracticeScoring.starRating(accuracy: accuracy)
        xpEarned = PracticeScoring.xpEarned(
            accuracy: accuracy,
            difficulty: song?.difficulty ?? 1
        )
        longestStreak = max(
            longestStreak,
            PracticeScoring.longestStreak(grades: noteScores.map(\.grade))
        )

        cancelPlaybackTasks()
        soundFont.stopAllNotes()
        playbackState = .stopped

        // Print MIDI diagnostics summary to Console.app
        MIDIEventDiagnostics.shared.printSummary()

        persistSessionResults()
        trackSessionCompletion()
    }

    /// Persist session results to SwiftData via PracticeSessionRecorder.
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
            noteScores: noteScores
        )
        Self.logger.info("Session persisted to SwiftData")
    }

    /// Fire analytics and log for session completion.
    private func trackSessionCompletion() {
        AnalyticsManager.shared.track(
            .songPlaybackCompleted,
            properties: [
                "song_title": song?.title ?? "",
                "accuracy": accuracy,
                "star_rating": starRating,
                "xp_earned": xpEarned,
                "tempo_scale": tempoScale,
                "view_mode": viewMode.rawValue,
            ]
        )
        Self.logger.info(
            "Session completed: accuracy=\(String(format: "%.0f", self.accuracy * 100))%, stars=\(self.starRating)"
        )
    }

    // MARK: - Private Methods — Utilities

    /// Cancel all active playback and display-link tasks.
    private func cancelPlaybackTasks() {
        playbackTask?.cancel()
        playbackTask = nil
        displayLinkTask?.cancel()
        displayLinkTask = nil
        pitchDetectionTask?.cancel()
        pitchDetectionTask = nil
        midiInput.onNoteEvent = nil
        midiInput.onControlChangeEvent = nil
        midiConnectionTask?.cancel()
        midiConnectionTask = nil
        patienceTimerTask?.cancel()
        patienceTimerTask = nil
    }

    /// Convert a `Duration` to seconds as a `TimeInterval`.
    ///
    /// Uses the components API to avoid floating-point precision issues.
    ///
    /// - Parameter duration: The duration to convert.
    /// - Returns: Elapsed time in seconds.
    private func elapsedSeconds(from duration: Duration) -> TimeInterval {
        Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    }
}
