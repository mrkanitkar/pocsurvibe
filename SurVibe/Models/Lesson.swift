import Foundation
import os
import SVCore
import SwiftData

/// Module-level logger for Lesson model decode diagnostics.
private nonisolated let lessonLogger = Logger.survibe(category: "LessonModel")

// MARK: - Supporting Types

/// A single step within a lesson.
///
/// Lessons are composed of ordered steps that guide the learner through
/// introduction, listening, singing, exercises, and quizzes.
public struct LessonStep: Codable, Equatable, Sendable {
    /// Step type: "intro", "listen", "sing", "exercise", "quiz".
    public let stepType: String

    /// Instructional content (plain text or markdown).
    public let content: String

    /// Associated song ID (if this step involves playing or listening to a song).
    public let songId: UUID?

    /// Expected duration in seconds for pacing.
    public let durationSeconds: Int?

    public init(
        stepType: String,
        content: String,
        songId: UUID? = nil,
        durationSeconds: Int? = nil
    ) {
        self.stepType = stepType
        self.content = content
        self.songId = songId
        self.durationSeconds = durationSeconds
    }
}

// MARK: - Lesson @Model

/// Represents a learning lesson in the SurVibe curriculum.
///
/// Lessons are the primary teaching unit. Each lesson contains:
/// - Learning objectives and instructions
/// - A sequence of steps (exercises, listening, practice)
/// - Links to associated songs (stored as JSON UUID arrays)
/// - Prerequisites (other lessons that must be completed first)
///
/// ## CloudKit Compatibility
/// - All fields have explicit default values or are optional.
/// - No `@Attribute(.unique)` — CloudKit does not support unique constraints.
/// - Binary data uses `@Attribute(.externalStorage)` and optional `Data?`.
///
/// ## Conflict Resolution
/// - `orderIndex`: last-write-wins.
/// - `updatedAt`: max-wins for consistency.
@Model
final class Lesson {
    // MARK: - Identifiers

    /// Unique identifier (auto-generated UUID).
    var id: UUID = UUID()

    /// Human-readable lesson ID (e.g., "lesson-01-sa-re-ga").
    var lessonId: String = ""

    // MARK: - Content

    /// Display title.
    var title: String = ""

    /// Detailed description of learning objectives.
    var lessonDescription: String = ""

    /// Difficulty level (1–5).
    var difficulty: Int = 1

    /// Ordering within curriculum (ascending).
    var orderIndex: Int = 0

    // MARK: - Prerequisites & Dependencies

    /// Lesson IDs that must be completed before this one.
    /// Stored as JSON array. Decode with `decodedPrerequisites`.
    @Attribute(.externalStorage)
    var prerequisiteLessonIds: Data?

    /// Song IDs referenced in this lesson.
    /// Stored as JSON array of UUID strings. Decode with `decodedSongIds`.
    @Attribute(.externalStorage)
    var associatedSongIds: Data?

    // MARK: - Learning Content

    /// Lesson steps as JSON-encoded `[LessonStep]`.
    /// Decode with `decodedSteps`.
    @Attribute(.externalStorage)
    var stepsData: Data?

    // MARK: - Business Logic

    /// Whether this lesson is available to free-tier users.
    var isFree: Bool = false

    // MARK: - Timestamps

    /// When this lesson was first created.
    var createdAt: Date = Date()

    /// Last modification timestamp.
    var updatedAt: Date = Date()

    // MARK: - Computed Properties

    /// Decodes prerequisite lesson IDs from the JSON blob.
    var decodedPrerequisites: [String]? {
        guard let data = prerequisiteLessonIds else { return nil }
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            let desc = error.localizedDescription
            lessonLogger.warning(
                "Failed to decode prerequisites for \(self.lessonId, privacy: .public): \(desc, privacy: .public)"
            )
            return nil
        }
    }

    /// Decodes associated song UUIDs from the JSON blob.
    var decodedSongIds: [UUID]? {
        guard let data = associatedSongIds else { return nil }
        do {
            return try JSONDecoder().decode([UUID].self, from: data)
        } catch {
            let desc = error.localizedDescription
            lessonLogger.warning(
                "Failed to decode song IDs for \(self.lessonId, privacy: .public): \(desc, privacy: .public)"
            )
            return nil
        }
    }

    /// Decodes associated song slug strings from the JSON blob.
    ///
    /// Seed content stores song references as slug strings (e.g., "twinkle-hindi-v1")
    /// rather than UUIDs. This provides access to those slug identifiers.
    var decodedAssociatedSongSlugs: [String]? {
        guard let data = associatedSongIds else { return nil }
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            let desc = error.localizedDescription
            lessonLogger.warning(
                "Failed to decode song slugs for \(self.lessonId, privacy: .public): \(desc, privacy: .public)"
            )
            return nil
        }
    }

    /// Decodes lesson steps from the JSON blob.
    var decodedSteps: [LessonStep]? {
        guard let data = stepsData else { return nil }
        do {
            return try JSONDecoder().decode([LessonStep].self, from: data)
        } catch {
            let desc = error.localizedDescription
            lessonLogger.warning(
                "Failed to decode steps for \(self.lessonId, privacy: .public): \(desc, privacy: .public)"
            )
            return nil
        }
    }

    // MARK: - Initialization

    init(
        lessonId: String = "",
        title: String = "",
        lessonDescription: String = "",
        difficulty: Int = 1,
        orderIndex: Int = 0
    ) {
        self.id = UUID()
        self.lessonId = lessonId
        self.title = title
        self.lessonDescription = lessonDescription
        self.difficulty = difficulty
        self.orderIndex = orderIndex
        self.isFree = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
