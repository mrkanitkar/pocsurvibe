import AVFoundation
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

    /// Unified tempo scaling factor (Wave 5 E1).
    ///
    /// Single source of truth for the play-along session's tempo. Setting
    /// this updates the legacy `playback.tempoScale` (so legacy preset
    /// pills stay in sync), pushes the same value to the wired
    /// `ArrangementPlayer` (when present), and is clamped to
    /// `[0.5, 1.5]` — the intersection of the legacy presets
    /// (`0.4`–`1.0`) and the Wave 4 D1 slider range (`0.5`–`1.5`).
    /// Values outside the range are clamped on assignment.
    var tempoScale: Double {
        get { playback.tempoScale }
        set {
            let clamped = min(1.5, max(0.5, newValue))
            playback.tempoScale = clamped
            arrangementTempoScale = clamped
            arrangementPlayer?.setTempoScale(Float(clamped))
        }
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
                return
            }
            // Mirror the slider value into the legacy `tempoScale` and
            // push to ArrangementPlayer. Guarded against the recursive
            // `tempoScale` setter (which clamps + re-assigns this same
            // property) by checking that the legacy value differs.
            if abs(playback.tempoScale - clamped) > 0.0001 {
                playback.tempoScale = clamped
            }
            arrangementPlayer?.setTempoScale(Float(clamped))
        }
    }

    /// Hand isolation mode for the play-along session.
    ///
    /// Defaults to `.both`. RH/LH are only meaningful when the loaded
    /// arrangement contains multiple staves (`hasMultipleStaves == true`).
    /// Bound to the toolbar's hands picker. Wave 5 E1: forwards to
    /// `ArrangementPlayer.practiceMode` when an arrangement is wired.
    public var practiceMode: PracticeMode = .both {
        didSet {
            arrangementPlayer?.practiceMode = practiceMode
        }
    }

    /// Whether the muted hand should still sound through the
    /// accompaniment sampler. Defaults to `true` (matches
    /// `ArrangementPlayer.hearOtherHand`). Wave 5 E1: forwarded to
    /// `ArrangementPlayer.hearOtherHand` when an arrangement is wired.
    public var hearOtherHand: Bool = true {
        didSet {
            arrangementPlayer?.hearOtherHand = hearOtherHand
        }
    }

    /// Active loop region (1-indexed inclusive measures), if any.
    ///
    /// `nil` means full-song playback. Bound to the toolbar's loop control.
    /// Wave 5 E1: forwarded to `ArrangementPlayer.setLoop(_:)` when an
    /// arrangement is wired.
    public var loopRegion: LoopRegion? {
        didSet {
            arrangementPlayer?.setLoop(loopRegion)
        }
    }

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

    /// Total measure count of the loaded arrangement (Wave 5 E1).
    ///
    /// Computed from `LearnerScore.notes.last?.measureNumber` after
    /// `loadArrangement(split:)`. Drives the `LoopBuilderView` stepper
    /// upper bound. Defaults to `1` when no arrangement is loaded so the
    /// builder still renders sensibly.
    public var totalMeasures: Int = 1

    /// Whether the "Practice mode — Bluetooth MIDI delay disables
    /// scoring" chip should be visible (Wave 5 E1, spec §D5).
    ///
    /// Set to `true` from `MIDIInputManager.onPracticeModeRequired` when
    /// a Bluetooth endpoint is registered. While `true`, the scoring
    /// path drops MIDI input events; the sampler-trigger / audible echo
    /// path is unaffected.
    public var practiceModeChipVisible: Bool = false

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

    // MARK: - Wave 5 E1 — ArrangementPlayer + ScoringAdapter

    /// Optional accompaniment player wired by `loadArrangement(split:)`.
    ///
    /// `nil` until a `PartSplit` is loaded. The Wave 1–4 audition pipeline
    /// produces splits from MXL/MusicXML; legacy notation-only songs leave
    /// this as `nil` and continue to use the prior visualization-only
    /// playback path.
    private(set) var arrangementPlayer: ArrangementPlayer?

    /// Scoring adapter wired alongside `arrangementPlayer`.
    ///
    /// `nil` until `loadArrangement(split:)` succeeds. Each MIDI note-on
    /// from the active input device is forwarded here together with the
    /// captured host time and current tempo scale (Wave 5 E1).
    private(set) var scoringAdapter: ScoringAdapter?

    /// Currently loaded `PartSplit`, retained so callers can introspect
    /// the learner score / staves without re-running PartSplitter. Set
    /// by `loadArrangement(split:)`; cleared on `cleanup()`.
    private(set) var currentSplit: PartSplit?

    /// Tonic Sa MIDI note for the loaded arrangement. Defaults to MIDI 60
    /// (C4); future tanpura-driven Sa changes can override via
    /// `setTonicSaPitch(_:)`. Forwarded into `ScoringAdapter` on each
    /// `loadArrangement` call.
    public var tonicSaPitch: UInt8 = 60

    #if DEBUG
    /// DEBUG-only end-to-end latency probe (Wave 5 E2 / verification gate).
    ///
    /// Records the elapsed time between the hardware MIDI timestamp on a
    /// note-on event and the moment scoring ingests it on the main actor.
    /// Powers the p50 ≤ 12 ms / p99 ≤ 18 ms gate measured during the
    /// 3-minute Sukhkarta playback (E3 device pass).
    ///
    /// Internal so tests in the host bundle can read percentiles after
    /// driving simulated note-on events through the scoring tap.
    let latencyProbe = AppLatencyProbe()
    #endif

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
    /// Wave 4 D3: PlaybackCoordinator is now visualization-only — it no longer
    /// takes `soundFont` / `audioEngine` / `metronome` / `clock`. Those audio
    /// dependencies are kept on this initializer's signature as no-op
    /// placeholders so existing call sites compile; Wave 5 E1 will route them
    /// to `ArrangementPlayer` when that owner lands.
    ///
    /// All parameters default to production singletons when `nil` is passed.
    /// Tests inject mocks for deterministic behavior without audio hardware.
    ///
    /// - Parameters:
    ///   - soundFont: SoundFont player. TODO(E1): wire to ArrangementPlayer.
    ///   - audioEngine: Audio engine. TODO(E1): wire to ArrangementPlayer.
    ///   - metronome: Metronome player. TODO(E1): wire to ArrangementPlayer.
    ///   - clock: Drift-corrected clock. TODO(E1): wire to ArrangementPlayer.
    ///   - midiInput: MIDI input provider for USB keyboard detection. Defaults to `MIDIInputManager.shared`.
    init(
        soundFont: (any SoundFontPlaying)? = nil,
        audioEngine: (any AudioEngineProviding)? = nil,
        metronome: (any MetronomePlaying)? = nil,
        clock: (any ClockProviding)? = nil,
        midiInput: (any MIDIInputProviding)? = nil
    ) {
        // Audio-side params accepted for source compatibility — ignored until E1.
        _ = soundFont
        _ = audioEngine
        _ = metronome
        _ = clock
        let scoring = ScoringCoordinator()
        self.scoring = scoring
        let resolvedMIDI = midiInput ?? MIDIInputManager.shared
        self.playback = PlaybackCoordinator(
            scoring: scoring,
            analytics: nil  // nil-sentinel — uses AnalyticsManager.shared at call time
        )
        self.noteRouter = NoteRouter(
            midiInput: resolvedMIDI,
            scoring: scoring,
            playback: playback
        )
        setupAudioSessionCallbacks()
        setupMIDIScoringTap(midiInput: resolvedMIDI)
    }

    // MARK: - Wave 5 E1 — Audio session + MIDI scoring wiring

    /// Install pause/resume callbacks on `AudioSessionManager.shared`.
    ///
    /// On interruption-began (phone call, Siri) or route-loss
    /// (`oldDeviceUnavailable` — wired headphones unplugged), the play-
    /// along session pauses immediately. On interruption-ended where the
    /// system recommends resuming, playback resumes automatically.
    ///
    /// Callbacks are `@Sendable` and hop to `@MainActor` via `Task`
    /// because the `AudioSessionManager` notification observers fire on
    /// the main queue but the closures are typed as `@Sendable`.
    private func setupAudioSessionCallbacks() {
        AudioSessionManager.shared.onInterruptionBegan = { [weak self] in
            Task { @MainActor [weak self] in
                self?.pauseSession()
            }
        }
        AudioSessionManager.shared.onInterruptionEnded = { [weak self] shouldResume in
            Task { @MainActor [weak self] in
                guard shouldResume else { return }
                self?.resumeSession()
            }
        }
        AudioSessionManager.shared.onRouteChangeWithReason = { [weak self] reason in
            Task { @MainActor [weak self] in
                if reason == .oldDeviceUnavailable {
                    self?.pauseSession()
                }
            }
        }
    }

    /// Install the scoring tap on `NoteRouter.onMIDINoteOnObserved` and
    /// the Practice-mode chip subscriber on `MIDIInputManager`.
    ///
    /// `NoteRouter` already owns the live CoreMIDI callback chain (Phase-1
    /// highlight + Phase-2 MainActor scoring). Wave 5 E1 piggy-backs on
    /// that chain via `onMIDINoteOnObserved` so the scoring fan-out does
    /// not collide with NoteRouter's `onNoteEvent` registration.
    ///
    /// While `practiceModeChipVisible` is `true`, the scoring path drops
    /// the event (the sampler-trigger / audible echo path is in the
    /// CoreMIDI parser and is not affected — the user still hears
    /// themselves play on Bluetooth, only scoring is suppressed).
    ///
    /// Practice-mode chip — fires only when the underlying provider is the
    /// singleton `MIDIInputManager`. Test-double mocks for
    /// `MIDIInputProviding` skip this hook because they do not surface a
    /// `onPracticeModeRequired` API.
    private func setupMIDIScoringTap(midiInput: any MIDIInputProviding) {
        noteRouter.onMIDINoteOnObserved = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMIDINoteEventForScoring(event)
            }
        }
        if let manager = midiInput as? MIDIInputManager {
            manager.onPracticeModeRequired = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.practiceModeChipVisible = true
                }
            }
        }
    }

    /// Forward a MIDI note-on event to `ScoringAdapter`.
    ///
    /// Drops the event entirely when `practiceModeChipVisible` is `true`
    /// (Bluetooth source — timing untrustworthy). Drops note-off events
    /// (`velocity == 0`) which are not scoring inputs. Captures
    /// `HostTime.now()` at the call site as the event arrival time. Uses
    /// `arrangementPlayer.startHostTime` as the sequencer-start anchor
    /// when present; otherwise no-ops because there is no anchor to
    /// score against.
    func handleMIDINoteEventForScoring(_ event: MIDIInputEvent) {
        guard !practiceModeChipVisible else { return }
        guard event.isNoteOn else { return }
        guard let adapter = scoringAdapter else { return }
        guard let startHost = arrangementPlayer?.startHostTime else { return }
        let now = HostTime.now()
        #if DEBUG
        // Record end-to-end MIDI ingest latency: from the hardware
        // timestamp captured on the CoreMIDI callback thread to the
        // moment the scoring path runs on the main actor. Synthetic
        // events (test doubles) don't carry `midiTimestamp` so the
        // record is skipped — the probe stays empty until a real
        // MIDI note arrives.
        if let hardwareTicks = event.midiTimestamp {
            let eventHost = HostTime(rawTicks: hardwareTicks)
            let elapsedSec = now.seconds(since: eventHost)
            // Negative deltas can occur if the event was scheduled in
            // the future via MIDI sysex timing — clamp to zero.
            latencyProbe.record(latencyMs: max(0.0, elapsedSec * 1000.0))
        }
        #endif
        _ = adapter.ingest(
            midiNote: event.noteNumber,
            velocity: event.velocity,
            hostTime: now,
            sequencerStartHostTime: startHost,
            currentTempoScale: Float(arrangementTempoScale)
        )
    }

    /// Wire an `ArrangementPlayer` over a `PartSplit` (Wave 5 E1).
    ///
    /// Loads the accompaniment SMF into the underlying graph, instantiates
    /// a fresh `ScoringAdapter` against the learner score, applies the
    /// current tempo / loop / practice-mode / hearOtherHand state, and
    /// updates `totalMeasures` + `hasMultipleStaves` for the toolbar.
    ///
    /// - Parameters:
    ///   - split: The learner / accompaniment split to load.
    ///   - graph: Sampler graph backing the player. Production callers
    ///     pass a `MultiTrackSamplerGraph`; tests inject a mock conforming
    ///     to `MultiTrackSamplerGraphProtocol`.
    /// - Throws: Any `PipelineError` from the underlying `loadMIDI` call.
    func loadArrangement(
        split: PartSplit,
        graph: any MultiTrackSamplerGraphProtocol
    ) async throws {
        let player = ArrangementPlayer(graph: graph)
        try await player.load(split)
        player.practiceMode = practiceMode
        player.hearOtherHand = hearOtherHand
        player.setTempoScale(Float(arrangementTempoScale))
        player.setLoop(loopRegion)

        arrangementPlayer = player
        currentSplit = split
        scoringAdapter = ScoringAdapter(
            score: split.learner,
            tonicSaPitch: tonicSaPitch
        )
        totalMeasures = max(1, split.learner.notes.last?.measureNumber ?? 1)
        hasMultipleStaves = split.learnerStaves.count > 1
        let noteCount = split.learner.notes.count
        let staveCount = split.learnerStaves.count
        let totalM = totalMeasures
        Self.logger.info(
            "loadArrangement: notes=\(noteCount) measures=\(totalM) staves=\(staveCount)"
        )
    }

    /// Set the tonic Sa MIDI pitch and refresh the active scoring
    /// adapter. Called by tanpura-driven Sa changes.
    ///
    /// - Parameter midi: MIDI note number that corresponds to Sa
    ///   (`60` = C4). Out-of-range values are clamped to `0...127`.
    func setTonicSaPitch(_ midi: UInt8) {
        tonicSaPitch = min(127, max(0, midi))
        if let split = currentSplit {
            scoringAdapter = ScoringAdapter(
                score: split.learner,
                tonicSaPitch: tonicSaPitch
            )
        }
    }

    /// Persist a `PlayAlongSession` row from the active scoring summary
    /// (Wave 5 E1 / spec §5.1).
    ///
    /// No-op when no `modelContext` is set, no `scoringAdapter` is
    /// present, or no `song` is loaded. Saves explicitly per CLAUDE.md
    /// "critical writes" rule and logs any persistence error via
    /// `os.Logger`.
    func persistPlayAlongSessionIfPossible(startedAt: Date, endedAt: Date) {
        guard let context = playback.modelContext,
            let adapter = scoringAdapter,
            let song = playback.song
        else { return }

        let summary = adapter.summary()
        let session = PlayAlongSession(
            songID: song.id,
            startedAt: startedAt,
            notesAttempted: summary.notesAttempted,
            notesCorrect: summary.notesCorrect,
            notesMissed: summary.notesMissed,
            notesExtra: summary.notesExtra,
            timingAccuracyPercent: summary.timingAccuracyPercent,
            notesCorrectPercent: summary.notesCorrectPercent
        )
        session.endedAt = endedAt
        session.compositeScore = summary.composite.accuracy
        session.tempoScale = arrangementTempoScale
        session.practiceMode = practiceMode.rawValue

        context.insert(session)
        do {
            try context.save()
            Self.logger.info("PlayAlongSession persisted (E1)")
        } catch {
            Self.logger.error(
                "PlayAlongSession save failed: \(error.localizedDescription, privacy: .public)"
            )
        }
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

    /// Wall-clock timestamp captured on the most recent `startSession()`.
    /// Threaded into the persisted `PlayAlongSession.startedAt` field on
    /// `stopAndComplete()`.
    private var sessionStartedAt: Date?

    /// Start the play-along session from the beginning.
    ///
    /// Delegates engine start, metronome, scheduling, and analytics to
    /// `PlaybackCoordinator`. Re-starts `NoteRouter` input detection to handle
    /// the case where it was stopped after a previous cleanup. Wave 5 E1:
    /// also calls `ArrangementPlayer.start(countInBars:)` when an
    /// arrangement is wired.
    ///
    /// Guards: only starts from `.idle` or `.stopped` with non-empty events.
    func startSession() async {
        MultiChannelLog.shared.log(.info, ">>> PlayAlongViewModel.startSession")
        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.startSession: about to await startScheduling")
        sessionStartedAt = Date()
        await playback.startScheduling()
        MultiChannelLog.shared.log(.info, "... PlayAlongViewModel.startSession: startScheduling returned")
        arrangementPlayer?.start(countInBars: 1)
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
        arrangementPlayer?.pause()
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
        arrangementPlayer?.resume()
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
        let started = sessionStartedAt ?? Date()
        playback.stopAndComplete()
        arrangementPlayer?.stop()
        persistPlayAlongSessionIfPossible(startedAt: started, endedAt: Date())
        sessionStartedAt = nil
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
        arrangementPlayer?.stop()
        arrangementPlayer = nil
        scoringAdapter = nil
        currentSplit = nil
        // Clear AudioSessionManager callbacks to break the retain cycle
        // back into this VM (callbacks captured `[weak self]` so this is
        // belt-and-braces — but explicit teardown matches Apple's
        // documented pattern for one-shot scene-host VMs).
        AudioSessionManager.shared.onInterruptionBegan = nil
        AudioSessionManager.shared.onInterruptionEnded = nil
        AudioSessionManager.shared.onRouteChangeWithReason = nil
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
