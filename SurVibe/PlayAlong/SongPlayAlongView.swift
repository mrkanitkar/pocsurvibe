import SVAudio
import SVCore
import SVLearning
import SwiftUI

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

    /// View model managing playback, scoring, and session lifecycle.
    @State private var viewModel = PlayAlongViewModel()

    /// Piano key positions collected via preference key for note alignment.
    @State private var keyPositions: [KeyPosition] = []

    /// Whether the results overlay is presented.
    @State private var showResults = false

    /// Whether the correctness flash overlay is visible (brief green/red flash).
    @State private var showCorrectnessBanner = false

    /// Color of the current correctness flash (green for correct, red for wrong).
    @State private var correctnessBannerColor: Color = .green

    // MARK: - AppStorage (persisted preferences)

    @AppStorage("playAlongViewMode") private var storedViewMode: String = PlayAlongViewMode.fallingNotes.rawValue
    @AppStorage("playAlongNotationMode") private var storedNotationMode: String = NotationDisplayMode.sargam.rawValue
    @AppStorage("playAlongWaitMode") private var storedWaitMode: Bool = false

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Transport toolbar
            PlayAlongToolbar(
                playbackState: viewModel.playbackState,
                tempoScale: viewModel.tempoScale,
                isWaitModeEnabled: viewModel.isWaitModeEnabled,
                isSoundEnabled: viewModel.isSoundEnabled,
                viewMode: viewModel.viewMode,
                notationMode: viewModel.notationMode,
                isMIDIConnected: viewModel.isMIDIConnected,
                midiDeviceName: viewModel.midiDeviceName,
                latencyPreset: viewModel.latencyPreset,
                baseBPM: song.tempo,
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
                    AnalyticsManager.shared.track(
                        .playAlongSoundToggled,
                        properties: ["enabled": viewModel.isSoundEnabled, "song_title": song.title]
                    )
                },
                onViewModeChange: {
                    viewModel.viewMode = $0
                    storedViewMode = $0.rawValue
                    AnalyticsManager.shared.track(
                        .playAlongViewModeChanged,
                        properties: ["view_mode": $0.rawValue, "song_title": song.title]
                    )
                },
                onNotationModeChange: {
                    viewModel.notationMode = $0
                    storedNotationMode = $0.rawValue
                    AnalyticsManager.shared.track(
                        .playAlongNotationToggled,
                        properties: ["notation_mode": $0.rawValue, "song_title": song.title]
                    )
                },
                onLatencyPresetChange: { viewModel.latencyPreset = $0 }
            )

            // Main content area — switches between visual modes
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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

            // Piano keyboard at the bottom.
            // highlightState is passed directly so CADisplayLink ticks (60–120 Hz)
            // that update MIDI key highlights only re-render InteractivePianoView —
            // NOT the entire SongPlayAlongView hierarchy. This eliminates the
            // @MainActor saturation that caused 300–530ms MIDI scoring lag.
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
                manageSoundFont: false
            )
            .onPreferenceChange(KeyPositionPreference.self) { positions in
                keyPositions = positions
            }
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
        .background(Color(.systemBackground))
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    viewModel.cleanup()
                    dismiss()
                }
                .accessibilityLabel("Close")
                .accessibilityHint("End play-along and return to the song library")
            }
        }
        .task {
            viewModel.modelContext = modelContext
            viewModel.viewMode = PlayAlongViewMode(rawValue: storedViewMode) ?? .fallingNotes
            viewModel.notationMode = NotationDisplayMode(rawValue: storedNotationMode) ?? .sargam
            viewModel.isWaitModeEnabled = storedWaitMode
            await viewModel.loadSong(song)
        }
        .onDisappear {
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
                  index < viewModel.noteEvents.count else { return }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Play along with \(song.title)")
    }

    // MARK: - Content Area

    /// Match state of the note at the current playback index, for notation overlays.
    ///
    /// Returns the `FallingNotesLayoutEngine.NoteState` for the note currently at
    /// `viewModel.currentNoteIndex`, enabling the scrolling-sheet renderers to show
    /// a green border (`.correct`) or red border (`.wrong`) on the active note.
    private var currentNoteMatchState: FallingNotesLayoutEngine.NoteState? {
        guard let index = viewModel.currentNoteIndex,
              index < viewModel.noteEvents.count else { return nil }
        return viewModel.noteStates[viewModel.noteEvents[index].id]
    }

    /// The main visual content area, switching between falling notes and sheet.
    @ViewBuilder
    private var contentArea: some View {
        if viewModel.playbackState == .loading {
            ProgressView("Loading song…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewModel.viewMode {
            case .fallingNotes:
                FallingNotesView(
                    noteEvents: viewModel.noteEvents,
                    playbackStartDate: viewModel.playbackStartDate,
                    tempoScale: viewModel.tempoScale,
                    currentNoteIndex: viewModel.currentNoteIndex,
                    noteStates: viewModel.noteStates,
                    notationMode: viewModel.notationMode,
                    keyPositions: keyPositions
                )
                .accessibilityLabel("Falling notes display")
                .accessibilityHint("Notes fall toward the piano keys during playback")

            case .scrollingSheet:
                ScrollingSheetView(
                    song: song,
                    currentNoteIndex: viewModel.currentNoteIndex,
                    notationMode: viewModel.notationMode,
                    currentPitch: viewModel.currentPitch,
                    highlightState: viewModel.highlightState,
                    currentNoteMatchState: currentNoteMatchState
                )
                .accessibilityLabel("Scrolling sheet notation")
                .accessibilityHint("Sheet notation scrolls to follow the current note")

            case .hide:
                Color.clear
                    .accessibilityLabel("Keyboard only mode — no notation overlay")
                    .accessibilityHint("Only the piano keyboard is visible")
            }
        }
    }

    // MARK: - Actions

    /// Handle the play/pause button tap based on current playback state.
    private func handlePlayPause() {
        switch viewModel.playbackState {
        case .idle, .stopped:
            Task {
                await viewModel.startSession()
            }
        case .playing:
            viewModel.pauseSession()
        case .paused:
            viewModel.resumeSession()
        case .loading, .error:
            break
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

    // MARK: - Pitch Feedback

    /// A compact horizontal bar showing the detected note name, cents deviation,
    /// confidence, and a `PitchProximityMeter` indicator.
    ///
    /// Visible only when the microphone detects a note above the silence/confidence
    /// thresholds. This gives the user immediate feedback before pressing Play.
    private func pitchFeedbackBar(pitch: PitchResult) -> some View {
        HStack(spacing: 12) {
            // Detected note name + octave
            VStack(alignment: .leading, spacing: 2) {
                Text("Detected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(pitch.noteName)
                        .font(.headline.bold())
                    // Show out-of-raga badge when available
                    if pitch.isInRaga == false {
                        Text("Outside Raga")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.orange))
                            .accessibilityLabel("Note is outside the raga")
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Detected note \(pitch.noteName)")

            // Cents deviation
            VStack(alignment: .leading, spacing: 2) {
                Text("Cents")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                let displayCents = pitch.ragaCentsOffset ?? pitch.centsOffset
                Text(String(format: "%+.0f", displayCents))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(centsColor(pitch.ragaCentsOffset ?? pitch.centsOffset))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(Int(pitch.ragaCentsOffset ?? pitch.centsOffset)) cents offset")

            // Vertical proximity meter
            PitchProximityMeter(
                centsOffset: pitch.ragaCentsOffset ?? pitch.centsOffset
            )
            .frame(width: 24, height: 48)

            Spacer()

            // Confidence
            VStack(alignment: .trailing, spacing: 2) {
                Text("Confidence")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(Int(pitch.confidence * 100))%")
                    .font(.callout.monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Confidence \(Int(pitch.confidence * 100)) percent")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    /// Map a cents offset to a feedback color (green ≤10¢, blue ≤25¢, orange ≤50¢, red >50¢).
    private func centsColor(_ cents: Double) -> Color {
        let abs = Swift.abs(cents)
        if abs <= 10 { return .green }
        if abs <= 25 { return .blue }
        if abs <= 50 { return .orange }
        return .red
    }

    // MARK: - Guided Play Overlays

    /// Brief banner flashing green (correct) or red (wrong) after each note attempt.
    private var correctnessBanner: some View {
        let isCorrect = correctnessBannerColor == .green
        return HStack(spacing: 8) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3.bold())
            Text(isCorrect ? "Correct!" : "Try again")
                .font(.headline)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(correctnessBannerColor.gradient, in: Capsule())
        .accessibilityLabel(isCorrect ? "Correct note" : "Wrong note, try again")
    }

    /// Overlay shown when user hasn't played for `patienceSeconds`.
    ///
    /// Displays the expected note name and a skip button.
    private func stuckHintOverlay(expectedMidiNote: Int) -> some View {
        let swarName = swarNameFromMIDI(expectedMidiNote)
        return VStack(spacing: 12) {
            Text("Play this note")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(swarName)
                .font(.largeTitle.bold())
                .foregroundStyle(.orange)
            HStack(spacing: 16) {
                Button {
                    withAnimation {
                        viewModel.skipGuidedNote()
                    }
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .accessibilityLabel("Skip this note")
                .accessibilityHint("Mark as missed and move to the next note")
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hint: play \(swarName)")
    }

    /// Convert a MIDI note number to a full swar name for the hint overlay.
    private func swarNameFromMIDI(_ midiNote: Int) -> String {
        let semitone = midiNote % 12
        // Map chromatic offset to swar name
        let swarNames = [
            "Sa", "Komal Re", "Re", "Komal Ga", "Ga", "Ma",
            "Tivra Ma", "Pa", "Komal Dha", "Dha", "Komal Ni", "Ni"
        ]
        let index = ((semitone % 12) + 12) % 12
        return swarNames[index]
    }

    // MARK: - Guided Play Actions

    /// Respond to guided play state transitions (correct/wrong flash).
    private func handleGuidedPlayStateChange(_ newState: PlayAlongViewModel.GuidedPlayState) {
        switch newState {
        case .correct:
            correctnessBannerColor = .green
            withAnimation { showCorrectnessBanner = true }
            // Auto-hide after 500ms
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation { showCorrectnessBanner = false }
            }
        case .wrong:
            correctnessBannerColor = .red
            withAnimation { showCorrectnessBanner = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation { showCorrectnessBanner = false }
            }
        case .waitingForNote, .stuck:
            withAnimation { showCorrectnessBanner = false }
        }
    }
}

// MARK: - Preview

#Preview("Play Along — Idle") {
    NavigationStack {
        SongPlayAlongView(
            song: Song(title: "Raag Yaman", difficulty: 2, tempo: 120)
        )
    }
}

#Preview("Play Along — With Song") {
    NavigationStack {
        SongPlayAlongView(
            song: {
                let song = Song(title: "Twinkle Twinkle", difficulty: 1, tempo: 100)
                return song
            }()
        )
    }
}
