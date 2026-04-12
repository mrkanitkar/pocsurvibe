import Foundation
import os.log

/// Imports lessons from JSON data, producing validated `LessonImportDTO` instances.
///
/// Lives in SVLearning (no SwiftData dependency). The app target's
/// `ContentImportManager` maps DTOs to `Lesson` @Model objects.
public struct LessonImporter: Sendable {
    private static let logger = Logger.survibe(category: "LessonImporter")

    // MARK: - Single Import

    /// Decodes and validates a single lesson from JSON data.
    ///
    /// - Parameter data: Raw JSON data conforming to the seed-lesson schema.
    /// - Returns: A validated `LessonImportDTO`.
    /// - Throws: `LessonImportError` if decoding or validation fails.
    public static func importLesson(from data: Data) throws -> LessonImportDTO {
        let dto: LessonImportDTO
        do {
            dto = try JSONDecoder().decode(LessonImportDTO.self, from: data)
        } catch {
            logger.error("Lesson JSON decoding failed: \(error, privacy: .public)")
            throw LessonImportError.decodingFailed(error.localizedDescription)
        }
        try dto.validate()
        logger.info("Imported lesson DTO: \(dto.lessonId, privacy: .public)")
        return dto
    }

    // MARK: - Batch Import

    /// Decodes and validates multiple lessons from a JSON array.
    ///
    /// - Parameter data: Raw JSON data containing an array of lesson objects.
    /// - Returns: An array of validated `LessonImportDTO` instances.
    ///   Invalid entries are logged and skipped.
    public static func importLessons(from data: Data) -> [LessonImportDTO] {
        let dtos: [LessonImportDTO]
        do {
            dtos = try JSONDecoder().decode([LessonImportDTO].self, from: data)
        } catch {
            logger.error("Lessons JSON array decoding failed: \(error, privacy: .public)")
            return []
        }

        var validated: [LessonImportDTO] = []
        for dto in dtos {
            do {
                try dto.validate()
                validated.append(dto)
            } catch {
                logger.warning("Skipped invalid lesson '\(dto.lessonId, privacy: .public)': \(error, privacy: .public)")
            }
        }
        logger.info("Imported \(validated.count)/\(dtos.count) lesson DTOs")
        return validated
    }
}
