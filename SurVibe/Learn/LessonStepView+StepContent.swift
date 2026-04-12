import SwiftUI

// MARK: - Step Type Views

extension LessonStepView {
    /// Content view for intro and read step types.
    ///
    /// Displays the step content as readable text. These steps are always
    /// unlocked and require no interaction to advance.
    ///
    /// - Parameter step: The lesson step to display.
    /// - Returns: A text content view.
    func introReadContent(step: LessonStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: step.content)
                .font(.body)
                .lineSpacing(6)
        }
    }

    /// Content view for listen step type.
    ///
    /// Delegates to `ListenStepView` with the resolved song and gate callback.
    ///
    /// - Parameters:
    ///   - step: The lesson step to display.
    ///   - viewModel: The view model for gate callbacks.
    /// - Returns: The listen step view.
    func listenContent(step: LessonStep, song: Song?, viewModel: LessonPlayerViewModel) -> some View {
        ListenStepView(step: step, song: song) {
            viewModel.listenCompleted()
        }
    }

    /// Content view for sing step type.
    ///
    /// Delegates to `SingStepView` with the resolved song, accuracy callback, and skip callback.
    ///
    /// - Parameters:
    ///   - step: The lesson step to display.
    ///   - viewModel: The view model for gate callbacks.
    /// - Returns: The sing step view.
    func singContent(step: LessonStep, song: Song?, viewModel: LessonPlayerViewModel) -> some View {
        SingStepView(
            step: step,
            song: song,
            onComplete: { accuracy in
                viewModel.singCompleted(accuracy: accuracy)
            },
            onManualAdvance: {
                viewModel.singManualAdvance()
            }
        )
    }

    /// Content view for exercise and practice step types.
    ///
    /// Delegates to `ExerciseStepView` with the resolved song and gate callback.
    ///
    /// - Parameters:
    ///   - step: The lesson step to display.
    ///   - viewModel: The view model for gate callbacks.
    /// - Returns: The exercise step view.
    func exerciseContent(
        step: LessonStep,
        song: Song?,
        viewModel: LessonPlayerViewModel
    ) -> some View {
        ExerciseStepView(step: step, song: song) {
            viewModel.exerciseCompleted()
        }
    }

    /// Content view for quiz step type.
    ///
    /// Delegates to `QuizStepView` which decodes JSON questions and runs the quiz engine.
    ///
    /// - Parameters:
    ///   - step: The lesson step to display.
    ///   - viewModel: The view model for gate callbacks.
    /// - Returns: The quiz step view.
    func quizContent(step: LessonStep, viewModel: LessonPlayerViewModel) -> some View {
        QuizStepView(step: step) { score in
            viewModel.quizCompleted(score: score)
        }
    }
}

// MARK: - Helper Views & Utilities

extension LessonStepView {
    /// A placeholder card for unimplemented step features.
    ///
    /// - Parameters:
    ///   - icon: SF Symbol name for the card icon.
    ///   - title: Headline text.
    ///   - description: Caption text.
    /// - Returns: A styled card view.
    func placeholderCard(
        icon: String,
        title: String,
        description: String
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemBackground))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title): \(description)"))
    }

    /// Human-readable label for a step type.
    ///
    /// - Parameter type: The step type string identifier.
    /// - Returns: A display-friendly label.
    func stepTypeLabel(_ type: String) -> String {
        switch type {
        case "intro": "Introduction"
        case "listen": "Listen"
        case "read": "Read"
        case "exercise": "Exercise"
        case "practice": "Practice"
        case "quiz": "Quiz"
        case "sing": "Sing Along"
        default: type.capitalized
        }
    }

    /// SF Symbol icon name for a step type.
    ///
    /// - Parameter type: The step type string identifier.
    /// - Returns: An SF Symbol name.
    func stepTypeIcon(_ type: String) -> String {
        switch type {
        case "intro": "text.book.closed"
        case "listen": "headphones"
        case "read": "doc.text"
        case "exercise": "hand.tap"
        case "practice": "music.mic"
        case "quiz": "questionmark.circle"
        case "sing": "waveform"
        default: "circle"
        }
    }

    /// Color associated with a step type.
    ///
    /// - Parameter type: The step type string identifier.
    /// - Returns: A color for the step badge and icon.
    func stepTypeColor(_ type: String) -> Color {
        switch type {
        case "intro": .blue
        case "listen": .purple
        case "read": .orange
        case "exercise": .green
        case "practice": .red
        case "quiz": .yellow
        case "sing": .pink
        default: .gray
        }
    }

    /// Format seconds into a human-readable duration string.
    ///
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A formatted string like "30s", "2 min", or "1m 30s".
    func durationLabel(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remaining = seconds % 60
        if remaining == 0 {
            return "\(minutes) min"
        }
        return "\(minutes)m \(remaining)s"
    }
}
