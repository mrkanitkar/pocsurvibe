import SVCore
import SwiftUI

/// Displays a quiz step with multi-choice questions and feedback.
///
/// Decodes `[QuizQuestion]` from the step's `content` field (JSON),
/// creates a `QuizEngine`, and renders three phases:
/// 1. **Question**: Shows question text with 4 option buttons (A/B/C/D)
/// 2. **Review**: Shows correct/incorrect feedback after each answer
/// 3. **Results**: Shows final score with encouraging message
///
/// Calls `onComplete(score)` when the quiz is finished.
struct QuizStepView: View {
    // MARK: - Properties

    /// The lesson step containing quiz questions as JSON in `content`.
    let step: LessonStep

    /// Callback when the quiz is complete, with score (0.0-1.0).
    let onComplete: (Double) -> Void

    @Environment(AppThemeManager.self) private var themeManager

    @State private var engine: QuizEngine?
    @State private var decodingError = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepBadge

            if decodingError {
                errorView
            } else if let engine {
                quizContent(engine: engine)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            }
        }
        .task {
            decodeQuestions()
        }
    }

    // MARK: - Quiz Content

    /// Routes to the appropriate quiz phase view.
    ///
    /// - Parameter engine: The quiz engine managing state.
    /// - Returns: The view for the current quiz phase.
    @ViewBuilder
    private func quizContent(engine: QuizEngine) -> some View {
        switch engine.phase {
        case .inProgress(let questionIndex):
            questionView(engine: engine, questionIndex: questionIndex)

        case .reviewing(let questionIndex, let selectedAnswer):
            reviewView(engine: engine, questionIndex: questionIndex, selectedAnswer: selectedAnswer)

        case .completed:
            if let result = engine.result {
                resultsView(result: result)
            }
        }
    }

    // MARK: - Question View

    /// Displays the current question with answer options.
    ///
    /// Shows a progress header, question text, question type badge,
    /// and four tappable answer options (A/B/C/D).
    ///
    /// - Parameters:
    ///   - engine: The quiz engine managing state.
    ///   - questionIndex: Index of the current question.
    /// - Returns: The question view with answer buttons.
    private func questionView(engine: QuizEngine, questionIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Progress header
            HStack {
                Text("Question \(questionIndex + 1) of \(engine.questions.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(engine.correctCount) correct")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.resolved.successColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text(
                    "Question \(questionIndex + 1) of \(engine.questions.count), \(engine.correctCount) correct so far"
                )
            )

            if let question = engine.currentQuestion {
                // Question text
                Text(verbatim: question.questionText)
                    .font(.title3)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Question type badge
                questionTypeBadge(question.questionType)

                // Answer options
                VStack(spacing: 10) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        Button {
                            engine.selectAnswer(index)
                        } label: {
                            HStack {
                                Text(optionLetter(index))
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.accentColor.opacity(0.15)))

                                Text(verbatim: option)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(themeManager.resolved.cardBackgroundColor)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Option \(optionLetter(index)): \(option)"))
                        .accessibilityHint(Text("Double tap to select this answer"))
                    }
                }
            }
        }
    }

    // MARK: - Review View

    /// Displays feedback after answering a question.
    ///
    /// Shows a large correct/incorrect icon, the selected vs correct answer
    /// (when wrong), and a "Continue" button to advance to the next question.
    ///
    /// - Parameters:
    ///   - engine: The quiz engine managing state.
    ///   - questionIndex: Index of the reviewed question.
    ///   - selectedAnswer: The answer index the user chose.
    /// - Returns: The review feedback view.
    private func reviewView(engine: QuizEngine, questionIndex: Int, selectedAnswer: Int) -> some View {
        let isCorrect = engine.isCorrect(questionIndex: questionIndex, answerIndex: selectedAnswer)
        let question = engine.questions[questionIndex]

        return VStack(spacing: 20) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(isCorrect ? themeManager.resolved.successColor : themeManager.resolved.errorColor)
                .accessibilityHidden(true)

            Text(isCorrect ? "Correct!" : "Not quite")
                .font(.title2).fontWeight(.bold)
                .foregroundStyle(isCorrect ? themeManager.resolved.successColor : themeManager.resolved.errorColor)

            if !isCorrect {
                incorrectAnswerDetails(
                    userAnswer: question.options[selectedAnswer],
                    correctAnswer: question.options[question.correctAnswerIndex]
                )
            }

            Button {
                engine.advanceAfterReview()
                if engine.isComplete, let result = engine.result {
                    onComplete(result.score)
                }
            } label: {
                Text("Continue")
                    .font(.body).fontWeight(.semibold)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(Text("Continue to next question"))
            .accessibilityHint(Text("Double tap to proceed"))
        }
        .frame(maxWidth: .infinity).padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(isCorrect ? "Correct answer" : "Incorrect answer"))
    }

    /// Shows the user's answer and the correct answer side by side.
    private func incorrectAnswerDetails(userAnswer: String, correctAnswer: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Your answer:").foregroundStyle(.secondary)
                Text(verbatim: userAnswer).fontWeight(.medium).foregroundStyle(themeManager.resolved.errorColor)
            }.font(.subheadline)
            HStack {
                Text("Correct answer:").foregroundStyle(.secondary)
                Text(verbatim: correctAnswer).fontWeight(.medium).foregroundStyle(themeManager.resolved.successColor)
            }.font(.subheadline)
        }
    }

    // MARK: - Results View

    /// Displays the final quiz results with score and message.
    ///
    /// Shows a circular progress ring with the percentage score,
    /// the number correct, and an encouraging message.
    ///
    /// - Parameter result: The computed quiz result.
    /// - Returns: The results summary view.
    private func resultsView(result: QuizResult) -> some View {
        VStack(spacing: 20) {
            // Score circle
            ZStack {
                Circle()
                    .stroke(themeManager.resolved.dividerColor, lineWidth: 8)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: result.score)
                    .stroke(scoreColor(result.percentage), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))

                Text("\(result.percentage)%")
                    .font(.title)
                    .fontWeight(.bold)
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Quiz score: \(result.percentage) percent"))

            Text("\(result.correctCount) of \(result.totalQuestions) correct")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(result.message)
                .font(.body)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Subviews

    /// Badge identifying this step as a quiz.
    private var stepBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
                .accessibilityHidden(true)
            Text("Quiz")
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(themeManager.resolved.warningColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(themeManager.resolved.warningColor.opacity(0.15)))
        .accessibilityLabel(Text("Step type: Quiz"))
    }

    /// Badge showing the type of quiz question being asked.
    ///
    /// - Parameter type: The question type.
    /// - Returns: A capsule badge with icon and label.
    private func questionTypeBadge(_ type: QuestionType) -> some View {
        let (icon, label): (String, String) = switch type {
        case .noteIdentification:
            ("music.note", "Note Identification")
        case .intervalRecognition:
            ("arrow.left.and.right", "Interval Recognition")
        case .sargamMatching:
            ("arrow.triangle.swap", "Sargam Matching")
        }

        return Label(label, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(themeManager.resolved.nestedSurfaceColor))
            .accessibilityLabel(Text("Question type: \(label)"))
    }

    /// Error view shown when quiz questions fail to decode.
    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(themeManager.resolved.warningColor)
                .accessibilityHidden(true)
            Text("Could not load quiz questions")
                .font(.headline)
            Text("The quiz data may be malformed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Error: Could not load quiz questions"))
    }

    // MARK: - Private Methods

    /// Decodes quiz questions from the step's JSON content.
    ///
    /// Parses `step.content` as a JSON array of `QuizQuestion`.
    /// Sets `decodingError` to true if parsing fails.
    private func decodeQuestions() {
        guard let data = step.content.data(using: .utf8) else {
            decodingError = true
            return
        }
        do {
            let questions = try JSONDecoder().decode([QuizQuestion].self, from: data)
            engine = QuizEngine(questions: questions)
        } catch {
            decodingError = true
        }
    }

    /// Converts a zero-based index to a letter label (A, B, C, D).
    ///
    /// - Parameter index: The option index.
    /// - Returns: A letter string for the option.
    private func optionLetter(_ index: Int) -> String {
        switch index {
        case 0: "A"
        case 1: "B"
        case 2: "C"
        case 3: "D"
        default: "\(index + 1)"
        }
    }

    /// Score color routed through theme tokens — success / warning / error.
    ///
    /// - Parameter percentage: The quiz score percentage (0-100).
    /// - Returns: Success color for 90%+, warning color for 70-89%, error color for below 70%.
    private func scoreColor(_ percentage: Int) -> Color {
        switch percentage {
        case 90...:   return themeManager.resolved.successColor
        case 70..<90: return themeManager.resolved.warningColor
        default:      return themeManager.resolved.errorColor
        }
    }
}
