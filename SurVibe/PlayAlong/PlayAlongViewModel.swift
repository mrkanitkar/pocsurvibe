import Foundation
import SVAudio
import SVCore
import SVLearning
import SwiftData
import SwiftUI
import os.log

/// Main view model for the play-along experience (facade).
///
/// Composes four coordinators, each owning a slice of play-along behavior:
///
/// - `scoring` (SP-3a): note scores, accuracy, streaks, stars, XP.
/// - `playback` (SP-3b): transport state, scheduling, session completion, persistence.
/// - `chrome` (SP-3c): chrome visibility + view modes + resolved theme colors.
/// - `noteRouter` (SP-3d): mic pitch, chord detection, MIDI input, scoring dispatch,
///   raga enrichment, guided free-play, `latencyPreset`.
///
/// The VM itself holds no play-along state. Every public property and method
/// forwards to one of the coordinators so existing views and tests continue to
/// call `viewModel.currentPitch`, `viewModel.handleKeyboardTouch(...)`, etc.
/// unchanged (spec AD-1 facade).
@Observable
@MainActor
final class PlayAlongViewModel {
    // MARK: - Published State — delegated to coordinators

    /// Current playback state — delegates to `playback.playbackState`.
    var playbackState: PlaybackState { playback.playbackState }

    /// Ordered note events — delegates to `playback.noteEvents`.
    var noteEvents: [NoteEvent] { playback.noteEvents }

    /// Current note index — delegates to `playback.currentNoteIndex` (read+write).
    var currentNoteIndex: Int? {
        get { playback.currentNoteIndex }
        set { playback.currentNoteIndex = newValue }
    }

    /// Per-note state — delegates to `playback.noteStates` (read+write).
    var noteStates: [UUID: FallingNotesLayoutEngine.NoteState] {
        get { playback.noteStates }
        set { playback.noteStates = newValue }
    }

    /// Accumulated individual note scores for the session. Delegates to `scoring.noteScores`.
    var noteScores: [NoteScore] { scoring.noteScores }

    /// Count of non-miss note scores. Delegates to `scoring.notesHit`.
    var notesHit: Int { scoring.notesHit }

    /// Current playback position in seconds — delegates to `playback.currentTime`.
    var currentTime: TimeInterval { playback.currentTime }

    /// Total duration of the song in seconds — delegates to `playback.duration`.
    var duration: TimeInterval { playback.duration }

    /// Normalized playback progress (0.0 to 1.0) — delegates to `playback.playbackProgress`.
    var playbackProgress: Double { playback.playbackProgress }

    /// Total playback duration in seconds — delegates to `playback.playbackDuration`.
    var playbackDuration: TimeInterval { playback.playbackDuration }

    /// Seek to a normalized position (0.0 to 1.0) in the song.
    ///
    /// Delegates to `playback.seek(to:)`.
    ///
    /// - Parameter progress: Normalized position from 0.0 (start) to 1.0 (end).
    func seek(to progress: Double) {
        playback.seek(to: progress)
    }

    /// Overall session accuracy (0.0-1.0). Delegates to `scoring.accuracy`.
    var accuracy: Double { scoring.accuracy }

    /// Current streak of consecutive non-miss notes. Delegates to `scoring.streak`.
    var streak: Int { scoring.streak }

    /// Longest streak achieved during this session. Delegates to `scoring.longestStreak`.
    var longestStreak: Int { scoring.longestStreak }

    /// Star rating (1-5) computed at session completion. Delegates to `scoring.starRating`.
    var starRating: Int { scoring.starRating }

    /// XP earned, computed at session completion. Delegates to `scoring.xpEarned`.
    var xpEarned: Int { scoring.xpEarned }

    /// Percentage of expected notes the user pressed correctly (0.0–1.0).
    ///
    /// Populated by `scoring.finalize`. Zero until session completion.
    /// Delegates to `scoring.notesCorrectPercent`.
    var notesCorrectPercent: Double { scoring.notesCorrectPercent }

    /// Weighted timing accuracy (0.0–1.0). Zero until session completion.
    ///
    /// Populated by `scoring.finalize`. Delegates to `scoring.timingAccuracyPercent`.
    var timingAccuracyPercent: Double { scoring.timingAccuracyPercent }

    /// Human-readable error message — delegates to `playback.errorMessage`.
    var errorMessage: String? { playback.errorMessage }

    /// Whether wait mode is enabled — delegates to `playback.isWaitModeEnabled` (read+write).
    var isWaitModeEnabled: Bool {
        get { playback.isWaitModeEnabled }
        set { playback.isWaitModeEnabled = newValue }
    }

    /// Tempo scaling factor — delegates to `playback.tempoScale` (read+write).
    var tempoScale: Double {
        get { playback.tempoScale }
        set { playback.tempoScale = newValue }
    }

    /// Whether SoundFont playback is enabled — delegates to `playback.isSoundEnabled` (read+write).
    var isSoundEnabled: Bool {
        get { playback.isSoundEnabled }
        set { playback.isSoundEnabled = newValue }
    }

    /// Visual display mode — delegates to `chrome.viewMode` (read+write).
    var viewMode: PlayAlongViewMode {
        get { chrome.viewMode }
        set { chrome.viewMode = newValue }
    }

    /// Notation label display mode — delegates to `chrome.notationMode` (read+write).
    var notationMode: NotationDisplayMode {
        get { chrome.notationMode }
        set { chrome.notationMode = newValue }
    }

    // MARK: - Resolved Theme Colors (v2) — delegates to chrome coordinator (SP-3c)

    /// Right-hand accent color — delegates to `chrome.rhColor` (read+write).
    var rhColor: Color {
        get { chrome.rhColor }
        set { chrome.rhColor = newValue }
    }

    /// Left-hand accent color — delegates to `chrome.lhColor` (read+write).
    var lhColor: Color {
        get { chrome.lhColor }
        set { chrome.lhColor = newValue }
    }

    /// Chord accent color — delegates to `chrome.chordColor` (read+write).
    var chordColor: Color {
        get { chrome.chordColor }
        set { chrome.chordColor = newValue }
    }

    /// Notation primary line color — delegates to `chrome.notationLineColor` (read+write).
    var notationLineColor: Color {
        get { chrome.notationLineColor }
        set { chrome.notationLineColor = newValue }
    }

    /// Notation secondary color — delegates to `chrome.notationSecondaryColor` (read+write).
    var notationSecondaryColor: Color {
        get { chrome.notationSecondaryColor }
        set { chrome.notationSecondaryColor = newValue }
    }

    /// Card background color — delegates to `chrome.cardBackgroundColor` (read+write).
    var cardBackgroundColor: Color {
        get { chrome.cardBackgroundColor }
        set { chrome.cardBackgroundColor = newValue }
    }

    /// Karaoke background color — delegates to `chrome.karaokeBackgroundColor` (read+write).
    var karaokeBackgroundColor: Color {
        get { chrome.karaokeBackgroundColor }
        set { chrome.karaokeBackgroundColor = newValue }
    }

    // MARK: - NoteRouter-owned state (SP-3d) — delegating computed properties

    /// Latency preset — delegates to `noteRouter.latencyPreset` (read+write).
    var latencyPreset: LatencyPreset {
        get { noteRouter.latencyPreset }
        set { noteRouter.latencyPreset = newValue }
    }

    /// Latest pitch detection result — delegates to `noteRouter.currentPitch`.
    var currentPitch: PitchResult? { noteRouter.currentPitch }

    /// MIDI notes currently detected — delegates to `noteRouter.detectedMidiNotes`.
    var detectedMidiNotes: Set<Int> { noteRouter.detectedMidiNotes }

    /// Isolated highlight observable — delegates to `noteRouter.highlightState`.
    var highlightState: HighlightState { noteRouter.highlightState }

    /// Effective MIDI notes to highlight — delegates to `noteRouter.effectiveMidiNotes`.
    var effectiveMidiNotes: Set<Int> { noteRouter.effectiveMidiNotes }

    /// USB/Bluetooth MIDI connection state — delegates to `noteRouter.isMIDIConnected`.
    var isMIDIConnected: Bool { noteRouter.isMIDIConnected }

    /// Human-readable MIDI device name — delegates to `noteRouter.midiDeviceName`.
    var midiDeviceName: String? { noteRouter.midiDeviceName }

    /// Guided free-play feedback state — delegates to `noteRouter.guidedPlayState`.
    var guidedPlayState: NoteRouter.GuidedPlayState { noteRouter.guidedPlayState }

    /// MIDI note expected in guided mode — delegates to `noteRouter.expectedMidiNote`.
    var expectedMidiNote: Int? { noteRouter.expectedMidiNote }

    /// Whether the patience timer expired — delegates to `noteRouter.isStuck`.
    var isStuck: Bool { noteRouter.isStuck }

    /// Legacy typealias for external code referencing the old nested enum location.
    /// `SongPlayAlongView+Subviews.swift` uses this to observe guided-play state.
    typealias GuidedPlayState = NoteRouter.GuidedPlayState

    // MARK: - Wave 4 D1 — Toolbar state (Wave 5 E1 wires to ArrangementPlayer)

    /// Backing accompaniment mode shown in the play-along toolbar.
    ///
    /// `.on` plays the full backing track; `.click` plays a metronome-style
    /// click only; `.off` mutes the accompaniment entirely. Wiring to the
    /// arrangement player is deferred to Wave 5 (E1).
    public enum BackingMode: String, Sendable, Equatable, CaseIterable {
        /// Full backing accompaniment plays.
        case on
        /// Metronome click only — no accompaniment instruments.
        case click
        /// Silent — no backing or click.
        case off
    }

    /// Click-track loudness preset shown in the toolbar when
    /// `backingMode == .click`.
    ///
    /// Wiring to the click sampler is deferred to Wave 5 (E1).
    public enum ClickLevel: String, Sendable, Equatable, CaseIterable {
        /// Quiet click — accent only.
        case soft
        /// Default click level.
        case normal
        /// Loud click — useful for noisy practice rooms.
        case loud
    }

    /// Selected backing accompaniment mode for the play-along session.
    ///
    /// Defaults to `.on`. Bound to the toolbar's backing-mode picker.
    public var backingMode: BackingMode = .on

    /// Tempo multiplier in the range `0.5...1.5`.
    ///
    /// Set values outside the range are clamped on assignment. Defaults to
    /// `1.0` (original tempo). Bound to the toolbar's tempo slider. The
    /// existing `tempoScale` (delegated to `PlaybackCoordinator`) drives the
    /// legacy 4-preset path; this Wave 4 D1 property powers the continuous
    /// slider and is wired to `ArrangementPlayer` in Wave 5 (E1).
    public var arrangementTempoScale: Double = 1.0 {
        didSet {
            let clamped = min(1.5, max(0.5, arrangementTempoScale))
            if clamped != arrangementTempoScale {
                arrangementTempoScale = clamped
            }
        }
    }

    /// Hand isolation mode for the play-along session.
    ///
    /// Defaults to `.both`. RH/LH are only meaningful when the loaded
    /// arrangement contains multiple staves (`hasMultipleStaves == true`).
    /// Bound to the toolbar's hands picker.
    public var practiceMode: PracticeMode = .both

    /// Active loop region (1-indexed inclusive measures), if any.
    ///
    /// `nil` means full-song playback. Bound to the toolbar's loop control.
    public var loopRegion: LoopRegion?

    /// Loudness preset for the click track when `backingMode == .click`.
    ///
    /// Defaults to `.normal`. Bound to the toolbar's click-level picker.
    public var clickLevel: ClickLevel = .normal

    /// Whether the loop-builder sheet should be presented.
    ///
    /// The toolbar flips this to `true` when the user taps "Loop" with no
    /// active region; the host view observes it to drive sheet presentation.
    public var showLoopBuilder: Bool = false

    /// Whether the currently loaded arrangement exposes more than one
    /// staff (e.g., separate RH and LH).
    ///
    /// When `false`, RH/LH options in the hands picker are disabled.
    /// `PlayAlongSceneHost` updates this from `PartSplit` after song load.
    public var hasMultipleStaves: Bool = false

    // MARK: - Chrome Visibility (v2) — delegates to chrome coordinator (SP-3c)

    /// Chrome visibility — delegates to `chrome.chromeVisibility`.
    var chromeVisibility: PlayAlongChromeState.ChromeVisibility { chrome.chromeVisibility }

    // MARK: - Chrome Actions (v2) — delegates to chrome coordinator

    /// Show the chrome and start/restart the auto-hide countdown.
    func summonChrome() {
        chrome.summonChrome()
    }

    /// Reset the auto-hide countdown (user interaction with a control).
    func resetAutoHide() {
        chrome.resetAutoHide()
    }

    /// Hide chrome immediately. Cancels any pending auto-hide timer.
    func hideChrome() {
        chrome.hideChrome()
    }

    // MARK: - Delegating passthroughs

    /// Model context for persistence — delegates to `playback.modelContext`.
    var modelContext: ModelContext? {
        get { playback.modelContext }
        set { playback.modelContext = newValue }
    }

    /// Wall-clock Date for FallingNotesView animation — delegates to `playback.playbackStartDate`.
    var playbackStartDate: Date? { playback.playbackStartDate }

    private static let logger = Logger.survibe(category: "PlayAlong")

    // MARK: - Coordinators (SP-3 extraction)

    /// Scoring coordinator — owns note scores, accuracy, streaks,
    /// star rating, and XP. SP-3a extraction.
    let scoring: ScoringCoordinator

    /// Playback coordinator — owns transport state, scheduling, session
    /// completion, and persistence. SP-3b extraction.
    let playback: PlaybackCoordinator

    /// Chrome state coordinator — owns visibility + view modes + resolved
    /// theme colors. SP-3c extraction.
    let chrome = PlayAlongChromeState()

    /// Note router coordinator — owns input detection (mic, MIDI, keyboard),
    /// scoring dispatch, raga enrichment, and guided free-play. SP-3d extraction.
    let noteRouter: NoteRouter

    // MARK: - Initialization

    /// Create a play-along view model with injectable dependencies.
    ///
    /// All parameters default to production singletons when `nil` is passed.
    /// Tests inject mocks for deterministic behavior without audio hardware.
    ///
    /// - Parameters:
    ///   - soundFont: SoundFont player for note playback. Defaults to
    ///     `MultiChannelTouchSoundFont()` (routes to multiChannel.samplers[0]).
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
        MultiChannelLog.shared.log(.info, ">>> PlayAlongViewModel.init")
        let scoring = ScoringCoordinator()
        self.scoring = scoring
        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.init: scoring constructed; about to resolve dependencies")
        let resolvedSoundFont = soundFont ?? MultiChannelTouchSoundFont()
        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.init: soundFont resolved")
        let resolvedEngine: any AudioEngineProviding = audioEngine ?? AudioEngineManager.shared
        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.init: audioEngine resolved")
        let resolvedMetronome = metronome ?? MetronomePlayer.shared
        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.init: metronome resolved")
        let resolvedClock = clock ?? RealClock()
        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.init: clock resolved")
        let resolvedMIDI = midiInput ?? MIDIInputManager.shared
        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.init: midiInput resolved")
        self.playback = PlaybackCoordinator(
            soundFont: resolvedSoundFont,
            audioEngine: resolvedEngine,
            metronome: resolvedMetronome,
            clock: resolvedClock,
            scoring: scoring,
            analytics: nil  // nil-sentinel — uses AnalyticsManager.shared at call time
        )
        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.init: PlaybackCoordinator constructed")
        self.noteRouter = NoteRouter(
            midiInput: resolvedMIDI,
            scoring: scoring,
            playback: playback
        )
        MultiChannelLog.shared.log(.info, "<<< PlayAlongViewModel.init DONE")
    }

    // MARK: - Public Methods — lifecycle

    /// Load a song and prepare note events for play-along.
    ///
    /// Delegates song parsing and note-state initialization to `PlaybackCoordinator`,
    /// wires raga context and guided-play hooks via `NoteRouter`, then starts the
    /// mic/MIDI detection pipelines.
    ///
    /// Sets `playbackState` to `.error` if neither MIDI nor notation data is found.
    ///
    /// - Parameter song: The Song model to load.
    func loadSong(_ song: Song) async {
        MultiChannelLog.shared.log(.info, ">>> PlayAlongViewModel.loadSong(\(song.title))")
        guard playback.loadSong(song) else { return }
        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.loadSong: playback.loadSong returned ok=true")

        noteRouter.configureRagaContext(ragaName: song.ragaName)
        noteRouter.updateExpectedMidiNote()

        let micGranted = await PermissionManager.shared.requestMicrophoneAccess()
        if !micGranted {
            Self.logger.warning("Microphone permission denied — pitch detection unavailable")
        }

        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.loadSong: starting input detection")
        noteRouter.startInputDetection()
        noteRouter.resetGuidedPlay()

        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.loadSong: about to startForPlayback")
        do {
            try AudioEngineManager.shared.startForPlayback()
            MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.loadSong: startForPlayback returned")
        } catch {
            MultiChannelLog.shared.log(
                .info,
                "... PlayAlongViewModel.loadSong: startForPlayback THREW: \(error.localizedDescription)"
            )
            Self.logger.error("Audio engine start failed: \(error.localizedDescription)")
        }
        MultiChannelLog.shared.log(.info, "<<< PlayAlongViewModel.loadSong DONE")
    }

    /// Start the play-along session from the beginning.
    ///
    /// Delegates engine start, metronome, scheduling, and analytics to
    /// `PlaybackCoordinator`. Re-starts `NoteRouter` input detection to handle
    /// the case where it was stopped after a previous cleanup.
    ///
    /// Guards: only starts from `.idle` or `.stopped` with non-empty events.
    func startSession() async {
        MultiChannelLog.shared.log(.info, ">>> PlayAlongViewModel.startSession")
        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.startSession: about to await startScheduling")
        await playback.startScheduling()
        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.startSession: startScheduling returned")
        noteRouter.startInputDetection()
        MultiChannelLog.shared.log(.info, "<<< PlayAlongViewModel.startSession")
    }

    /// Pause the current play-along session.
    ///
    /// Delegates transport pause to `PlaybackCoordinator`. Keeps `NoteRouter`
    /// detection running for keyboard highlight, and re-arms guided free-play
    /// patience timer via `noteRouter.resetGuidedPlay()`.
    func pauseSession() {
        playback.pauseScheduling()
        noteRouter.startInputDetection()
        noteRouter.updateExpectedMidiNote()
        noteRouter.resetGuidedPlay()
    }

    /// Resume the play-along session from the paused position.
    ///
    /// Delegates clock adjustment, display link, and scheduling restart to
    /// `PlaybackCoordinator`. Pitch detection keeps running continuously.
    func resumeSession() {
        playback.resumeScheduling()
    }

    /// Called when the user toggles wait mode. Updates state and fires analytics.
    func toggleWaitMode() {
        playback.isWaitModeEnabled.toggle()
        AnalyticsManager.shared.track(
            .waitModeToggled,
            properties: [
                "enabled": playback.isWaitModeEnabled,
                "song_title": playback.song?.title ?? "",
            ]
        )
    }

    /// Stop the session early and compute results from notes scored so far.
    ///
    /// Delegates to `PlaybackCoordinator` which marks remaining notes as missed,
    /// finalizes scoring, persists results, and transitions to `.stopped`.
    func stopAndComplete() {
        playback.stopAndComplete()
    }

    /// Clean up all resources and cancel active tasks.
    ///
    /// Delegates playback-side teardown to `PlaybackCoordinator` and input-side
    /// teardown to `NoteRouter`.
    ///
    /// Call from the view's `onDisappear` to ensure no orphaned tasks or audio
    /// resources remain.
    func cleanup() {
        playback.cleanup()
        noteRouter.stopInputDetection()
        MIDIEventDiagnostics.shared.printSummary()
        Self.logger.info("Play-along cleanup complete (facade)")
    }

    // MARK: - Public Methods — input handlers (delegating to NoteRouter)

    /// Handle a note detected from pitch detection or MIDI input.
    ///
    /// Delegates to `noteRouter.handleNoteDetected(midiNote:)`.
    ///
    /// - Parameter midiNote: MIDI note number of the detected pitch.
    func handleNoteDetected(midiNote: Int) {
        noteRouter.handleNoteDetected(midiNote: midiNote)
    }

    /// Handle a note-on event from the on-screen piano keyboard.
    ///
    /// Delegates to `noteRouter.handleKeyboardNoteOn(midiNote:)`.
    ///
    /// - Parameter midiNote: MIDI note number of the pressed key.
    func handleKeyboardNoteOn(midiNote: Int) {
        noteRouter.handleKeyboardNoteOn(midiNote: midiNote)
    }

    /// Handle a note-off event from the on-screen piano keyboard.
    ///
    /// Delegates to `noteRouter.handleKeyboardNoteOff(midiNote:)`.
    ///
    /// - Parameter midiNote: MIDI note number of the released key.
    func handleKeyboardNoteOff(midiNote: Int) {
        noteRouter.handleKeyboardNoteOff(midiNote: midiNote)
    }

    /// Awaitable on-screen keyboard touch handler for test call sites.
    ///
    /// Delegates to `noteRouter.handleKeyboardTouch(midiNote:)`.
    ///
    /// - Parameter midiNote: MIDI note number of the touched key.
    func handleKeyboardTouch(midiNote: Int) async {
        await noteRouter.handleKeyboardTouch(midiNote: midiNote)
    }

    /// Handle an on-screen keyboard touch in guided free-play mode.
    ///
    /// Delegates to `noteRouter.handleKeyboardTouchGuided(midiNote:)`.
    ///
    /// - Parameter midiNote: MIDI note number of the touched key.
    func handleKeyboardTouchGuided(midiNote: Int) {
        noteRouter.handleKeyboardTouchGuided(midiNote: midiNote)
    }

    /// Skip the current expected note and advance to the next one.
    ///
    /// Called when the user taps the hint skip button after getting stuck.
    /// Delegates to `noteRouter.skipGuidedNote()`.
    func skipGuidedNote() {
        noteRouter.skipGuidedNote()
    }
}
