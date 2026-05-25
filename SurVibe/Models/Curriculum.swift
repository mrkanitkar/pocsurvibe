import Foundation
import os
import SVCore
import SwiftData

/// Module-level logger for Curriculum model decode diagnostics.
nonisolated private let curriculumLogger = Logger.survibe(category: "CurriculumModel")

/// A structured learning curriculum (ordered sequence of lessons).
///
/// Curriculums provide named learning paths that group lessons by theme
/// and difficulty (e.g., "Beginner Sargam Path", "Classical Raag Journey").
///
/// ## CloudKit Compatibility
/// - All fields have explicit default values or are optional.
/// - No `@Attribute(.unique)` — CloudKit does not support unique constraints.
/// - Binary data uses `@Attribute(.externalStorage)` and optional `Data?`.
///
/// ## Conflict Resolution
/// - `updatedAt`: max-wins for consistency.
/// - `lessonIds`: last-write-wins (ordering changes are infrequent).
@Model
final class Curriculum {
    // MARK: - Identifiers

    /// Unique identifier (auto-generated UUID).
    var id: UUID = UUID()

    /// Human-readable curriculum ID (e.g., "curriculum-beginner-sargam").
    var curriculumId: String = ""

    // MARK: - Content

    /// Display title.
    var title: String = ""

    /// Description of this learning path.
    var curriculumDescription: String = ""

    /// Ordered lesson IDs in this curriculum.
    /// Stored as JSON array. Decode with `decodedLessonIds`.
    @Attribute(.externalStorage) var lessonIds: Data?

    // MARK: - Difficulty Range

    /// Minimum difficulty of lessons in this curriculum (1–5).
    var minDifficulty: Int = 1

    /// Maximum difficulty of lessons in this curriculum (1–5).
    var maxDifficulty: Int = 1

    // MARK: - Timestamps

    /// When this curriculum was first created.
    var createdAt: Date = Date()

    /// Last modification timestamp.
    var updatedAt: Date = Date()

    // MARK: - Computed Properties

    /// Decodes ordered lesson IDs from the JSON blob.
    var decodedLessonIds: [String]? {
        guard let data = lessonIds else { return nil }
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            let desc = error.localizedDescription
            curriculumLogger.warning(
                "Failed to decode lesson IDs for \(self.curriculumId, privacy: .public): \(desc, privacy: .public)"
            )
            return nil
        }
    }

    /// Returns the difficulty range as a `ClosedRange`.
    var difficultyRange: ClosedRange<Int> {
        minDifficulty...maxDifficulty
    }

    // MARK: - Initialization

    init(
        curriculumId: String = "",
        title: String = "",
        curriculumDescription: String = "",
        minDifficulty: Int = 1,
        maxDifficulty: Int = 1
    ) {
        self.id = UUID()
        self.curriculumId = curriculumId
        self.title = title
        self.curriculumDescription = curriculumDescription
        self.minDifficulty = minDifficulty
        self.maxDifficulty = maxDifficulty
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
