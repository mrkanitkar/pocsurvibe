import SVAudio
import SVCore
import SwiftUI

/// Displays a sing-along step with real-time pitch detection and accuracy scoring.
///
/// When a `Song` with sargam notation is provided, the view activates the microphone
/// via `PitchDetectionViewModel` and tracks note-matching accuracy against the expected
/// notes. The step auto-unlocks when accuracy reaches 60%.
///
/// When no song is available, falls back to manual "Done Singing" completion (accuracy 1.0).
///
/// ## Accuracy Tracking
/// Uses a simplified note-name matching approach: each detected note that matches the
/// current expected note increments `notesMatched`. Accuracy = notesMatched / totalNotes.
///
/// ## Mic Permission
/// If microphone access is denied, shows an inline message with a Settings deep link.
/// The user can still complete the step manually.
struct SingStepView: View {
    // MARK: - Properties

    /// The lesson step to display.
    let step: LessonStep

    /// The resolved song for this step, or nil if unavailable.
    let song: Song?

    /// Callback when singing is complete, with accuracy (0.0-1.0).
    let onComplete: (Double) -> Void

    /// Callback when user manually skips past the singing exercise.
    let onManualAdvance: () -> Void

    /// Sing step-type color. Passed by parent — never read from @Environment
    /// to preserve audio-latency contract (spec §5.5, §7). This view has the
    /// highest mutation frequency in the Learn tab (pitch @ 20–40 Hz).
    let singStepColor: Color

    /// Warning color for mic-permission-denied / low-accuracy hints.
    let warningColor: Color

    /// Nested surface color for chips inside the step card.
    let nestedSurfaceColor: Color

    /// Success color for accuracy-reached confirmations.
    let successColor: Color

    @State private var pitchVM = PitchDetectionViewModel()
    @State private var accuracy: Double = 0.0
    @State private var notesMatched: Int = 0
    @State private var totalNotes: Int = 0
    @State private var expectedNotes: [SargamNote] = []
    @State private var currentNoteIndex: Int = 0
    @State private var showSkipButton = false
    @State private var hasCompleted = false

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    // MARK: - Initialization

    /// Creates a sing step view with theme colors injected by the parent.
    ///
    /// All theme colors are required parameters — there are no defaults.
    /// Theme colors are `let` params rather than `@Environment` reads to preserve the
    /// audio-latency contract — `PitchDetectionViewModel` publishes at 20–40 Hz and
    /// reading from the environment on every render cycle would add overhead (spec §5.5, §7).
    ///
    /// - Parameters:
    ///   - step: The lesson step to display.
    ///   - song: The resolved song, or nil for manual-fallback mode.
    ///   - onComplete: Called with accuracy (0.0–1.0) when singing finishes.
    ///   - onManualAdvance: Called when the user skips the exercise.
    ///   - singStepColor: Accent color for sing-type UI elements.
    ///   - warningColor: Color for mic-denied and low-accuracy warnings.
    ///   - nestedSurfaceColor: Background fill for nested chip surfaces.
    ///   - successColor: Color for pass-threshold and completion indicators.
    init(
        step: LessonStep,
        song: Song?,
        onComplete: @escaping (Double) -> Void,
        onManualAdvance: @escaping () -> Void,
        singStepColor: Color = StepTypeColorSystem.color(for: .sing),
        warningColor: Color,
        nestedSurfaceColor: Color,
        successColor: Color
    ) {
        self.step = step
        self.song = song
        self.onComplete = onComplete
        self.onManualAdvance = onManualAdvance
        self.singStepColor = singStepColor
        self.warningColor = warningColor
        self.nestedSurfaceColor = nestedSurfaceColor
        self.successColor = successColor
    }

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

            if song != nil {
                pitchDetectionContent
            } else {
                manualFallbackContent
            }

            actionButtons

            if hasCompleted {
                completionBadge
            }
        }
        .task {
            await setupAndListen()
        }
        .task(id: "skipTimer") {
            try? await Task.sleep(for: .seconds(10))
            showSkipButton = true
        }
        .onChange(of: pitchVM.currentResult?.noteName) {
            updateAccuracy()
        }
        .onDisappear {
            pitchVM.stopListening()
        }
    }

    // MARK: - Pitch Detection Content

    /// Live pitch detection area showing the current detected note and accuracy.
    ///
    /// Displays a real-time note indicator, an accuracy progress bar, and
    /// a mic-denied warning when permission is not granted.
    private var pitchDetectionContent: some View {
        VStack(spacing: 16) {
            if pitchVM.micStatus == .denied {
                micPermissionDenied
            } else {
                liveNoteIndicator
                accuracyBar
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(nestedSurfaceColor)
        )
    }

    /// Displays the currently detected note name from the microphone.
    ///
    /// Shows the Sargam note name (e.g., "Sa", "Re") in large text, with
    /// a subtitle showing confidence. Falls back to "Listening..." when
    /// no note is detected.
    private var liveNoteIndicator: some View {
        VStack(spacing: 8) {
            if let result = pitchVM.currentResult {
                Text(verbatim: result.noteName)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(singStepColor)
                    .accessibilityLabel(Text("Detected note: \(result.noteName)"))

                Text("Confidence: \(Int(result.confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        Text("Detection confidence \(Int(result.confidence * 100)) percent")
                    )
            } else if pitchVM.isListening {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(singStepColor.opacity(0.5))
                    .accessibilityHidden(true)

                Text("Listening...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "music.mic")
                    .font(.system(size: 48))
                    .foregroundStyle(singStepColor.opacity(0.5))
                    .accessibilityHidden(true)

                Text("Starting microphone...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Shows current accuracy as a percentage and a progress bar.
    ///
    /// The bar fills from 0% to 100%. A green tint appears at 60%+ (pass threshold).
    private var accuracyBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Accuracy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(accuracy * 100))%")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(accuracy >= 0.60 ? successColor : .primary)
            }

            ProgressView(value: accuracy, total: 1.0)
                .tint(accuracy >= 0.60 ? successColor : singStepColor)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.3),
                    value: accuracy
                )
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Accuracy \(Int(accuracy * 100)) percent"))
        .accessibilityHint(Text("60 percent required to pass"))
    }

    /// Inline message shown when microphone permission is denied.
    ///
    /// Provides a button to open the Settings app for permission changes.
    private var micPermissionDenied: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 36))
                .foregroundStyle(warningColor)
                .accessibilityHidden(true)

            Text("Microphone access is needed for pitch detection")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("Open Settings"))
            .accessibilityHint(
                Text("Double tap to open Settings and enable microphone access")
            )
        }
        .padding(.vertical, 8)
    }

    // MARK: - Manual Fallback Content

    /// Fallback content when no song is available for pitch detection.
    ///
    /// Shows a placeholder card indicating manual completion mode.
    private var manualFallbackContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.mic")
                .font(.system(size: 48))
                .foregroundStyle(singStepColor.opacity(0.5))
                .accessibilityHidden(true)

            Text("Sing Along Mode")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Complete when you are finished singing")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(nestedSurfaceColor)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Sing along area — tap Done Singing when finished"))
    }

    // MARK: - Action Buttons

    /// Skip and Done Singing action buttons.
    ///
    /// Skip appears after 10 seconds. Done Singing sends the current accuracy
    /// (or 1.0 when no song is available for pitch detection).
    @ViewBuilder
    private var actionButtons: some View {
        if !hasCompleted {
            HStack(spacing: 12) {
                if showSkipButton {
                    Button {
                        hasCompleted = true
                        pitchVM.stopListening()
                        onManualAdvance()
                    } label: {
                        Text("Skip")
                            .font(.body)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text("Skip singing exercise"))
                    .accessibilityHint(Text("Double tap to skip to the next step"))
                }

                Button {
                    hasCompleted = true
                    pitchVM.stopListening()
                    let finalAccuracy = song != nil ? accuracy : 1.0
                    onComplete(finalAccuracy)
                } label: {
                    Label("Done Singing", systemImage: "checkmark.circle")
                        .font(.body)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(singStepColor)
                .accessibilityLabel(Text("Done singing"))
                .accessibilityHint(
                    Text("Double tap to mark the singing exercise as complete")
                )
            }
        }
    }

    // MARK: - Completion Badge

    /// Checkmark badge shown after the step is completed.
    private var completionBadge: some View {
        Label("Singing Complete", systemImage: "checkmark.circle.fill")
            .foregroundStyle(successColor)
            .font(.subheadline)
            .fontWeight(.medium)
            .accessibilityLabel(Text("Singing exercise completed"))
    }

    // MARK: - Subviews

    /// Badge identifying this step as a sing-along exercise.
    private var stepBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
            Text("Sing Along")
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(singStepColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(singStepColor.opacity(0.15)))
        .accessibilityLabel(Text("Step type: Sing Along"))
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

    /// Decodes expected notes from the song and starts pitch detection.
    ///
    /// If the song has sargam notation, decodes it and stores the expected
    /// note count. Then starts the pitch detection microphone session.
    /// No-op if no song is provided (manual fallback path).
    private func setupAndListen() async {
        guard let song else { return }

        if let notes = song.decodedSargamNotes {
            expectedNotes = notes
            totalNotes = notes.count
        }

        await pitchVM.startListening()
    }

    /// Updates accuracy based on the latest detected pitch.
    ///
    /// Compares the detected note name against the current expected note
    /// in the sargam sequence. On match, advances the note index and
    /// increments the match counter. Accuracy auto-triggers completion
    /// at the 60% threshold.
    private func updateAccuracy() {
        guard !hasCompleted else { return }
        guard !expectedNotes.isEmpty else { return }
        guard let result = pitchVM.currentResult else { return }
        guard result.confidence >= 0.5 else { return }
        guard currentNoteIndex < expectedNotes.count else { return }

        let expected = expectedNotes[currentNoteIndex]
        let expectedName = buildExpectedNoteName(expected)

        if result.noteName == expectedName {
            notesMatched += 1
            currentNoteIndex += 1
        }

        accuracy = Double(notesMatched) / Double(max(totalNotes, 1))

        if accuracy >= 0.60, !hasCompleted {
            hasCompleted = true
            pitchVM.stopListening()
            onComplete(accuracy)
        }
    }

    /// Builds the expected Sargam note name from a SargamNote.
    ///
    /// Combines the modifier (e.g., "Komal", "Tivra") with the base note name
    /// to match the format returned by PitchResult.noteName (e.g., "Komal Re", "Tivra Ma").
    ///
    /// - Parameter note: The SargamNote to build a name for.
    /// - Returns: The combined note name string.
    private func buildExpectedNoteName(_ note: SargamNote) -> String {
        if let modifier = note.modifier, !modifier.isEmpty {
            return "\(modifier) \(note.note)"
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
