import SVAudio
import SwiftUI

// MARK: - PlayAlongMinimalToolbar

/// Single-strip minimal toolbar for the play-along experience.
///
/// Replaces the multi-row `PlayAlongToolbar` with a compact horizontal layout:
/// - **Left cluster:** back, play/pause, restart, settings.
/// - **Center:** `SongPlayAlongTitleStrip` showing title, input, Sa, BPM.
/// - **Right cluster:** time pill, tempo `Menu` with presets + custom.
///
/// All transport actions flow through closures so the parent view retains
/// ownership of state-based dispatch logic.
struct PlayAlongMinimalToolbar: View {
    // MARK: - Properties

    /// View model for live playback state and tempo binding.
    @Bindable var viewModel: PlayAlongViewModel

    /// Called when the user taps play or pause.
    let onPlayPause: () -> Void

    /// Called when the user taps restart.
    let onRestart: () async -> Void

    /// Called when the user taps the settings gear.
    let onSettingsTap: () -> Void

    /// Called when the user selects "Custom..." from the tempo menu.
    let onTempoCustomTap: () -> Void

    /// When true, the "Custom..." item in the tempo menu is disabled
    /// (prevents stacking sheets).
    let showSettingsSheet: Bool

    /// Title of the currently loaded song.
    let songTitle: String

    /// Artist or subtitle for the song.
    let songArtist: String

    /// Base tempo in BPM from the song metadata.
    let baseBPM: Int

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            // Left cluster
            leftCluster

            Spacer(minLength: 4)

            // Center — title strip
            SongPlayAlongTitleStrip(
                viewModel: viewModel,
                songTitle: songTitle,
                songArtist: songArtist,
                baseBPM: baseBPM
            )
            .frame(maxWidth: .infinity)

            Spacer(minLength: 4)

            // Right cluster
            rightCluster
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Left Cluster

    /// Back, play/pause, restart, settings buttons.
    private var leftCluster: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.backward")
                    .font(.body)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Back")
            .accessibilityHint("Return to the song list")

            Button(action: onPlayPause) {
                Image(systemName: PlayAlongToolbar.playPauseIcon(for: viewModel.playbackState))
                    .font(.body)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
            .accessibilityHint(viewModel.isPlaying ? "Pause playback" : "Start or resume playback")

            Button {
                Task { await onRestart() }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Restart")
            .accessibilityHint("Restart the song from the beginning")

            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
                    .font(.body)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Settings")
            .accessibilityHint("Open play-along settings")
        }
    }

    // MARK: - Right Cluster

    /// Time pill and tempo menu.
    private var rightCluster: some View {
        HStack(spacing: 8) {
            timePill
            tempoMenu
        }
    }

    /// Pill showing elapsed / total time.
    private var timePill: some View {
        Text(
            verbatim:
                "\(PlayAlongToolbar.formatTime(viewModel.currentTime)) / \(PlayAlongToolbar.formatTime(viewModel.duration))"
        )
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
        .accessibilityLabel(
            "\(PlayAlongToolbar.formatTime(viewModel.currentTime)) of \(PlayAlongToolbar.formatTime(viewModel.duration))"
        )
    }

    /// Tempo preset menu with 50%–150% presets plus "Custom...".
    private var tempoMenu: some View {
        Menu {
            ForEach(Self.tempoPresets, id: \.self) { preset in
                let percent = Int((preset * 100).rounded())
                let isSelected = abs(viewModel.tempoScale - preset) < 0.01
                Button {
                    viewModel.tempoScale = preset
                } label: {
                    if isSelected {
                        Label("\(percent)%", systemImage: "checkmark")
                    } else {
                        Text(verbatim: "\(percent)%")
                    }
                }
            }
            Divider()
            Button("Custom\u{2026}") {
                onTempoCustomTap()
            }
            .disabled(showSettingsSheet)
        } label: {
            Text(verbatim: PlayAlongToolbar.formatTempoLabel(viewModel.tempoScale))
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())
        }
        .accessibilityLabel("Tempo")
        .accessibilityValue(PlayAlongToolbar.formatTempoLabel(viewModel.tempoScale))
        .accessibilityHint("Choose a tempo preset or custom speed")
    }

    // MARK: - Constants

    /// Tempo presets shown in the menu.
    private static let tempoPresets: [Double] = [0.5, 0.6, 0.75, 1.0, 1.25, 1.5]
}

// MARK: - PlayAlongToolbar (static helpers preserved for tests)

/// Legacy toolbar type preserved for its static helper methods.
///
/// Existing tests reference `PlayAlongToolbar.formatTime`,
/// `PlayAlongToolbar.formatTempoScale`, `PlayAlongToolbar.playPauseIcon(for:)`,
/// etc. This type keeps those statics available without breaking the test suite.
/// The UI has moved to `PlayAlongMinimalToolbar`.
enum PlayAlongToolbar {
    /// SF Symbol name for the play/pause button based on current playback state.
    ///
    /// - Parameter state: Current playback state.
    /// - Returns: SF Symbol name ("pause.fill" when playing, "play.fill" otherwise).
    static func playPauseIcon(for state: PlaybackState) -> String {
        switch state {
        case .playing:
            "pause.fill"
        default:
            "play.fill"
        }
    }

    /// Format a time interval as "m:ss".
    ///
    /// - Parameter time: Time in seconds to format.
    /// - Returns: Formatted string in "m:ss" format (e.g., "3:42").
    static func formatTime(_ time: TimeInterval) -> String {
        let clamped = max(time, 0)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Format tempo as "quarter-note = 72 BPM (60%)" given a scale and base BPM.
    ///
    /// - Parameters:
    ///   - scale: The tempo multiplier (0.4-1.0).
    ///   - baseBPM: The song's original BPM.
    /// - Returns: Formatted string like "quarter-note = 72 BPM (60%)".
    static func formatTempoBPM(scale: Double, baseBPM: Int) -> String {
        let effectiveBPM = Int((Double(baseBPM) * scale).rounded())
        let percent = Int((scale * 100).rounded())
        return "\u{2669} = \(effectiveBPM) BPM (\(percent)%)"
    }

    /// Format tempo scale as a short percentage string (e.g. "75%").
    ///
    /// - Parameter scale: The tempo multiplier value.
    /// - Returns: Formatted string like "75%" or "100%".
    static func formatTempoLabel(_ scale: Double) -> String {
        "\(Int((scale * 100).rounded()))%"
    }

    /// Format a tempo scale value as a human-readable string.
    ///
    /// Kept for backward compatibility with existing tests.
    ///
    /// - Parameter scale: The tempo multiplier value.
    /// - Returns: Formatted percentage string like "75%".
    static func formatTempoScale(_ scale: Double) -> String {
        formatTempoLabel(scale)
    }
}

// MARK: - Previews

#Preview("Minimal Toolbar — Idle") {
    PlayAlongMinimalToolbar(
        viewModel: PlayAlongViewModel(),
        onPlayPause: {},
        onRestart: {},
        onSettingsTap: {},
        onTempoCustomTap: {},
        showSettingsSheet: false,
        songTitle: "Aarohan Practice",
        songArtist: "Raga Yaman",
        baseBPM: 120
    )
    .padding()
}

#Preview("Minimal Toolbar — Playing") {
    PlayAlongMinimalToolbar(
        viewModel: {
            let vm = PlayAlongViewModel()
            vm.tempoScale = 0.75
            return vm
        }(),
        onPlayPause: {},
        onRestart: {},
        onSettingsTap: {},
        onTempoCustomTap: {},
        showSettingsSheet: false,
        songTitle: "Teentaal Drut",
        songArtist: "Raga Bhairav",
        baseBPM: 100
    )
    .padding()
}
