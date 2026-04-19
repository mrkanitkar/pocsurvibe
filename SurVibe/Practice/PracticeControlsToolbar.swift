import SwiftUI

/// Toolbar with play/pause, speed, metronome, and stop controls for practice mode.
///
/// Provides a consistent control bar at the bottom of practice views
/// for managing playback and session state.
struct PracticeControlsToolbar: View {
    /// Whether playback/practice is currently active.
    let isPlaying: Bool

    /// Whether the metronome is enabled.
    @Binding
    var isMetronomeEnabled: Bool

    /// Whether the tanpura drone is enabled.
    @Binding
    var isTanpuraEnabled: Bool

    /// Current speed multiplier (for display).
    let speedMultiplier: Double

    /// Called when the play/pause button is tapped.
    let onPlayPause: () -> Void

    /// Called when the stop button is tapped.
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            // Metronome toggle
            Button {
                isMetronomeEnabled.toggle()
            } label: {
                Image(systemName: isMetronomeEnabled ? "metronome.fill" : "metronome")
                    .font(.title3)
            }
            .accessibilityLabel(isMetronomeEnabled ? "Metronome on" : "Metronome off")
            .accessibilityHint("Toggle the metronome")

            // Tanpura drone toggle
            Button {
                isTanpuraEnabled.toggle()
            } label: {
                Image(systemName: isTanpuraEnabled ? "waveform.circle.fill" : "waveform.circle")
                    .font(.title3)
            }
            .accessibilityLabel(isTanpuraEnabled ? "Tanpura drone on" : "Tanpura drone off")
            .accessibilityHint("Toggles the Sa-Pa drone for tonic reference")

            Spacer()

            // Speed indicator
            Text(String(format: "%.1fx", speedMultiplier))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Speed \(String(format: "%.1f", speedMultiplier)) times")

            // Play/Pause
            Button {
                onPlayPause()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .accessibilityHint(isPlaying ? "Pause the practice session" : "Resume the practice session")

            Spacer()

            // Stop
            Button {
                onStop()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .accessibilityLabel("Stop")
            .accessibilityHint("End the practice session")
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}
