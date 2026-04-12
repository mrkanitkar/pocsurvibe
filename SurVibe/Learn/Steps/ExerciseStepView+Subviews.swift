import SVAudio
import SVCore
import SVLearning
import SwiftUI

// MARK: - Drill Subviews

extension ExerciseStepView {
    /// Inline banner shown when microphone permission is denied.
    ///
    /// Provides an explanation and a button to open Settings.
    var micDeniedBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red.opacity(0.6))
                .accessibilityHidden(true)

            Text("Microphone access is required for the exercise drill.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let url = PermissionManager.shared.settingsURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Open Settings to enable microphone"))
                .accessibilityHint(
                    Text("Double tap to open the Settings app and grant microphone access")
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Microphone access denied. Open Settings to enable."))
    }

    /// Manual fallback when no song or notation is available.
    var manualFallback: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green.opacity(0.5))
                .accessibilityHidden(true)

            Text("Practice Exercise")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Follow the instructions above, then mark as complete.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if !hasCompleted {
                Button {
                    hasCompleted = true
                    onComplete()
                } label: {
                    Label("Mark as Complete", systemImage: "checkmark.circle")
                        .font(.body)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityLabel(Text("Mark exercise as complete"))
                .accessibilityHint(Text("Double tap to confirm you have completed the exercise"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemBackground))
        )
        .accessibilityElement(children: .contain)
    }

    /// Fallback "Mark as Complete" button that appears after 30 seconds.
    ///
    /// Acts as an escape hatch if pitch detection is not working or
    /// the learner wants to skip the drill.
    var fallbackCompleteButton: some View {
        Group {
            if showFallbackButton {
                Button {
                    hasCompleted = true
                    pitchVM.stopListening()
                    waitEngine.reset()
                    onComplete()
                } label: {
                    Label("Mark as Complete", systemImage: "checkmark.circle")
                        .font(.body)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .accessibilityLabel(Text("Mark exercise as complete manually"))
                .accessibilityHint(Text("Double tap to skip the drill and mark as complete"))
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(30))
            showFallbackButton = true
        }
    }
}

// MARK: - Helper Methods

extension ExerciseStepView {
    /// Advance to the next note in the sequence, or finish if all done.
    ///
    /// Called when WaitModeEngine transitions to `.advancing` or `.skipped`.
    /// Increments the note index and either starts waiting for the next note
    /// or completes the exercise.
    ///
    /// - Parameter notes: The full sargam notation array.
    func advanceToNextNote(in notes: [SargamNote]) {
        let nextIdx = currentNoteIdx + 1
        currentNoteIdx = nextIdx
        if nextIdx < notes.count {
            waitEngine.waitForNote()
        } else {
            hasCompleted = true
            pitchVM.stopListening()
            onComplete()
        }
    }

    /// Builds the full swar name including modifier prefix.
    ///
    /// Matches the format returned by `SwarUtility.frequencyToNote()` and
    /// `PitchResult.noteName` (e.g., "Komal Re", "Tivra Ma", "Sa").
    ///
    /// - Parameter note: The sargam note to format.
    /// - Returns: Display string such as "Komal Re" or "Sa".
    func noteDisplayName(_ note: SargamNote) -> String {
        if let modifier = note.modifier {
            return "\(modifier.capitalized) \(note.note)"
        }
        return note.note
    }

    /// Formats seconds into a human-readable duration string.
    ///
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A formatted string like "30s", "2 min", or "1m 30s".
    func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        return remaining == 0 ? "\(minutes) min" : "\(minutes)m \(remaining)s"
    }
}
