// swiftlint:disable type_body_length
import SVAudio
import SVCore
import SVLearning
import SwiftData
import SwiftUI
import os.log

/// Main container view for the song play-along experience.
///
/// Composes all play-along sub-views into a unified interface:
/// - **Toolbar** at top with transport controls (play/pause/stop, tempo, modes).
/// - **Content area** switches between falling notes and scrolling sheet views.
/// - **Piano keyboard** at bottom for touch input, with key positions reported
///   upward via `KeyPositionPreference` for falling-note alignment.
/// - **Scoring HUD** floating over the content area.
/// - **Results overlay** presented as a full-screen cover when the session completes.
///
/// ## State Management
/// All mutable state lives in `PlayAlongViewModel`, which is created once
/// per navigation push and disposed on disappear via `cleanup()`.
///
/// ## Keyboard–Note Alignment
/// `InteractivePianoView` reports its key center-X positions through
/// `KeyPositionPreference`. These positions are collected via
/// `onPreferenceChange` and passed to `FallingNotesView` so falling notes
/// align precisely with the corresponding keys.
struct SongPlayAlongView: View {
    // MARK: - Properties

    /// The song to play along with.
    let song: Song

    /// View model received from `PlayAlongSceneHost`; do not own here.
    ///
    /// `@Bindable` gives SwiftUI two-way access to published properties without
    /// taking ownership. Ownership lives in `PlayAlongSceneHost` so the VM
    /// survives rotation and size-class changes without restarting the audio engine.
    @Bindable
    var viewModel: PlayAlongViewModel

    /// Owns tanpura drone state and debounces retune against the engine.
    /// `internal` so helpers in `SongPlayAlongView+Tanpura.swift` can read it.
    @State
    var tanpura = TanpuraController()

    /// Whether the tanpura settings sheet is presented.
    /// `internal` so helpers in `SongPlayAlongView+Tanpura.swift` can set it.
    @State
    var showTanpuraSheet = false

    /// Pending persistence write for `preferredSaHz`. Canceled on rapid changes.
    @State
    private var persistDebounceTask: Task<Void, Never>?

    /// Set to true after the initial `tanpura.seed(...)` call in `.task`.
    /// Gates the `effectiveSaHz` persistence observer so the initial seed
    /// doesn't spuriously write a SongProgress row on every song open.
    @State
    private var didInitialSeed = false

    /// Set to true by `resetPreferredSaHz()` so the next `effectiveSaHz`
    /// change (which comes from the internal re-seed to the song default,
    /// not from the user) is ignored by the persistence observer. Cleared
    /// automatically by the observer itself.
    /// `internal` so `resetPreferredSaHz()` in the +Tanpura extension can set it.
    @State
    var suppressNextPersistenceTick = false

    /// Cached "SongProgress.preferredSaHz is non-nil" flag, updated at
    /// task-time and on every persist/reset. Replaces a per-render
    /// SwiftData fetch that previously fired on every sheet open.
    /// `internal` so the +Tanpura extension can read and flip it.
    @State
    var hasStoredOverride: Bool = false

    /// Whether the results overlay is presented.
    @State
    private var showResults = false

    /// Whether the theme picker sheet is presented (from the toolbar's Mode button).
    @State
    private var showAppearanceSheet = false

    /// Whether the first-run microphone pre-prompt sheet should be shown.
    ///
    /// Initialised from `MicPermissionPrePrompt.shouldShow`, which reads the
    /// `hasSeenMicPermissionPrePrompt` flag from `UserDefaults`. The sheet
    /// displays in parallel with the existing `.task` that calls
    /// `viewModel.loadSong(song)`; `loadSong` itself issues the system
    /// permission request — this pre-prompt merely explains why first.
    @State
    private var showMicPrePrompt: Bool = MicPermissionPrePrompt.shouldShow

    /// Whether the correctness flash overlay is visible (brief green/red flash).
    @State
    var showCorrectnessBanner = false

    /// Color of the current correctness flash (green for correct, red for wrong).
    @State
    var correctnessBannerColor: Color = .green

    // MARK: - AppStorage (persisted preferences)

    @AppStorage("playAlongWaitMode")
    private var storedWaitMode: Bool = false

    // MARK: - Environment

    @Environment(AppThemeManager.self)
    var themeManager  // internal so the +Subviews extension (separate file) can read it
    // internal so the +Tanpura extension (separate file) can fetch/save SongProgress
    @Environment(\.modelContext)
    var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.accessibilityReduceMotion)
    var reduceMotion
    @Environment(\.verticalSizeClass)
    private var verticalSizeClass
    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    // MARK: - Layout helpers

    /// Returns `true` when the window should use a side-by-side (landscape)
    /// layout: iPhone landscape (vertical-compact) or iPad / Mac regular width.
    /// Stacks vertically for iPhone portrait and iPad Slide Over.
    private var shouldUseLandscapeLayout: Bool {
        verticalSizeClass == .compact || horizontalSizeClass == .regular
    }

    // MARK: - Transport actions

    /// Actions published to `TransportCommands` via `.focusedSceneValue`.
    ///
    /// The closures capture `self` by value (View is a struct) which is safe —
    /// each SwiftUI render produces a fresh struct; the closures are short-lived.
    /// Seek uses `playbackDuration` to convert a 5-second offset into the
    /// normalised progress fraction that `seek(to:)` expects.
    private var transportActions: TransportActions {
        TransportActions(
            playPause: { handlePlayPause() },
            seekBackward: {
                let duration = viewModel.playbackDuration
                guard duration > 0 else { return }
                let newProgress = max(0, viewModel.playbackProgress - 5 / duration)
                viewModel.seek(to: newProgress)
            },
            seekForward: {
                let duration = viewModel.playbackDuration
                guard duration > 0 else { return }
                let newProgress = min(1, viewModel.playbackProgress + 5 / duration)
                viewModel.seek(to: newProgress)
            },
            stop: { handleStop() }
        )
    }

    // MARK: - Body

    var body: some View {
        let _ = MultiChannelLog.shared.log(.info, "BODY-EVAL SongPlayAlongView body recomputed (song=\(song.title))")
        // PlayTab-style linear layout — simple VStack so each child owns its
        // own observation scope. Heavy ticking subviews (toolbar, content,
        // piano) read viewModel directly; the parent body only re-renders
        // on a small set of properties (chromeVisibility, playbackState).
        VStack(spacing: 0) {
            // 1. Top toolbar — full width.
            playAlongToolbarSection

            // 2. Content area (notation / falling notes / staff) — flexible.
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 3. Bottom transport bar with big play button.
            bottomTransportBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            // 4. Piano keyboard — fixed height like Play tab.
            keyboardContent
                .frame(height: 280)
        }
        .background(
            LinearGradient(
                colors: themeManager.resolved.backgroundGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .overlay(alignment: .topLeading) { tanpuraRagaPill.padding(16) }
        .overlay(alignment: .topTrailing) {
            micSourcePill.padding(16).allowsHitTesting(false)
        }
        .overlay { FirstTimeCoachMark() }
        .onAppear {
            MultiChannelLog.shared.log(.info, "ZSTACK SongPlayAlongView onAppear fired")
        }
        .overlay(alignment: .top) {
            // Correctness flash banner — shows briefly on each note attempt
            if showCorrectnessBanner {
                correctnessBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                    .animation(reduceMotion ? nil : .spring(response: 0.3), value: showCorrectnessBanner)
            }
        }
        .overlay(alignment: .center) {
            // Stuck hint overlay — shown when user hasn't played in a while
            if viewModel.isStuck, let expectedNote = viewModel.expectedMidiNote {
                stuckHintOverlay(expectedMidiNote: expectedNote)
                    .transition(.scale.combined(with: .opacity))
                    .animation(reduceMotion ? nil : .spring(response: 0.4), value: viewModel.isStuck)
            }
        }
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: viewModel.scoring.notesHit)
        .sheet(isPresented: $showMicPrePrompt) {
            MicPermissionPrePrompt(onContinue: {})
        }
        .task {
            MultiChannelLog.shared.log(.info, ">>> SongPlayAlongView.task ENTERED song=\(song.title) cancelled=\(Task.isCancelled)")
            defer {
                MultiChannelLog.shared.log(.info, "<<< SongPlayAlongView.task EXITING song=\(song.title) cancelled=\(Task.isCancelled)")
            }
            viewModel.modelContext = modelContext
            // Derive view mode and notation from the active theme preset
            viewModel.viewMode = themeManager.currentPreset.viewMode
            viewModel.notationMode = themeManager.currentPreset.notationMode
            viewModel.chrome.updateTheme(themeManager)
            viewModel.isWaitModeEnabled = storedWaitMode
            let slug = song.slugId
            let progress = try? modelContext.fetch(
                FetchDescriptor<SongProgress>(
                    predicate: #Predicate { $0.songId == slug }
                )
            ).first
            tanpura.seed(
                preferredSaHz: progress?.preferredSaHz,
                songDefaultHz: song.defaultSaFrequencyHz
            )
            tanpura.setSoundEnabled(viewModel.isSoundEnabled)
            hasStoredOverride = (progress?.preferredSaHz != nil)
            didInitialSeed = true
            MultiChannelLog.shared.log(.info, "... SongPlayAlongView.task: about to await viewModel.loadSong")
            await viewModel.loadSong(song)
        }
        .onChange(of: themeManager.currentPreset) { _, newPreset in
            // Live-switch when user changes theme via quick-switch sheet
            viewModel.viewMode = newPreset.viewMode
            viewModel.notationMode = newPreset.notationMode
            viewModel.chrome.updateTheme(themeManager)
            AnalyticsManager.shared.track(
                .playAlongViewModeChanged,
                properties: ["view_mode": newPreset.viewMode.rawValue, "song_title": song.title]
            )
            AnalyticsManager.shared.track(
                .playAlongNotationToggled,
                properties: ["notation_mode": newPreset.notationMode.rawValue, "song_title": song.title]
            )
            AnalyticsManager.shared.track(
                .themeChanged,
                properties: [
                    "preset": newPreset.rawValue,
                    "song_title": song.title,
                    "source": "play_along_mode_button",
                ]
            )
        }
        .onDisappear {
            persistDebounceTask?.cancel()
            tanpura.stop()
            viewModel.cleanup()
        }
        .onChange(of: viewModel.playbackState) { _, newState in
            handlePlaybackStateChange(newState)
        }
        .onChange(of: viewModel.guidedPlayState) { _, newState in
            handleGuidedPlayStateChange(newState)
        }
        .onChange(of: viewModel.currentNoteIndex) { _, newIndex in
            // AUD-VO: Announce current note to VoiceOver users.
            // Only announces when VoiceOver is running to avoid unnecessary overhead.
            guard UIAccessibility.isVoiceOverRunning,
                let index = newIndex,
                index < viewModel.noteEvents.count
            else { return }
            let event = viewModel.noteEvents[index]
            // Post queued announcement so it doesn't cut off prior speech.
            UIAccessibility.post(
                notification: .announcement,
                argument: NSAttributedString(
                    string: event.swarName,
                    attributes: [.accessibilitySpeechQueueAnnouncement: true]
                )
            )
        }
        .fullScreenCover(isPresented: $showResults) {
            PlayAlongResultsOverlay(
                songTitle: song.title,
                accuracy: viewModel.accuracy,
                notesCorrectPercent: viewModel.notesCorrectPercent,
                timingAccuracyPercent: viewModel.timingAccuracyPercent,
                notesHit: viewModel.notesHit,
                totalNotes: viewModel.noteEvents.count,
                streak: viewModel.longestStreak,
                starRating: viewModel.starRating,
                xpEarned: viewModel.xpEarned,
                onReplay: {
                    showResults = false
                    AnalyticsManager.shared.track(
                        .playAlongRestarted,
                        properties: ["song_title": song.title]
                    )
                    Task {
                        await viewModel.startSession()
                    }
                },
                onDone: {
                    showResults = false
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showTanpuraSheet) {
            tanpuraSettingsSheetContent
        }
        .sheet(isPresented: $viewModel.showLoopBuilder) {
            LoopBuilderView(
                totalMeasures: viewModel.totalMeasures,
                initialStart: viewModel.loopRegion?.startMeasure ?? 1,
                initialEnd: viewModel.loopRegion?.endMeasure
            ) { region in
                viewModel.loopRegion = region
            }
        }
        .sheet(isPresented: $showAppearanceSheet) {
            NavigationStack {
                ThemeCarouselPicker()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: tanpura.effectiveSaHz) { _, newHz in
            guard didInitialSeed else { return }
            if suppressNextPersistenceTick {
                suppressNextPersistenceTick = false
                return
            }
            persistDebounceTask?.cancel()
            persistDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                persistPreferredSaHz(newHz)
                AnalyticsManager.shared.track(
                    .tanpuraSaChanged,
                    properties: [
                        "grid_hz": tanpura.saGridHz,
                        "cents_offset": tanpura.saCentsOffset,
                        "effective_hz": newHz,
                        "song_title": song.title,
                    ]
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Play along with \(song.title)")
        .focusedSceneValue(\.transportActions, transportActions)
    }

    // MARK: - Layout

    /// Top toolbar wrapper for the new linear layout. Reads viewModel
    /// internally so parent body doesn't tick on toolbar state.
    @ViewBuilder
    private var playAlongToolbarSection: some View {
        PlayAlongToolbar(
            viewModel: viewModel,
            playbackState: viewModel.playbackState,
            tempoScale: viewModel.tempoScale,
            isWaitModeEnabled: viewModel.isWaitModeEnabled,
            isSoundEnabled: viewModel.isSoundEnabled,
            isMIDIConnected: viewModel.isMIDIConnected,
            midiDeviceName: viewModel.midiDeviceName,
            baseBPM: song.tempo,
            songTitle: song.title,
            songSubtitle: song.artist.isEmpty ? "Aaroha" : song.artist,
            playbackProgress: viewModel.playbackProgress,
            playbackDuration: viewModel.playbackDuration,
            onPlayPause: handlePlayPause,
            onStop: handleStop,
            onTempoChange: { viewModel.tempoScale = $0 },
            onWaitModeToggle: {
                viewModel.toggleWaitMode()
                storedWaitMode = viewModel.isWaitModeEnabled
            },
            onSoundToggle: {
                viewModel.isSoundEnabled.toggle()
                tanpura.setSoundEnabled(viewModel.isSoundEnabled)
            },
            onTanpuraToggle: { tanpura.toggleEnabled() },
            onModeTapped: { showAppearanceSheet = true },
            onSeek: { viewModel.seek(to: $0) }
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 60)  // leave room for tanpura/mic pills overlay
    }

    /// Bottom transport bar with a big, obvious play button.
    /// The play button always responds to taps — independent of body re-eval rate.
    @ViewBuilder
    private var bottomTransportBar: some View {
        let isPlaying = viewModel.playbackState == .playing
        HStack(spacing: 24) {
            Button { handleStop() } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 24))
                    .frame(width: 56, height: 56)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop")

            Button { handlePlayPause() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32))
                    .frame(width: 72, height: 72)
                    .background(themeManager.resolved.accentColor, in: Circle())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
        }
        .frame(maxWidth: .infinity)
    }

    /// Notation, toolbar, scoring HUD, and pitch feedback — everything above (or
    /// beside) the keyboard. Extracted so `layoutContent` can place it in either
    /// a `VStack` or an `HStack` depending on `shouldUseLandscapeLayout`.
    @ViewBuilder
    private var notationAndChrome: some View {
        VStack(spacing: 0) {
            if viewModel.chromeVisibility == .summoned {
                // Transport toolbar — theme-driven, only visible when chrome is summoned.
                PlayAlongToolbar(
                    viewModel: viewModel,
                    playbackState: viewModel.playbackState,
                    tempoScale: viewModel.tempoScale,
                    isWaitModeEnabled: viewModel.isWaitModeEnabled,
                    isSoundEnabled: viewModel.isSoundEnabled,
                    isMIDIConnected: viewModel.isMIDIConnected,
                    midiDeviceName: viewModel.midiDeviceName,
                    baseBPM: song.tempo,
                    songTitle: song.title,
                    songSubtitle: song.artist.isEmpty ? "Aaroha" : song.artist,
                    playbackProgress: viewModel.playbackProgress,
                    playbackDuration: viewModel.playbackDuration,
                    onPlayPause: handlePlayPause,
                    onStop: handleStop,
                    onTempoChange: {
                        viewModel.tempoScale = $0
                        AnalyticsManager.shared.track(
                            .playAlongTempoChanged,
                            properties: ["tempo_scale": $0, "song_title": song.title]
                        )
                    },
                    onWaitModeToggle: {
                        viewModel.toggleWaitMode()
                        storedWaitMode = viewModel.isWaitModeEnabled
                    },
                    onSoundToggle: {
                        viewModel.isSoundEnabled.toggle()
                        tanpura.setSoundEnabled(viewModel.isSoundEnabled)
                        AnalyticsManager.shared.track(
                            .playAlongSoundToggled,
                            properties: ["enabled": viewModel.isSoundEnabled, "song_title": song.title]
                        )
                    },
                    onTanpuraToggle: {
                        tanpura.toggleEnabled()
                        AnalyticsManager.shared.track(
                            .tanpuraToggled,
                            properties: [
                                "enabled": tanpura.isTanpuraEnabled,
                                "song_title": song.title,
                                "source": "toolbar",
                            ]
                        )
                    },
                    onModeTapped: { showAppearanceSheet = true },
                    onSeek: { viewModel.seek(to: $0) }
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity)
                )
            }

            // Main content area — theme-aware renderer dispatch.
            //
            // Gesture overlay summons/manages chrome. Gestures are attached
            // HERE (not on the piano keyboard) so piano-key taps still route
            // to `InteractivePianoView.onNoteOn`/`onNoteOff` without being
            // swallowed. `.contentShape(Rectangle())` ensures the full area
            // is hittable even when the underlying view renders `Color.clear`
            // (e.g., `.hide` notation mode).
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Tap = "I want controls" → summon chrome.
                    viewModel.summonChrome()
                }
                .gesture(
                    // Swipe down (from top edge or anywhere on the content):
                    // downward translation dominates → summon chrome.
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            if value.translation.height > 30
                                && abs(value.translation.width) < 50
                            {
                                viewModel.summonChrome()
                            }
                        }
                )
                .onLongPressGesture(minimumDuration: 0.5) {
                    // TODO(Task 2.11+): open a seek scrubber on long-press
                    // instead of summoning chrome. For now, treat long-press
                    // on notation as an intent to see controls.
                    viewModel.summonChrome()
                }
            // TODO(Task 2.11+): implement native two-finger tap for
            // wait-mode toggle via UIKit bridging (SwiftUI's TapGesture
            // doesn't distinguish finger count on iOS).

            if shouldShowLyricStrip && !viewModel.noteEvents.isEmpty {
                LyricsStrip(
                    words: sargamLyricWords,
                    devanagariLine: nil,
                    currentTime: viewModel.currentTime,
                    backgroundColor: viewModel.karaokeBackgroundColor
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }

            // Scoring HUD overlay — visible during playback OR when notes have been scored in guided mode
            CompactScoringHUD(
                accuracy: viewModel.accuracy,
                streak: viewModel.streak,
                notesHit: viewModel.notesHit,
                totalNotes: viewModel.noteEvents.count,
                isVisible: viewModel.playbackState == .playing
                    || viewModel.playbackState == .paused
                    || (viewModel.playbackState == .idle && viewModel.notesHit > 0)
            )

            // Pitch proximity feedback (shown when a note is detected from mic)
            if let pitch = viewModel.currentPitch {
                pitchFeedbackBar(pitch: pitch)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
    }

    /// The piano keyboard, with key-position preference reporting.
    ///
    /// `highlightState` is passed directly so CADisplayLink ticks (60–120 Hz)
    /// that update MIDI key highlights only re-render `InteractivePianoView` —
    /// NOT the entire `SongPlayAlongView` hierarchy. This eliminates the
    /// `@MainActor` saturation that caused 300–530ms MIDI scoring lag.
    @ViewBuilder
    private var keyboardContent: some View {
        InteractivePianoView(
            activeMidiNotes: viewModel.effectiveMidiNotes,
            highlightState: viewModel.highlightState,
            activeCentsOffset: viewModel.currentPitch?.centsOffset ?? 0,
            expectedMidiNote: viewModel.expectedMidiNote,
            onNoteOn: { midiNote in
                viewModel.handleKeyboardNoteOn(midiNote: midiNote)
            },
            onNoteOff: { midiNote in
                viewModel.handleKeyboardNoteOff(midiNote: midiNote)
            },
            notationMode: viewModel.notationMode,
            manageSoundFont: false,
            // Two-hand highlight colors resolved once upstream from the
            // active theme (see `.task` / `.onChange(of: themeManager.currentPreset)`
            // above). Passed as `let` so the CADisplayLink-driven
            // `highlightState` mutations only re-render this view —
            // not `SongPlayAlongView.body`. InteractivePianoView reads
            // the per-note RH/LH/chord sets from `highlightState`
            // internally, preserving the latency contract.
            rhColor: viewModel.rhColor,
            lhColor: viewModel.lhColor,
            chordColor: viewModel.chordColor
        )
    }

    /// Composes `notationAndChrome` + `keyboardContent` into the active
    /// layout variant: side-by-side in landscape / regular-width windows,
    /// stacked vertically otherwise.
    @ViewBuilder
    private var layoutContent: some View {
        if shouldUseLandscapeLayout {
            HStack(alignment: .top, spacing: 0) {
                notationAndChrome
                    .frame(maxWidth: .infinity)
                keyboardContent
                    .frame(maxWidth: 400)
            }
        } else {
            VStack(spacing: 0) {
                notationAndChrome
                keyboardContent
            }
        }
    }

    // MARK: - Lyric Strip Helpers

    /// Lyric-strip words derived from the current song's note events.
    ///
    /// Each note becomes a syllable card showing its Sargam name, timed
    /// to the note's start + duration window so `LyricsStrip`'s karaoke
    /// highlight follows the playback clock.
    private var sargamLyricWords: [LyricsStrip.LyricWord] {
        viewModel.noteEvents.map { event in
            LyricsStrip.LyricWord(
                text: event.swarName,
                startTime: event.timestamp,
                endTime: event.timestamp + event.duration
            )
        }
    }

    /// True when the active theme's primary notation is Sargam, which
    /// is also when showing a dedicated Sargam lyric strip adds value.
    /// Western/Pop/Night themes already render note labels on the staff.
    private var shouldShowLyricStrip: Bool {
        switch themeManager.currentPreset {
        case .sargamGlass, .sargamGlassBars, .neonRhythm:
            return true
        default:
            return false
        }
    }

    // MARK: - Content Area

    /// The main visual content area — dispatches to the right notation renderer
    /// based on the active theme preset. Colors arrive to renderers as `let`
    /// parameters (via `viewModel`) so none of them read the `AppThemeManager`
    /// environment — preserving the audio-latency contract.
    @ViewBuilder
    private var contentArea: some View {
        if viewModel.playbackState == .loading {
            ProgressView("Loading song…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch themeManager.currentPreset {
            // Sargam Glass · Bars (v2) — dual-row Sargam with horizontal bars
            case .sargamGlassBars:
                SargamDualRowView(
                    noteEvents: viewModel.noteEvents,
                    currentTime: viewModel.currentTime,
                    rhColor: viewModel.rhColor,
                    lhColor: viewModel.lhColor,
                    chordColor: viewModel.chordColor,
                    cardBackgroundColor: viewModel.cardBackgroundColor
                )
                .accessibilityLabel("Sargam dual-row notation")

            // Bars-style grand staff with horizontal colored bars (Yousician-like).
            // Used by Immersive Bars (#6), Midnight Bars (#7), Pop Era (#9).
            case .immersiveBars, .midnightBars, .popEra:
                BarsOnStaffView(
                    noteEvents: viewModel.noteEvents,
                    currentTime: viewModel.currentTime,
                    rhColor: viewModel.rhColor,
                    lhColor: viewModel.lhColor,
                    chordColor: viewModel.chordColor,
                    notationLineColor: viewModel.notationLineColor,
                    notationSecondaryColor: viewModel.notationSecondaryColor,
                    showTrebleClef: true,
                    showBassClef: true
                )
                .accessibilityLabel("Horizontal-bar grand-staff notation")

            // Drop variants — classical scrolling sheet with round notes.
            // Per spec §5.1:
            //   #1 Immersive · Drop  → grand staff, round notes (sheetMusic)
            //   #3 Sargam Glass · Drop → Devanagari ribbon + round mini-staff (sargamPlusSheet)
            //   #4 Midnight · Drop  → OLED grand staff, amber round notes (sheetMusic)
            case .immersive, .midnight, .sargamGlass:
                ScrollingSheetView(
                    song: song,
                    noteEvents: viewModel.noteEvents,
                    currentTime: viewModel.currentTime,
                    currentNoteIndex: viewModel.currentNoteIndex,
                    notationMode: viewModel.notationMode,
                    currentPitch: viewModel.currentPitch,
                    highlightState: viewModel.highlightState
                )
                .accessibilityLabel("Scrolling sheet notation, grand staff with round notes")

            // Falling-notes lanes (vertical drop) — Synthesia/Neon-style.
            case .neonRhythm, .synthesia:
                SplitLaneView(
                    noteEvents: viewModel.noteEvents,
                    currentTime: viewModel.currentTime,
                    rhColor: viewModel.rhColor,
                    lhColor: viewModel.lhColor,
                    chordColor: viewModel.chordColor,
                    tempoBPM: Double(song.tempo)
                )
                .accessibilityLabel("Vertical split-lane falling notes")
            }
        }
    }

    // MARK: - Persistent chrome pills

    /// Top-right pill showing the active input source (mic vs MIDI).
    @ViewBuilder
    private var micSourcePill: some View {
        let source: MicSourcePill.Source =
            viewModel.isMIDIConnected
            ? .midi(deviceName: viewModel.midiDeviceName)
            : .mic
        MicSourcePill(
            source: source,
            backgroundColor: viewModel.cardBackgroundColor,
            foregroundColor: themeManager.resolved.primaryTextColor
        )
    }

    // MARK: - Actions

    /// Handle the play/pause button tap based on current playback state.
    private func handlePlayPause() {
        let state = viewModel.playbackState
        MultiChannelLog.shared.log(.info, "==> handlePlayPause TAP state=\(state) arrangementWired=\(viewModel.arrangementPlayer != nil)")
        switch state {
        case .idle, .stopped:
            Task {
                MultiChannelLog.shared.log(.info, "... handlePlayPause: calling startSession")
                await viewModel.startSession()
                MultiChannelLog.shared.log(.info, "... handlePlayPause: startSession returned, newState=\(viewModel.playbackState)")
            }
        case .playing:
            viewModel.pauseSession()
        case .paused:
            viewModel.resumeSession()
        case .loading, .error:
            MultiChannelLog.shared.log(.warning, "... handlePlayPause: ignored — state=\(state)")
        }
    }

    /// Handle the stop button tap.
    ///
    /// If notes have been scored, completes the session to show results.
    /// Otherwise just cleans up and resets to idle.
    private func handleStop() {
        if viewModel.notesHit > 0 {
            viewModel.stopAndComplete()
        } else {
            viewModel.cleanup()
        }
    }

    /// Respond to playback state transitions.
    ///
    /// Shows the results overlay when the session completes (transitions to `.stopped`).
    /// Keyboard highlighting is driven directly by `viewModel.effectiveMidiNotes` —
    /// no explicit state update needed here.
    private func handlePlaybackStateChange(_ newState: PlaybackState) {
        switch newState {
        case .stopped:
            // Show results when session completes naturally
            if viewModel.notesHit > 0 {
                showResults = true
            }
        default:
            break
        }
    }

}

// MARK: - Preview

#Preview("Play Along — Idle") {
    NavigationStack {
        PlayAlongSceneHost(song: Song(title: "Raag Yaman", difficulty: 2, tempo: 120))
    }
    .environment(AppThemeManager())
}

#Preview("Play Along — With Song") {
    NavigationStack {
        PlayAlongSceneHost(
            song: {
                let song = Song(title: "Twinkle Twinkle", difficulty: 1, tempo: 100)
                return song
            }()
        )
    }
    .environment(AppThemeManager())
}
