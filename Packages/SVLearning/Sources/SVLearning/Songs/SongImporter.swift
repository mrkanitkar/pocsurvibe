import Foundation
import os.log

/// Imports songs from JSON data, producing validated `SongImportDTO` instances.
///
/// Lives in SVLearning (no SwiftData dependency). The app target's
/// `ContentImportManager` maps DTOs to `Song` @Model objects.
public struct SongImporter: Sendable {
    private static let logger = Logger.survibe(category: "SongImporter")

    // MARK: - Single Import

    /// Decodes and validates a single song from JSON data.
    ///
    /// - Parameter data: Raw JSON data conforming to the seed-song schema.
    /// - Returns: A validated `SongImportDTO`.
    /// - Throws: `SongImportError` if decoding or validation fails.
    public static func importSong(from data: Data) throws -> SongImportDTO {
        let dto: SongImportDTO
        do {
            dto = try JSONDecoder().decode(SongImportDTO.self, from: data)
        } catch {
            logger.error("Song JSON decoding failed: \(error, privacy: .public)")
            throw SongImportError.decodingFailed(error.localizedDescription)
        }
        try dto.validate()
        logger.info("Imported song DTO: \(dto.slugId, privacy: .public)")
        return dto
    }

    // MARK: - Batch Import

    /// Decodes and validates multiple songs from a JSON array.
    ///
    /// - Parameter data: Raw JSON data containing an array of song objects.
    /// - Returns: An array of validated `SongImportDTO` instances.
    ///   Invalid entries are logged and skipped.
    public static func importSongs(from data: Data) -> [SongImportDTO] {
        let dtos: [SongImportDTO]
        do {
            dtos = try JSONDecoder().decode([SongImportDTO].self, from: data)
        } catch {
            logger.error("Songs JSON array decoding failed: \(error, privacy: .public)")
            return []
        }

        var validated: [SongImportDTO] = []
        for dto in dtos {
            do {
                try dto.validate()
                validated.append(dto)
            } catch {
                logger.warning("Skipped invalid song '\(dto.slugId, privacy: .public)': \(error, privacy: .public)")
            }
        }
        logger.info("Imported \(validated.count)/\(dtos.count) song DTOs")
        return validated
    }
}
