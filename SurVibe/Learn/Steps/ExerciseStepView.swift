import SVAudio
import SVCore
import SVLearning
import SwiftUI

/// Displays an exercise step with WaitMode drill functionality.
///
/// When a `Song` with Sargam notation is provided, the view runs an
/// interactive note-by-note drill: the learner plays each expected note
/// on the piano (detected via microphone) and the WaitModeEngine
/// evaluates accuracy and advances through the sequence.
///
/// When no song or notation data is available, falls back to showing
/// the step content with a manual "Mark as Complete" button.
///
/// ## Mic Permission
/// If microphone access is denied, the drill is disabled and an inline
/// message with a Settings deep link is shown instead.
struct ExerciseStepView: View {
    // MARK: - Properties

    /// The lesson step to display.
    let step: LessonStep

    /// Resolved song for this step (nil if step has no songId or song not found).
    let song: Song?

    /// Callback when the exercise is complete.
    let onComplete: () -> Void

    @State private var waitEngine = WaitModeEngine(
        configuration: WaitModeConfiguration(isEnabled: true)
    )
    @State private var pitchVM = PitchDetectionViewModel()
    @State private var currentNoteIdx = 0
    @State private var hasCompleted = false
    @State private var showFallbackButton = false

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.openURL)
    private var openURL

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

            if let notes = sargamNotes, !notes.isEmpty {
                drillContent(notes)
            } else {
                manualFallback
            }

            if hasCompleted {
                completionBanner
            }
        }
    }

    // MARK: - Computed Properties

    /// Decoded sargam notes from the song's notation data.
    private var sargamNotes: [SargamNote]? {
        song?.decodedSargamNotes
    }

    // MARK: - Drill Content

    /// Interactive drill area with note display, progress, and mic status.
    ///
    /// Listens for pitch via the microphone and evaluates each attempt
    /// against the expected note using WaitModeEngine.
    ///
    /// - Parameter notes: The decoded sargam notation array.
    /// - Returns: A view containing the drill UI with progress and feedback.
    @ViewBuilder
    private func drillContent(_ notes: [SargamNote]) -> some View {
        if pitchVM.micStatus == .denied || pitchVM.micStatus == .restricted {
            micDeniedBanner
        } else {
            VStack(spacing: 16) {
                progressBar(current: currentNoteIdx, total: notes.count)

                expectedNoteDisplay(notes)

                statsRow

                micStatusIndicator
            }
            .padding(.vertical, 12)
            .task {
                await pitchVM.startListening()
                waitEngine.waitForNote()
            }
            .onChange(of: pitchVM.currentResult) { _, newResult in
                guard let result = newResult,
                      result.confidence > 0.5,
                      waitEngine.state == .waiting,
                      currentNoteIdx < notes.count
                else { return }

                let expected = notes[currentNoteIdx]
                waitEngine.evaluateAttempt(
                    detectedNoteName: result.noteName,
                    detectedOctave: result.octave,
                    detectedCents: result.centsOffset,
                    expectedNoteName: noteDisplayName(expected),
                    expectedOctave: expected.octave
                )
            }
            .onChange(of: waitEngine.state) { _, newState in
                guard newState == .advancing || newState == .skipped else { return }
                advanceToNextNote(in: notes)
            }
            .onDisappear {
                pitchVM.stopListening()
                waitEngine.reset()
            }
        }

        if !hasCompleted {
            fallbackCompleteButton
        }
    }

    // MARK: - Subviews

    /// Badge identifying this step as an exercise.
    private var stepBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.tap")
            Text("Exercise")
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(.green)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(.green.opacity(0.15)))
        .accessibilityLabel(Text("Step type: Exercise"))
    }

    /// Shows a progress bar for the note sequence.
    ///
    /// - Parameters:
    ///   - current: The current note index (0-based).
    ///   - total: Total number of notes in the sequence.
    /// - Returns: A labeled progress view.
    private func progressBar(current: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(
                value: Double(min(current, total)),
                total: Double(total)
            )
            .tint(.green)

            Text(verbatim: "\(min(current, total)) / \(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Progress: \(min(current, total)) of \(total) notes"))
    }

    /// Displays the expected note the learner should play.
    ///
    /// Shows the full swar name (including Komal/Tivra modifier) and octave.
    /// Highlights with a scale animation when the engine is in `.waiting` state.
    ///
    /// - Parameter notes: The full sargam notation array.
    /// - Returns: A view showing the current expected note.
    private func expectedNoteDisplay(_ notes: [SargamNote]) -> some View {
        VStack(spacing: 8) {
            if currentNoteIdx < notes.count {
                let note = notes[currentNoteIdx]
                Text(verbatim: noteDisplayName(note))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(waitEngine.state == .waiting ? .green : .primary)
                    .scaleEffect(waitEngine.state == .waiting ? 1.1 : 1.0)
                    .animation(
                        reduceMotion ? .none : .easeInOut(duration: 0.3),
                        value: waitEngine.state
                    )
                    .accessibilityLabel(Text("Play \(noteDisplayName(note)), octave \(note.octave)"))
                    .accessibilityHint(Text("Play this note on the piano"))

                Text(verbatim: "Octave \(note.octave)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                Text("All notes complete")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    /// Shows correct count, skipped count, and total attempts.
    private var statsRow: some View {
        HStack(spacing: 24) {
            statItem(
                label: "Correct",
                value: "\(waitEngine.correctOnFirstAttempt)",
                color: .green
            )
            statItem(
                label: "Skipped",
                value: "\(waitEngine.skippedCount)",
                color: .orange
            )
            statItem(
                label: "Attempts",
                value: "\(waitEngine.totalAttempts)",
                color: .blue
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(
                """
                \(waitEngine.correctOnFirstAttempt) correct, \
                \(waitEngine.skippedCount) skipped, \
                \(waitEngine.totalAttempts) total attempts
                """
            )
        )
    }

    /// A single stat item with a label and value.
    ///
    /// - Parameters:
    ///   - label: Description of the stat.
    ///   - value: Current value as a string.
    ///   - color: Accent color for the value text.
    /// - Returns: A vertically stacked label and value.
    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Mic status indicator showing whether pitch detection is active.
    private var micStatusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(pitchVM.isListening ? .green : .red)
                .frame(width: 8, height: 8)
            Text(pitchVM.isListening ? "Listening" : "Mic inactive")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(pitchVM.isListening ? "Microphone is active" : "Microphone is not active")
        )
    }

    /// Inline banner shown when microphone permission is denied.
    ///
    /// Provides an explanation and a button to open Settings.
    private var micDeniedBanner: some View {
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
    private var manualFallback: some View {
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
    private var fallbackCompleteButton: some View {
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

    /// Green completion checkmark shown after the exercise is done.
    private var completionBanner: some View {
        Label("Exercise Complete", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .font(.subheadline)
            .fontWeight(.medium)
            .accessibilityLabel(Text("Exercise completed"))
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

    // MARK: - Private Methods

    /// Advance to the next note in the sequence, or finish if all done.
    ///
    /// Called when WaitModeEngine transitions to `.advancing` or `.skipped`.
    /// Increments the note index and either starts waiting for the next note
    /// or completes the exercise.
    ///
    /// - Parameter notes: The full sargam notation array.
    private func advanceToNextNote(in notes: [SargamNote]) {
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
    private func noteDisplayName(_ note: SargamNote) -> String {
        if let modifier = note.modifier {
            return "\(modifier.capitalized) \(note.note)"
        }
        return note.note
    }

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
