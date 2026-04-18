import SVCore
import SwiftUI

/// Displays a listening step with audio playback controls.
///
/// When a `Song` with MIDI data is available, the view loads
/// `SongPlaybackEngine` and presents play/pause, a progress slider,
/// and auto-completes when the song finishes. For notation-only
/// songs or missing songs, it falls back to a manual "Mark as
/// Listened" button.
struct ListenStepView: View {
    // MARK: - Properties

    /// The lesson step to display.
    let step: LessonStep

    /// The resolved song for this step, or `nil` if not found.
    let song: Song?

    /// Callback when the listening activity is complete.
    let onComplete: () -> Void

    @State private var engine = SongPlaybackEngine()
    @State private var hasListened = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppThemeManager.self) private var themeManager

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepBadge

            Text(verbatim: step.content)
                .font(.body)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let seconds = step.durationSeconds {
                durationIndicator(seconds)
            }

            if song != nil, engine.hasPlayableContent {
                playbackControls
            } else {
                manualListenPrompt
            }

            if !hasListened {
                markAsListenedButton
            }

            if hasListened {
                listenedConfirmation
            }
        }
        .task { await loadSongIfNeeded() }
        .onDisappear { stopEngineIfPlaying() }
        .onChange(of: engine.playbackState) { _, newState in
            handlePlaybackStateChange(newState)
        }
    }

    // MARK: - Subviews

    /// Badge identifying this step as a listening exercise.
    private var stepBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "headphones")
                .accessibilityHidden(true)
            Text("Listen")
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(StepTypeColorSystem.color(for: .listen))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(StepTypeColorSystem.color(for: .listen).opacity(0.15)))
        .accessibilityLabel(Text("Step type: Listen"))
    }

    /// Play/pause toggle and progress slider for MIDI-backed songs.
    private var playbackControls: some View {
        VStack(spacing: 12) {
            playPauseButton

            // TODO: Implement seeking — slider is read-only until
            // SongPlaybackEngine supports seek(to:).
            Slider(
                value: .constant(sliderProgress),
                in: 0...1
            )
            .accessibilityLabel(Text("Playback progress"))
            .accessibilityValue(Text(progressAccessibilityText))

            HStack {
                Text(verbatim: formatDuration(Int(engine.currentPosition)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: formatDuration(Int(engine.duration)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.resolved.nestedSurfaceColor)
        )
    }

    /// Play/pause toggle button.
    private var playPauseButton: some View {
        Button {
            togglePlayback()
        } label: {
            Image(systemName: playButtonIcon)
                .font(.system(size: 36))
                .foregroundStyle(StepTypeColorSystem.color(for: .listen))
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .accessibilityLabel(Text(playButtonAccessibilityLabel))
        .accessibilityHint(Text(playButtonAccessibilityHint))
        .disabled(engine.playbackState == .loading)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: engine.playbackState)
    }

    /// Fallback prompt for songs without playable content.
    private var manualListenPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 32))
                .foregroundStyle(StepTypeColorSystem.color(for: .listen).opacity(0.5))
                .accessibilityHidden(true)
            Text("Listen to the song, then mark as complete.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    /// Manual completion button.
    private var markAsListenedButton: some View {
        Button {
            markComplete()
        } label: {
            Label("Mark as Listened", systemImage: "checkmark.circle")
                .font(.body)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(StepTypeColorSystem.color(for: .listen))
        .accessibilityLabel(Text("Mark as listened"))
        .accessibilityHint(Text("Double tap to confirm you have listened to the audio"))
    }

    /// Confirmation label shown after the step is complete.
    private var listenedConfirmation: some View {
        Label("Listened", systemImage: "checkmark.circle.fill")
            .foregroundStyle(themeManager.resolved.successColor)
            .font(.subheadline)
            .fontWeight(.medium)
            .accessibilityLabel(Text("Audio listening completed"))
    }

    /// Shows the estimated duration for this step.
    ///
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A label with a timer icon and formatted duration.
    private func durationIndicator(_ seconds: Int) -> some View {
        Label(formatDuration(seconds), systemImage: "timer")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Actions

    /// Loads the song into the engine when the view appears.
    private func loadSongIfNeeded() async {
        guard let song else { return }
        await engine.load(song: song)
    }

    /// Stops the engine if playback is active.
    private func stopEngineIfPlaying() {
        if engine.playbackState == .playing || engine.playbackState == .paused {
            engine.stop()
        }
    }

    /// Toggles between play, pause, and resume states.
    private func togglePlayback() {
        switch engine.playbackState {
        case .idle, .stopped:
            engine.play()
        case .playing:
            engine.pause()
        case .paused:
            engine.resume()
        case .loading, .error:
            break
        }
    }

    /// Auto-completes when playback finishes naturally.
    ///
    /// When the engine transitions from `.playing` to `.idle` (song
    /// reached the end), this marks the step complete automatically.
    private func handlePlaybackStateChange(_ newState: PlaybackState) {
        if newState == .idle, engine.duration > 0, !hasListened {
            markComplete()
        }
    }

    /// Marks the step as listened and fires the completion callback.
    private func markComplete() {
        guard !hasListened else { return }
        hasListened = true
        onComplete()
    }

    // MARK: - Computed Helpers

    /// Normalized progress value for the slider (0...1).
    private var sliderProgress: Double {
        guard engine.duration > 0 else { return 0 }
        return engine.currentPosition / engine.duration
    }

    /// SF Symbol name for the play/pause button.
    private var playButtonIcon: String {
        switch engine.playbackState {
        case .playing: "pause.circle.fill"
        case .loading: "hourglass.circle"
        default: "play.circle.fill"
        }
    }

    /// Accessibility label for the play/pause button.
    private var playButtonAccessibilityLabel: String {
        switch engine.playbackState {
        case .playing: "Pause"
        case .loading: "Loading"
        case .paused: "Resume"
        default: "Play"
        }
    }

    /// Accessibility hint for the play/pause button.
    private var playButtonAccessibilityHint: String {
        switch engine.playbackState {
        case .playing: "Double tap to pause playback"
        case .paused: "Double tap to resume playback"
        default: "Double tap to start playback"
        }
    }

    /// Accessibility text for the progress slider.
    private var progressAccessibilityText: String {
        let percent = Int(sliderProgress * 100)
        return "\(percent) percent complete"
    }

    // MARK: - Private Methods

    /// Formats seconds into a human-readable duration string.
    ///
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A formatted string like "30s", "2 min", or "1m 30s".
    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        return remaining == 0 ? "\(minutes) min" : "\(minutes)m \(remaining)s"
    }
}
