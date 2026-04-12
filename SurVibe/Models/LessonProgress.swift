import Foundation
import os
import SVCore
import SwiftData

private let lpLogger = Logger.survibe(category: "LessonProgressModel")

/// Tracks lesson completion progress. One-way flag: once completed, stays completed.
///
/// Each `LessonProgress` record corresponds to a single lesson and stores:
/// - Completion state (one-way: once `true`, never reverts)
/// - Step-level progress with a resume point (`currentStepIndex`)
/// - Best quiz score using high-water mark conflict resolution
/// - Cumulative time spent across all sessions
/// - Per-step completion flags as a JSON-encoded `[Bool]` blob
///
/// ## CloudKit Compatibility
/// - All fields have explicit default values or are optional.
/// - `stepCompletions` uses `@Attribute(.externalStorage)` for binary Data.
/// - `bestQuizScore` uses high-water mark (max-wins) on sync conflicts.
/// - `isCompleted` is a one-way flag (false->true, never reverts).
@Model
final class LessonProgress {
    // MARK: - Identifiers

    /// Unique identifier (auto-generated UUID).
    var id: UUID = UUID()

    /// The lesson ID this progress tracks (matches `Lesson.lessonId`).
    var lessonId: String = ""

    /// Display title of the tracked lesson (denormalized for convenience).
    var lessonTitle: String = ""

    // MARK: - Completion State

    /// Whether the lesson is completed. One-way flag: once `true`, stays `true`.
    var isCompleted: Bool = false

    /// Timestamp when the lesson was completed. `nil` if not yet completed.
    var completedAt: Date?

    /// Overall progress as a fraction (0.0–1.0).
    var progressPercent: Double = 0.0

    // MARK: - Step Tracking

    /// Zero-based index of the current step the learner should resume from.
    ///
    /// Updated when a step is completed. Used to restore position
    /// when the learner returns to a partially completed lesson.
    var currentStepIndex: Int = 0

    /// Per-step completion flags stored as a JSON-encoded `[Bool]`.
    ///
    /// Stored as an opaque binary blob for CloudKit compatibility.
    /// Use `stepCompletionFlags` to decode and `updateStepCompletions(_:)` to encode.
    @Attribute(.externalStorage)
    var stepCompletions: Data?

    // MARK: - Scoring & Time

    /// Best quiz score achieved (0.0–1.0). Uses high-water mark: only increases.
    var bestQuizScore: Double = 0.0

    /// Cumulative time spent on this lesson across all sessions, in seconds.
    var totalTimeSpent: Double = 0.0

    // MARK: - Timestamps

    /// When this lesson was last accessed by the learner.
    var lastAccessedAt: Date = Date()

    // MARK: - Computed Properties

    /// Decodes step completion flags from the stored JSON blob.
    ///
    /// Returns an empty array if `stepCompletions` is `nil` or cannot be decoded.
    var stepCompletionFlags: [Bool] {
        guard let data = stepCompletions else { return [] }
        do {
            return try JSONDecoder().decode([Bool].self, from: data)
        } catch {
            lpLogger.warning(
                """
                Failed to decode stepCompletions for lesson \
                \(self.lessonId, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """
            )
            return []
        }
    }

    // MARK: - Initialization

    /// Creates a new progress record for a lesson.
    ///
    /// All fields initialize to their "not started" defaults.
    ///
    /// - Parameters:
    ///   - lessonId: The lesson identifier to track progress for.
    ///   - lessonTitle: Display title of the lesson.
    init(
        lessonId: String = "",
        lessonTitle: String = ""
    ) {
        self.id = UUID()
        self.lessonId = lessonId
        self.lessonTitle = lessonTitle
        self.isCompleted = false
        self.progressPercent = 0.0
        self.currentStepIndex = 0
        self.bestQuizScore = 0.0
        self.totalTimeSpent = 0.0
        self.lastAccessedAt = Date()
    }

    // MARK: - Methods

    /// Mark lesson as completed (one-way flag -- cannot be uncompleted).
    func markCompleted() {
        guard !isCompleted else { return }
        isCompleted = true
        completedAt = Date()
        progressPercent = 1.0
    }

    /// Encodes and stores step completion flags as JSON data.
    ///
    /// - Parameter flags: Array of booleans, one per step, indicating completion.
    func updateStepCompletions(_ flags: [Bool]) {
        stepCompletions = try? JSONEncoder().encode(flags)
    }
}
