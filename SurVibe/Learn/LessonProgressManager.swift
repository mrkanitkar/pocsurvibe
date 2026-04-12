import Foundation
import os.log
import SVCore
import SwiftData

/// Manages lesson progress tracking, prerequisite validation, and curriculum completion.
///
/// `LessonProgressManager` is the single source of truth for all lesson progress
/// operations. It wraps a `ModelContext` and provides:
/// - Fetching or creating progress records for individual lessons
/// - Step-level completion tracking with resume-point advancement
/// - Lesson completion with high-water-mark quiz scoring
/// - Prerequisite checking to determine lesson unlock status
/// - Curriculum-level progress aggregation
/// - "Continue Learning" recommendations based on recent activity
///
/// ## Thread Safety
/// Isolated to `@MainActor` — all SwiftData operations run on the main actor.
///
/// ## Error Handling
/// SwiftData errors are caught and logged via `os.Logger`. Methods return
/// safe defaults (empty progress, `false`, `0.0`) when queries fail.
@MainActor
@Observable
final class LessonProgressManager {
    // MARK: - Properties

    /// The SwiftData model context for all persistence operations.
    private let modelContext: ModelContext

    /// Logger for progress-related operations.
    private static let logger = Logger.survibe(category: "LessonProgress")

    // MARK: - Initialization

    /// Creates a new progress manager backed by the given model context.
    ///
    /// - Parameter modelContext: The SwiftData context used for all queries and mutations.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Single Lesson Progress

    /// Fetches the existing progress record for a lesson, or creates one if none exists.
    ///
    /// When a new record is created it is immediately inserted into the model context.
    /// The caller receives a live, context-managed object.
    ///
    /// - Parameter lessonId: The lesson identifier to look up.
    /// - Returns: The existing or newly created `LessonProgress` for the given lesson.
    func progress(for lessonId: String) -> LessonProgress {
        do {
            let descriptor = FetchDescriptor<LessonProgress>(
                predicate: #Predicate { $0.lessonId == lessonId }
            )
            let results = try modelContext.fetch(descriptor)
            if let existing = results.first {
                return existing
            }
        } catch {
            Self.logger.error("Failed to fetch progress for lesson '\(lessonId, privacy: .public)': \(error, privacy: .public)")
        }

        // Not found or fetch failed — create a new record
        let newProgress = LessonProgress(lessonId: lessonId)
        modelContext.insert(newProgress)
        Self.logger.info("Created new progress record for lesson '\(lessonId, privacy: .public)'")
        return newProgress
    }

    /// Marks a specific step as completed and advances the resume point.
    ///
    /// Updates the `stepCompletions` flags array to mark the given index as `true`,
    /// advances `currentStepIndex` to the next incomplete step (or the end),
    /// recalculates `progressPercent`, and updates `lastAccessedAt`.
    ///
    /// - Parameters:
    ///   - lessonId: The lesson identifier.
    ///   - stepIndex: Zero-based index of the completed step.
    ///   - totalSteps: Total number of steps in the lesson.
    func completeStep(lessonId: String, stepIndex: Int, totalSteps: Int) {
        guard totalSteps > 0, stepIndex >= 0, stepIndex < totalSteps else {
            Self.logger.warning(
                "Invalid step parameters: stepIndex=\(stepIndex), totalSteps=\(totalSteps)"
            )
            return
        }

        let record = progress(for: lessonId)

        // Decode or initialize flags array
        var flags = record.stepCompletionFlags
        if flags.count < totalSteps {
            flags.append(contentsOf: Array(repeating: false, count: totalSteps - flags.count))
        }

        flags[stepIndex] = true
        record.updateStepCompletions(flags)

        // Advance currentStepIndex to the next incomplete step
        let completedCount = flags.filter { $0 }.count
        if let nextIncomplete = flags.firstIndex(where: { !$0 }) {
            record.currentStepIndex = nextIncomplete
        } else {
            // All steps done — point past the end
            record.currentStepIndex = totalSteps
        }

        // Update progress percentage
        record.progressPercent = Double(completedCount) / Double(totalSteps)
        record.lastAccessedAt = Date()

        save()

        let pct = record.progressPercent
        Self.logger.info(
            "Step \(stepIndex) completed for '\(lessonId, privacy: .public)' — \(pct, format: .fixed(precision: 2))"
        )
    }

    /// Finalizes lesson completion with an optional quiz score and session time.
    ///
    /// Calls `markCompleted()` on the progress record (one-way flag).
    /// Applies high-water mark to `bestQuizScore` — only stores the value
    /// if it exceeds the existing best. Adds the session time to `totalTimeSpent`.
    ///
    /// - Parameters:
    ///   - lessonId: The lesson identifier.
    ///   - quizScore: Optional quiz score (0.0–1.0). Applies high-water mark.
    ///   - timeSpent: Duration of the final session in seconds.
    func completeLesson(lessonId: String, quizScore: Double?, timeSpent: TimeInterval) {
        let record = progress(for: lessonId)

        record.markCompleted()

        // High-water mark for quiz score
        if let score = quizScore {
            let clampedScore = min(max(score, 0.0), 1.0)
            record.bestQuizScore = max(record.bestQuizScore, clampedScore)
        }

        record.totalTimeSpent += max(timeSpent, 0)
        record.lastAccessedAt = Date()

        save()

        let quiz = quizScore ?? -1
        let total = record.totalTimeSpent
        Self.logger.info(
            """
            Lesson '\(lessonId, privacy: .public)' done \
            quiz=\(quiz, format: .fixed(precision: 2)) \
            time=\(total, format: .fixed(precision: 1))s
            """
        )
    }

    /// Adds elapsed session time to a lesson's cumulative total.
    ///
    /// - Parameters:
    ///   - lessonId: The lesson identifier.
    ///   - seconds: Duration to add, in seconds. Negative values are ignored.
    func addTimeSpent(lessonId: String, seconds: TimeInterval) {
        guard seconds > 0 else { return }

        let record = progress(for: lessonId)
        record.totalTimeSpent += seconds
        record.lastAccessedAt = Date()

        save()
    }

    // MARK: - Prerequisite Logic

    /// Checks whether all prerequisites for a lesson are completed.
    ///
    /// A lesson is considered unlocked if:
    /// - It has no prerequisites (`decodedPrerequisites` is `nil` or empty), OR
    /// - Every prerequisite lesson ID has a `LessonProgress` with `isCompleted == true`.
    ///
    /// - Parameter lesson: The lesson to check.
    /// - Returns: `true` if the lesson is unlocked and available for the learner.
    func isLessonUnlocked(lesson: Lesson) -> Bool {
        guard let prerequisites = lesson.decodedPrerequisites, !prerequisites.isEmpty else {
            return true
        }

        for prereqId in prerequisites {
            let record = progress(for: prereqId)
            if !record.isCompleted {
                return false
            }
        }

        return true
    }

    /// Finds the first incomplete prerequisite lesson for navigation.
    ///
    /// Iterates through the lesson's prerequisite IDs in order and returns
    /// the first `Lesson` whose progress is not yet completed. Useful for
    /// a "Go to prerequisite" button.
    ///
    /// - Parameters:
    ///   - lesson: The lesson whose prerequisites to check.
    ///   - allLessons: All available lessons to search through.
    /// - Returns: The first incomplete prerequisite `Lesson`, or `nil` if all are met.
    func firstIncompletePrerequisite(for lesson: Lesson, allLessons: [Lesson]) -> Lesson? {
        guard let prerequisites = lesson.decodedPrerequisites, !prerequisites.isEmpty else {
            return nil
        }

        let lessonsByLessonId = Dictionary(
            uniqueKeysWithValues: allLessons.map { ($0.lessonId, $0) }
        )

        for prereqId in prerequisites {
            let record = progress(for: prereqId)
            if !record.isCompleted, let prereqLesson = lessonsByLessonId[prereqId] {
                return prereqLesson
            }
        }

        return nil
    }

    // MARK: - Curriculum Progress

    /// Calculates overall progress (0.0–1.0) for a curriculum.
    ///
    /// Counts the number of completed lessons in the curriculum and divides
    /// by the total. Returns `0.0` if the curriculum has no lessons.
    ///
    /// - Parameter curriculum: The curriculum to evaluate.
    /// - Returns: Progress fraction from 0.0 (not started) to 1.0 (fully completed).
    func curriculumProgress(curriculum: Curriculum) -> Double {
        guard let lessonIds = curriculum.decodedLessonIds, !lessonIds.isEmpty else {
            return 0.0
        }

        let completed = lessonIds.filter { progress(for: $0).isCompleted }.count
        return Double(completed) / Double(lessonIds.count)
    }

    /// Checks whether all lessons in a curriculum are completed.
    ///
    /// - Parameter curriculum: The curriculum to check.
    /// - Returns: `true` if every lesson in the curriculum is completed.
    func isCurriculumCompleted(curriculum: Curriculum) -> Bool {
        guard let lessonIds = curriculum.decodedLessonIds, !lessonIds.isEmpty else {
            return false
        }

        return lessonIds.allSatisfy { progress(for: $0).isCompleted }
    }

    /// Finds the next incomplete and unlocked lesson in a curriculum.
    ///
    /// Iterates through the curriculum's lesson IDs in order and returns
    /// the first lesson that is both not completed and has all prerequisites met.
    ///
    /// - Parameters:
    ///   - curriculum: The curriculum to search.
    ///   - allLessons: All available lessons to match against.
    /// - Returns: The next actionable `Lesson`, or `nil` if all are completed or locked.
    func nextLesson(in curriculum: Curriculum, allLessons: [Lesson]) -> Lesson? {
        guard let lessonIds = curriculum.decodedLessonIds, !lessonIds.isEmpty else {
            return nil
        }

        let lessonsByLessonId = Dictionary(
            uniqueKeysWithValues: allLessons.map { ($0.lessonId, $0) }
        )

        for lessonId in lessonIds {
            let record = progress(for: lessonId)
            if !record.isCompleted, let lesson = lessonsByLessonId[lessonId] {
                if isLessonUnlocked(lesson: lesson) {
                    return lesson
                }
            }
        }

        return nil
    }

    /// Counts the number of completed lessons within a curriculum.
    ///
    /// - Parameter curriculum: The curriculum to evaluate.
    /// - Returns: Number of completed lessons. Returns `0` if the curriculum has no lessons.
    func completedLessonCount(curriculum: Curriculum) -> Int {
        guard let lessonIds = curriculum.decodedLessonIds else {
            return 0
        }

        return lessonIds.filter { progress(for: $0).isCompleted }.count
    }

    // MARK: - Recommendations

    /// Finds the most recently accessed incomplete lesson for a "Continue Learning" card.
    ///
    /// Queries all `LessonProgress` records that are not completed and have a
    /// `currentStepIndex > 0` (meaning the learner has started at least one step).
    /// Returns the most recently accessed one, paired with its `Lesson` model.
    ///
    /// - Parameter allLessons: All available lessons to match against.
    /// - Returns: A tuple of the lesson and its progress, or `nil` if no in-progress lesson exists.
    func continueLesson(allLessons: [Lesson]) -> (lesson: Lesson, progress: LessonProgress)? {
        do {
            var descriptor = FetchDescriptor<LessonProgress>(
                predicate: #Predicate { !$0.isCompleted && $0.currentStepIndex > 0 },
                sortBy: [SortDescriptor(\LessonProgress.lastAccessedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1

            let results = try modelContext.fetch(descriptor)

            guard let topProgress = results.first else {
                return nil
            }

            let lessonsByLessonId = Dictionary(
                uniqueKeysWithValues: allLessons.map { ($0.lessonId, $0) }
            )

            if let matchedLesson = lessonsByLessonId[topProgress.lessonId] {
                return (lesson: matchedLesson, progress: topProgress)
            }

            Self.logger.warning(
                "Progress record exists for lesson '\(topProgress.lessonId, privacy: .public)' but no matching Lesson found"
            )
            return nil
        } catch {
            Self.logger.error("Failed to fetch continue-lesson progress: \(error, privacy: .public)")
            return nil
        }
    }

    // MARK: - Private Methods

    /// Persists pending changes in the model context.
    ///
    /// Logs an error if the save fails but does not throw — callers
    /// are not expected to handle persistence failures directly.
    private func save() {
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save model context: \(error, privacy: .public)")
        }
    }
}
