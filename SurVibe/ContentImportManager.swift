import Foundation
import SVCore
import SVLearning
import SwiftData
import os.log

/// Orchestrates import of seed content (songs, lessons) from JSON into SwiftData.
///
/// Maps DTOs from SVLearning to @Model objects in the app target,
/// then inserts them into the ModelContext.
///
/// ## Usage
/// ```swift
/// let summary = try ContentImportManager.importAllSeedContent(
///     into: modelContainer
/// )
/// ```
@MainActor
final class ContentImportManager {
    private static let logger = Logger.survibe(category: "ContentImportManager")

    /// Result of an import operation.
    struct ImportSummary: Sendable {
        /// Number of songs successfully imported.
        var songCount: Int = 0
        /// Number of lessons successfully imported.
        var lessonCount: Int = 0
        /// Number of curricula successfully imported.
        var curriculumCount: Int = 0
        /// Descriptions of any non-fatal errors encountered.
        var errorDescriptions: [String] = []

        /// Human-readable summary.
        var description: String {
            let counts = "Songs: \(songCount), Lessons: \(lessonCount)"
            return "\(counts), Curricula: \(curriculumCount), Errors: \(errorDescriptions.count)"
        }
    }

    // MARK: - Private DTOs

    /// Data transfer object for decoding curriculum JSON.
    ///
    /// Matches the schema in `seed-curricula.json`. Used only within
    /// `ContentImportManager` — curricula do not have an SVLearning-level
    /// importer because they are simple metadata containers.
    private struct CurriculumDTO: Codable {
        /// Unique curriculum identifier (e.g., "curriculum-sargam-foundations").
        let curriculumId: String
        /// Display title.
        let title: String
        /// Description of this learning path.
        let curriculumDescription: String
        /// Ordered lesson IDs in this curriculum.
        let lessonIds: [String]
        /// Minimum difficulty of lessons in this curriculum (1–5).
        let minDifficulty: Int
        /// Maximum difficulty of lessons in this curriculum (1–5).
        let maxDifficulty: Int
    }

    // MARK: - Import All

    /// Performs a complete seed content import from bundled JSON files.
    ///
    /// Reads `seed-songs.json` and `seed-lessons.json` from the main bundle,
    /// validates via SVLearning importers, maps to @Model objects, and inserts
    /// into the provided ModelContainer.
    ///
    /// - Parameters:
    ///   - container: SwiftData ModelContainer for insert operations.
    ///   - bundle: Bundle containing JSON resources (default: `.main`).
    /// - Returns: Summary of the import results.
    /// - Throws: If the ModelContext fails to save.
    static func importAllSeedContent(
        into container: ModelContainer,
        from bundle: Bundle = .main
    ) throws -> ImportSummary {
        logger.info("Starting seed content import")
        var summary = ImportSummary()
        let context = ModelContext(container)

        deleteExistingSeedContent(from: context)
        importSongs(from: bundle, into: context, summary: &summary)
        importLessons(from: bundle, into: context, summary: &summary)
        importCurricula(from: bundle, into: context, summary: &summary)

        try context.save()
        logger.info("Seed content saved: \(summary.description, privacy: .public)")
        return summary
    }

    /// Imports songs from the bundled JSON into the context.
    private static func importSongs(
        from bundle: Bundle,
        into context: ModelContext,
        summary: inout ImportSummary
    ) {
        guard let url = bundle.url(forResource: "seed-songs", withExtension: "json") else {
            logger.warning("seed-songs.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let songDTOs = SongImporter.importSongs(from: data)
            for dto in songDTOs {
                context.insert(mapSongDTO(dto))
                summary.songCount += 1
            }
            let count = summary.songCount
            logger.info("Imported \(count) songs")
        } catch {
            logger.error("Error reading seed-songs.json: \(error, privacy: .public)")
            summary.errorDescriptions.append("Songs: \(error.localizedDescription)")
        }
    }

    /// Imports lessons from the bundled JSON into the context.
    private static func importLessons(
        from bundle: Bundle,
        into context: ModelContext,
        summary: inout ImportSummary
    ) {
        guard let url = bundle.url(forResource: "seed-lessons", withExtension: "json") else {
            logger.warning("seed-lessons.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let lessonDTOs = LessonImporter.importLessons(from: data)
            for dto in lessonDTOs {
                context.insert(mapLessonDTO(dto))
                summary.lessonCount += 1
            }
            let count = summary.lessonCount
            logger.info("Imported \(count) lessons")
        } catch {
            logger.error("Error reading seed-lessons.json: \(error, privacy: .public)")
            summary.errorDescriptions.append("Lessons: \(error.localizedDescription)")
        }
    }

    /// Imports curricula from the bundled JSON into the context.
    private static func importCurricula(
        from bundle: Bundle,
        into context: ModelContext,
        summary: inout ImportSummary
    ) {
        guard let url = bundle.url(forResource: "seed-curricula", withExtension: "json") else {
            logger.warning("seed-curricula.json not found in bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let dtos = try JSONDecoder().decode([CurriculumDTO].self, from: data)
            for dto in dtos {
                context.insert(mapCurriculumDTO(dto))
                summary.curriculumCount += 1
            }
            let count = summary.curriculumCount
            logger.info("Imported \(count) curricula")
        } catch {
            logger.error("Error reading seed-curricula.json: \(error, privacy: .public)")
            summary.errorDescriptions.append("Curricula: \(error.localizedDescription)")
        }
    }

    /// Deletes all existing Song, Lesson, and Curriculum records before a fresh seed import.
    ///
    /// This ensures no duplicates accumulate when the seed content version
    /// is bumped and the full JSON is re-imported.
    private static func deleteExistingSeedContent(from context: ModelContext) {
        do {
            let songs = try context.fetch(FetchDescriptor<Song>())
            for song in songs {
                context.delete(song)
            }
            logger.info("Deleted \(songs.count) existing songs before re-import")
        } catch {
            logger.warning("Failed to fetch existing songs for deletion: \(error, privacy: .public)")
        }

        do {
            let lessons = try context.fetch(FetchDescriptor<Lesson>())
            for lesson in lessons {
                context.delete(lesson)
            }
            logger.info("Deleted \(lessons.count) existing lessons before re-import")
        } catch {
            logger.warning("Failed to fetch existing lessons for deletion: \(error, privacy: .public)")
        }

        do {
            let curricula = try context.fetch(FetchDescriptor<Curriculum>())
            for curriculum in curricula {
                context.delete(curriculum)
            }
            logger.info("Deleted \(curricula.count) existing curricula before re-import")
        } catch {
            logger.warning("Failed to fetch existing curricula for deletion: \(error, privacy: .public)")
        }
    }

    // MARK: - DTO → @Model Mapping

    /// Maps a `SongImportDTO` to a `Song` @Model instance.
    private static func mapSongDTO(_ dto: SongImportDTO) -> Song {
        let song = Song(
            slugId: dto.slugId,
            title: dto.title,
            artist: dto.artist,
            language: dto.language,
            difficulty: dto.difficulty,
            category: dto.category,
            ragaName: dto.ragaName ?? "",
            tempo: dto.tempo,
            durationSeconds: dto.durationSeconds
        )
        song.isFree = dto.isFree ?? false
        song.sortOrder = dto.sortOrder

        // Encode notation arrays to JSON Data blobs
        song.sargamNotation = try? JSONEncoder().encode(dto.sargamNotation)
        song.westernNotation = try? JSONEncoder().encode(dto.westernNotation)

        // Encode MIDI data from base64 if present
        if let midiString = dto.midiData, !midiString.isEmpty {
            song.midiData = Data(base64Encoded: midiString)
        }

        // Map key/time signature for staff notation
        song.keySignatureRaw = dto.keySignature ?? ""
        song.timeSignatureRaw = dto.timeSignature ?? ""

        return song
    }

    /// Maps a `LessonImportDTO` to a `Lesson` @Model instance.
    private static func mapLessonDTO(_ dto: LessonImportDTO) -> Lesson {
        let lesson = Lesson(
            lessonId: dto.lessonId,
            title: dto.title,
            lessonDescription: dto.lessonDescription,
            difficulty: dto.difficulty,
            orderIndex: dto.orderIndex
        )
        lesson.isFree = dto.isFree ?? false

        // Encode prerequisite IDs to JSON blob
        lesson.prerequisiteLessonIds = try? JSONEncoder().encode(dto.prerequisiteLessonIds ?? [])

        // Encode associated song IDs to JSON blob (stored as String slugs)
        lesson.associatedSongIds = try? JSONEncoder().encode(dto.associatedSongIds ?? [])

        // Map LessonStepDTO → LessonStep, then encode to JSON blob
        let steps = dto.steps.map { stepDTO in
            LessonStep(
                stepType: stepDTO.stepType,
                content: stepDTO.content,
                songId: nil,
                durationSeconds: stepDTO.durationSeconds
            )
        }
        lesson.stepsData = try? JSONEncoder().encode(steps)

        return lesson
    }

    /// Maps a `CurriculumDTO` to a `Curriculum` @Model instance.
    ///
    /// Encodes the ordered lesson IDs as a JSON blob for CloudKit-compatible
    /// storage in the `lessonIds` `Data?` field.
    private static func mapCurriculumDTO(_ dto: CurriculumDTO) -> Curriculum {
        let curriculum = Curriculum(
            curriculumId: dto.curriculumId,
            title: dto.title,
            curriculumDescription: dto.curriculumDescription,
            minDifficulty: dto.minDifficulty,
            maxDifficulty: dto.maxDifficulty
        )
        curriculum.lessonIds = try? JSONEncoder().encode(dto.lessonIds)
        return curriculum
    }
}
