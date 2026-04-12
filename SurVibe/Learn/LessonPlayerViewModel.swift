import Foundation
import os.log
import SVCore
import SwiftData

/// Phases of the lesson player.
///
/// Represents the three distinct states a lesson can be in:
/// loading content, actively presenting steps, or completed.
enum PlayerPhase: Equatable, Sendable {
    /// Loading lesson content.
    case loading
    /// Actively presenting a step at the given index.
    case active(stepIndex: Int)
    /// Lesson completed — all steps finished.
    case completed
}

/// Whether the current step's gate is locked or unlocked.
///
/// Gates prevent the learner from advancing until they complete the
/// step's interactive requirement (e.g., listening to audio, answering a quiz).
enum StepGateStatus: Equatable, Sendable {
    /// Step completion criteria not yet met. Contains a user-facing reason.
    case locked(reason: String)
    /// Step is ready to advance.
    case unlocked
}

/// Manages the lesson player state machine, step gating, and progress tracking.
///
/// The ViewModel orchestrates the step-by-step lesson experience:
/// 1. Loads lesson steps and restores resume position from `LessonProgress`
/// 2. Evaluates gate status for each step type (intro = always unlocked, etc.)
/// 3. Receives completion signals from step views (listen, sing, exercise, quiz)
/// 4. Persists step completion and time spent via `LessonProgressManager`
/// 5. Transitions to `.completed` when the final step is finished
///
/// ## Step Gating Rules
/// | Step Type | Gate Behavior |
/// |-----------|---------------|
/// | intro     | Always unlocked |
/// | read      | Always unlocked |
/// | listen    | Locked until `listenCompleted()` called |
/// | sing      | Locked until `singCompleted(accuracy:)` >= 0.60 or manual advance |
/// | exercise  | Locked until `exerciseCompleted()` or manual advance |
/// | practice  | Locked until `exerciseCompleted()` or manual advance |
/// | quiz      | Locked until `quizCompleted(score:)` called |
@Observable @MainActor
final class LessonPlayerViewModel {
    // MARK: - Properties

    /// Current phase of the lesson player.
    private(set) var phase: PlayerPhase = .loading

    /// Gate status for the current step.
    private(set) var gateStatus: StepGateStatus = .unlocked

    /// Quiz score from the most recent quiz step (nil if no quiz yet).
    private(set) var quizScore: Double?

    /// The lesson being played.
    let lesson: Lesson

    /// Decoded steps from the lesson.
    let steps: [LessonStep]

    /// Progress manager for persistence.
    private let progressManager: LessonProgressManager

    /// Gamification service for XP awards, rang progression, and achievements.
    private let gamificationService: GamificationService?

    /// Timestamp when the current session started.
    private var sessionStartTime: Date = Date()

    /// Logger for player events.
    nonisolated private static let logger = Logger.survibe(category: "LessonPlayer")

    // MARK: - Computed Properties

    /// Index of the currently active step.
    var currentStepIndex: Int {
        switch phase {
        case .loading:
            0
        case .active(let index):
            index
        case .completed:
            max(steps.count - 1, 0)
        }
    }

    /// The current step being displayed.
    var currentStep: LessonStep? {
        let index = currentStepIndex
        guard index >= 0, index < steps.count else { return nil }
        return steps[index]
    }

    /// Total number of steps.
    var totalSteps: Int {
        steps.count
    }

    /// Progress fraction (0.0-1.0) based on completed steps.
    ///
    /// Reads persisted step completion flags from `LessonProgressManager`
    /// and calculates the ratio of completed to total steps.
    var progressFraction: Double {
        guard totalSteps > 0 else { return 0.0 }
        let progress = progressManager.progress(for: lesson.lessonId)
        let completedCount = progress.stepCompletionFlags.filter { $0 }.count
        return Double(completedCount) / Double(totalSteps)
    }

    /// Whether the user can go to the previous step.
    var canGoBack: Bool {
        currentStepIndex > 0
    }

    /// Whether the user can advance to the next step.
    var canGoNext: Bool {
        gateStatus == .unlocked
    }

    /// Whether the current step is the last one.
    var isLastStep: Bool {
        currentStepIndex == steps.count - 1
    }

    // MARK: - Initialization

    /// Creates a lesson player for the given lesson.
    ///
    /// Decodes steps from the lesson's `stepsData` JSON blob. If decoding
    /// fails or the lesson has no steps, the steps array will be empty and
    /// the player will immediately transition to `.completed` on appear.
    ///
    /// - Parameters:
    ///   - lesson: The lesson to play.
    ///   - progressManager: The progress manager for persistence.
    ///   - gamificationService: Optional gamification service for XP/achievement wiring.
    init(
        lesson: Lesson,
        progressManager: LessonProgressManager,
        gamificationService: GamificationService? = nil
    ) {
        self.lesson = lesson
        self.steps = lesson.decodedSteps ?? []
        self.progressManager = progressManager
        self.gamificationService = gamificationService
    }

    // MARK: - Lifecycle

    /// Called when the lesson player view appears.
    ///
    /// Restores the resume position from saved progress and evaluates
    /// the gate status for the current step. Updates `lastAccessedAt`
    /// on the progress record.
    func onAppear() {
        sessionStartTime = Date()

        let progress = progressManager.progress(for: lesson.lessonId)
        progress.lastAccessedAt = Date()

        let resumeIndex = min(progress.currentStepIndex, max(steps.count - 1, 0))

        if steps.isEmpty {
            phase = .completed
        } else {
            phase = .active(stepIndex: resumeIndex)
            evaluateGate()
        }

        Self.logger.info(
            "Lesson player started: '\(self.lesson.lessonId)' at step \(resumeIndex)"
        )
    }

    /// Called when the lesson player view disappears.
    ///
    /// Saves elapsed session time to the progress record. Sessions shorter
    /// than 1 second are ignored to avoid noise from accidental opens.
    func onDisappear() {
        let elapsed = Date().timeIntervalSince(sessionStartTime)
        if elapsed > 1.0 {
            progressManager.addTimeSpent(lessonId: lesson.lessonId, seconds: elapsed)
        }
    }

    // MARK: - Navigation

    /// Advance to the next step or complete the lesson.
    ///
    /// Checks gate status, marks the current step as complete via
    /// `LessonProgressManager`, and either advances to the next step
    /// or finalizes the lesson with quiz score and session time.
    func goToNextStep() {
        guard canGoNext else { return }

        let index = currentStepIndex
        progressManager.completeStep(
            lessonId: lesson.lessonId,
            stepIndex: index,
            totalSteps: totalSteps
        )

        // Award XP for completing this step
        let completedStepType = steps[index].stepType
        gamificationService?.handleStepCompleted(
            lessonId: lesson.lessonId,
            stepType: completedStepType,
            quizScore: completedStepType == "quiz" ? quizScore : nil
        )

        if isLastStep {
            // Complete the lesson
            let elapsed = Date().timeIntervalSince(sessionStartTime)
            progressManager.completeLesson(
                lessonId: lesson.lessonId,
                quizScore: quizScore,
                timeSpent: elapsed
            )
            // Award bonus XP for full lesson completion
            gamificationService?.handleLessonCompleted(
                lessonId: lesson.lessonId,
                quizScore: quizScore
            )
            // Reset so onDisappear doesn't double-count
            sessionStartTime = Date()
            phase = .completed
            Self.logger.info("Lesson '\(self.lesson.lessonId, privacy: .public)' completed")
        } else {
            phase = .active(stepIndex: index + 1)
            resetStepState()
            evaluateGate()
        }
    }

    /// Go back to the previous step.
    ///
    /// Navigating backward always succeeds if there is a previous step.
    /// The gate is re-evaluated for the new step position.
    func goToPreviousStep() {
        guard canGoBack else { return }
        let index = currentStepIndex
        phase = .active(stepIndex: index - 1)
        resetStepState()
        evaluateGate()
    }

    // MARK: - Step Completion Signals

    /// Signal that the listen step audio has finished playing.
    ///
    /// Unconditionally unlocks the gate so the learner can proceed.
    func listenCompleted() {
        gateStatus = .unlocked
    }

    /// Signal that the sing step is done with an accuracy score.
    ///
    /// Auto-unlocks if accuracy >= 0.60, otherwise stays locked.
    /// The learner can still use `singManualAdvance()` to skip.
    ///
    /// - Parameter accuracy: Singing accuracy (0.0-1.0).
    func singCompleted(accuracy: Double) {
        if accuracy >= 0.60 {
            gateStatus = .unlocked
        }
    }

    /// Signal that the user wants to manually advance past a sing step.
    ///
    /// Allows the learner to skip the singing gate without meeting
    /// the accuracy threshold. This ensures no one gets stuck.
    func singManualAdvance() {
        gateStatus = .unlocked
    }

    /// Signal that the exercise step is complete.
    ///
    /// Unlocks the gate so the learner can proceed to the next step.
    func exerciseCompleted() {
        gateStatus = .unlocked
    }

    /// Signal that the quiz step is complete with a score.
    ///
    /// Applies high-water mark to `quizScore` so repeated attempts
    /// only improve the recorded score. Always unlocks the gate.
    ///
    /// - Parameter score: Quiz score (0.0-1.0).
    func quizCompleted(score: Double) {
        quizScore = max(quizScore ?? 0.0, score)
        gateStatus = .unlocked
    }

    // MARK: - Private Methods

    /// Evaluate gate status for the current step.
    ///
    /// If the step was already completed in a previous session, the gate
    /// is always unlocked. Otherwise, the gate depends on the step type.
    private func evaluateGate() {
        guard let step = currentStep else {
            gateStatus = .unlocked
            return
        }

        // If step was already completed, always unlock
        let progress = progressManager.progress(for: lesson.lessonId)
        let flags = progress.stepCompletionFlags
        if currentStepIndex < flags.count, flags[currentStepIndex] {
            gateStatus = .unlocked
            return
        }

        switch step.stepType {
        case "intro", "read":
            gateStatus = .unlocked
        case "listen":
            gateStatus = .locked(reason: "Listen to the audio to continue")
        case "sing":
            gateStatus = .locked(reason: "Sing along to continue")
        case "exercise", "practice":
            gateStatus = .locked(reason: "Complete the exercise to continue")
        case "quiz":
            gateStatus = .locked(reason: "Answer all questions to continue")
        default:
            gateStatus = .unlocked
        }
    }

    /// Reset per-step transient state when navigating.
    ///
    /// Quiz score persists across the lesson (high-water mark),
    /// so it is not reset here.
    private func resetStepState() {
        // Quiz score persists across the lesson, don't reset it
    }
}
