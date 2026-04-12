import Foundation
import os.log
import SVCore

/// Phases of a quiz session.
///
/// The quiz progresses linearly: answer a question → review feedback → next question → ... → completed.
enum QuizPhase: Equatable, Sendable {
    /// Displaying a question for the user to answer.
    case inProgress(questionIndex: Int)

    /// Showing review feedback for the selected answer.
    case reviewing(questionIndex: Int, selectedAnswer: Int)

    /// All questions answered — showing final results.
    case completed
}

/// Manages the state machine for a lesson quiz.
///
/// The engine tracks which question the user is on, records their answers,
/// provides review feedback after each question, and computes final results.
///
/// ## State Flow
/// ```
/// inProgress(0) → [select answer] → reviewing(0, answer)
/// → [advance] → inProgress(1) → [select answer] → reviewing(1, answer)
/// → [advance] → ... → completed
/// ```
///
/// ## Usage
/// ```swift
/// let engine = QuizEngine(questions: decodedQuestions)
/// engine.selectAnswer(2)      // User picks option C
/// engine.advanceAfterReview() // Move to next question
/// ```
@Observable @MainActor
final class QuizEngine {
    // MARK: - Properties

    /// Current phase of the quiz.
    private(set) var phase: QuizPhase

    /// User's selected answer for each question (nil if not yet answered).
    private(set) var answers: [Int?]

    /// Final quiz result (nil until quiz is completed).
    private(set) var result: QuizResult?

    /// The quiz questions.
    let questions: [QuizQuestion]

    private static let logger = Logger.survibe(category: "QuizEngine")

    // MARK: - Computed Properties

    /// Index of the current question.
    var currentQuestionIndex: Int {
        switch phase {
        case .inProgress(let index):
            index
        case .reviewing(let index, _):
            index
        case .completed:
            questions.count - 1
        }
    }

    /// The current question being displayed (nil if completed with no questions).
    var currentQuestion: QuizQuestion? {
        let index = currentQuestionIndex
        guard index >= 0, index < questions.count else { return nil }
        return questions[index]
    }

    /// Number of correct answers so far.
    var correctCount: Int {
        answers.enumerated().reduce(0) { count, pair in
            let (index, answer) = pair
            guard let answer, index < questions.count else { return count }
            return count + (answer == questions[index].correctAnswerIndex ? 1 : 0)
        }
    }

    /// Number of questions answered so far.
    var totalAnswered: Int {
        answers.compactMap { $0 }.count
    }

    /// Whether all questions have been answered.
    var isComplete: Bool {
        if case .completed = phase { return true }
        return false
    }

    // MARK: - Initialization

    /// Create a new quiz engine with the given questions.
    ///
    /// Starts in `.inProgress(questionIndex: 0)` if questions exist,
    /// or `.completed` if the question array is empty.
    ///
    /// - Parameter questions: The quiz questions to present.
    init(questions: [QuizQuestion]) {
        self.questions = questions
        self.answers = Array(repeating: nil, count: questions.count)
        self.phase = questions.isEmpty ? .completed : .inProgress(questionIndex: 0)
        self.result = questions.isEmpty
            ? QuizResult(totalQuestions: 0, correctCount: 0)
            : nil
    }

    // MARK: - Actions

    /// Record the user's answer and transition to review phase.
    ///
    /// - Parameter answerIndex: The index of the selected option (0–3).
    func selectAnswer(_ answerIndex: Int) {
        guard case .inProgress(let questionIndex) = phase else {
            Self.logger.warning("selectAnswer called outside inProgress phase")
            return
        }
        guard questionIndex < questions.count else { return }
        guard answerIndex >= 0, answerIndex < questions[questionIndex].options.count else {
            Self.logger.warning("Invalid answer index: \(answerIndex)")
            return
        }

        answers[questionIndex] = answerIndex
        phase = .reviewing(questionIndex: questionIndex, selectedAnswer: answerIndex)
    }

    /// Advance past the review screen to the next question or completion.
    func advanceAfterReview() {
        guard case .reviewing(let questionIndex, _) = phase else {
            Self.logger.warning("advanceAfterReview called outside reviewing phase")
            return
        }

        let nextIndex = questionIndex + 1
        if nextIndex >= questions.count {
            // Quiz complete
            result = QuizResult(
                totalQuestions: questions.count,
                correctCount: correctCount
            )
            phase = .completed
            Self.logger.info("Quiz completed: \(self.correctCount)/\(self.questions.count)")
        } else {
            phase = .inProgress(questionIndex: nextIndex)
        }
    }

    /// Check if a specific answer is correct.
    ///
    /// - Parameters:
    ///   - questionIndex: The question index.
    ///   - answerIndex: The answer index to check.
    /// - Returns: `true` if the answer matches the correct answer.
    func isCorrect(questionIndex: Int, answerIndex: Int) -> Bool {
        guard questionIndex >= 0, questionIndex < questions.count else { return false }
        return questions[questionIndex].correctAnswerIndex == answerIndex
    }

    /// Reset the engine for a retry.
    func reset() {
        answers = Array(repeating: nil, count: questions.count)
        result = nil
        phase = questions.isEmpty ? .completed : .inProgress(questionIndex: 0)
        Self.logger.info("Quiz reset")
    }
}
