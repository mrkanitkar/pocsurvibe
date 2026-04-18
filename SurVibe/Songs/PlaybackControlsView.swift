import SVCore
import SwiftUI

/// Playback transport controls for song playback.
///
/// Displays a progress slider with time labels, play/pause and stop buttons,
/// and loading/error state indicators. Reads from a `SongPlaybackEngine`
/// instance to reflect the current playback state in real time.
///
/// The slider supports user-initiated seeking via local `@State` tracking.
/// During a drag gesture the slider value is decoupled from the engine's
/// position, preventing jitter. On release the seek position is applied.
struct PlaybackControlsView: View {
    // MARK: - Properties

    /// The playback engine driving audio output and position tracking.
    let engine: SongPlaybackEngine

    @Environment(AppThemeManager.self)
    private var themeManager

    /// Whether the user is currently dragging the progress slider.
    @State
    private var isUserSeeking = false

    /// The slider value during a user drag gesture.
    @State
    private var seekPosition: TimeInterval = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            progressBar

            controlButtons

            stateIndicator
        }
    }

    // MARK: - Private Views

    /// Progress slider with current and total time labels.
    private var progressBar: some View {
        HStack(spacing: 8) {
            Text(formatTime(isUserSeeking ? seekPosition : engine.currentPosition))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
                .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { isUserSeeking ? seekPosition : engine.currentPosition },
                    set: { newValue in
                        seekPosition = newValue
                        isUserSeeking = true
                    }
                ),
                in: 0...max(engine.duration, 0.01)
            )
            .accessibilityLabel("Playback progress")
            .accessibilityValue(progressPercentText)
            .accessibilityHint("Adjust to seek within the song")
            .onChange(of: isUserSeeking) { _, isSeeking in
                if !isSeeking {
                    // Seek completed — the engine does not yet support seeking,
                    // so we reset to current position. Seek support will be
                    // added in a future sprint.
                    seekPosition = engine.currentPosition
                }
            }

            Text(formatTime(engine.duration))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    /// Play/Pause and Stop transport buttons.
    private var controlButtons: some View {
        HStack(spacing: 32) {
            Spacer()

            Button(action: stopAction) {
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .disabled(isStopDisabled)
            .accessibilityLabel("Stop")
            .accessibilityHint("Stop playback and return to the beginning")

            Button(action: playPauseAction) {
                Image(systemName: playPauseIconName)
                    .font(.title)
                    .frame(width: 44, height: 44)
            }
            .disabled(isPlayPauseDisabled)
            .accessibilityLabel(playPauseAccessibilityLabel)
            .accessibilityHint(playPauseAccessibilityHint)

            Spacer()
        }
    }

    /// Loading spinner, error message, or notation-only indicator based on engine state.
    @ViewBuilder
    private var stateIndicator: some View {
        switch engine.playbackState {
        case .loading:
            ProgressView("Loading…")
                .font(.caption)
                .accessibilityLabel("Loading song")

        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(themeManager.resolved.errorColor)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Playback error: \(message)")

        case .idle where !engine.hasPlayableContent:
            Label("Notation only — no audio playback", systemImage: "music.note")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("This song has notation only. Audio playback is not available.")

        default:
            EmptyView()
        }
    }

    // MARK: - Private Computed Properties

    /// SF Symbol name for the play/pause button based on current state.
    private var playPauseIconName: String {
        switch engine.playbackState {
        case .playing:
            "pause.fill"
        default:
            "play.fill"
        }
    }

    /// VoiceOver label for the play/pause button.
    private var playPauseAccessibilityLabel: String {
        switch engine.playbackState {
        case .playing:
            "Pause"
        default:
            "Play"
        }
    }

    /// VoiceOver hint for the play/pause button.
    private var playPauseAccessibilityHint: String {
        switch engine.playbackState {
        case .playing:
            "Pause song playback"
        case .paused:
            "Resume song playback"
        default:
            "Start playing the song"
        }
    }

    /// Whether the stop button should be disabled.
    private var isStopDisabled: Bool {
        switch engine.playbackState {
        case .idle, .loading, .stopped, .error:
            true
        case .playing, .paused:
            false
        }
    }

    /// Whether the play/pause button should be disabled.
    ///
    /// Disabled during loading, error states, and when the song has no
    /// MIDI data (notation-only songs cannot be played back).
    private var isPlayPauseDisabled: Bool {
        switch engine.playbackState {
        case .loading, .error:
            true
        default:
            !engine.hasPlayableContent
        }
    }

    /// Percentage text for slider accessibility value.
    private var progressPercentText: String {
        guard engine.duration > 0 else { return "0 percent" }
        let position = isUserSeeking ? seekPosition : engine.currentPosition
        let percent = Int((position / engine.duration) * 100)
        return "\(percent) percent"
    }

    // MARK: - Private Methods

    /// Handle play/pause button tap based on current engine state.
    private func playPauseAction() {
        switch engine.playbackState {
        case .idle, .stopped:
            engine.play()
        case .playing:
            engine.pause()
        case .paused:
            engine.resume()
        default:
            break
        }
    }

    /// Handle stop button tap.
    private func stopAction() {
        engine.stop()
    }

    /// Format a time interval as "m:ss".
    ///
    /// - Parameter time: Time in seconds to format.
    /// - Returns: Formatted string in "m:ss" format (e.g., "3:42").
    private func formatTime(_ time: TimeInterval) -> String {
        let clamped = max(time, 0)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    PlaybackControlsView(engine: SongPlaybackEngine())
        .padding()
}
