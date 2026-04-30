import Foundation
import SwiftData
import os.log
import SVCore

/// Manages seed content loading into SwiftData with version tracking.
///
/// Uses a UserDefaults integer version to detect when new seed content
/// is available. When the stored version is lower than `currentContentVersion`,
/// all seed content is re-imported (existing entries are upserted by slug ID
/// via `ContentImportManager`).
///
/// ## Usage
/// Call from `SurVibeApp.init()` after ModelContainer is created:
/// ```swift
/// SeedContentLoader.loadSeedContentIfNeeded(into: modelContainer)
/// ```
@MainActor
final class SeedContentLoader {
    private static let logger = Logger.survibe(category: "SeedContentLoader")
    private static let seedContentVersionKey = "com.survibe.seedContentVersion"

    /// Current seed content version.
    /// Bump this whenever new songs or lessons are added to seed JSON files.
    /// - v1: Initial 3 songs (Day 3)
    /// - v2: +5 Hindi songs, +5 Marathi songs (Day 7/8)
    /// - v3: +Jana Gana Mana, enhanced Morya Morya with MIDI playback data
    /// - v4: +5 English songs (Happy Birthday, London Bridge, Ode to Joy, Amazing Grace, Für Elise Theme)
    /// - v5: +keySignatureRaw, timeSignatureRaw fields on Song model for staff notation
    /// - v6: +8 lessons (total 10), +2 curricula (Sargam Foundations, Melodic Expression)
    /// - v7: Jana Gana Mana updated with official notation in G major (G=Sa)
    /// - v8: Force re-import Jana Gana Mana (v7 written before JSON was corrected)
    /// - v9: Auto-import bundled MXL audition assets
    ///       (Sukhkarta_Dukhharta, james-bond-theme) as Songs so the
    ///       Learn-a-Song play-along path has populated `midiData` +
    ///       `learnerTrackIndices` on first launch.
    private static let currentContentVersion = 9

    /// Resource basenames (no extension) of the bundled MXL audition
    /// assets that should be imported as `Song` rows on first launch.
    /// Each entry maps the resource name to the slug used by
    /// `ContentImportManager.importMusicXMLAsSong` so we can short-circuit
    /// the import when the song already exists.
    private static let bundledMXLImports: [(resource: String, slug: String)] = [
        ("Sukhkarta_Dukhharta", "sukhkarta-dukhharta"),
        ("james-bond-theme", "james-bond-theme"),
    ]

    /// The stored seed content version from UserDefaults.
    static var storedContentVersion: Int {
        UserDefaults.standard.integer(forKey: seedContentVersionKey)
    }

    /// Loads seed content if not already at the current version.
    ///
    /// Safe to call multiple times; idempotent via version check.
    /// Runs synchronously on the main actor (called during app init).
    ///
    /// - Parameter container: SwiftData ModelContainer for inserts.
    static func loadSeedContentIfNeeded(into container: ModelContainer) {
        guard storedContentVersion < currentContentVersion else {
            logger.info("Seed content at version \(storedContentVersion); current is \(currentContentVersion). Skipping.")
            return
        }

        logger.info("Seed content version \(storedContentVersion) < \(currentContentVersion). Importing.")

        do {
            let summary = try ContentImportManager.importAllSeedContent(into: container)
            importBundledMXLs(into: container)
            UserDefaults.standard.set(currentContentVersion, forKey: seedContentVersionKey)
            logger.info("Seed content loaded successfully (v\(currentContentVersion)): \(summary.description, privacy: .public)")
        } catch {
            logger.error(
                "Seed content loading failed: \(error, privacy: .public). App will continue without seed data."
            )
        }
    }

    /// Import each bundled `.mxl` audition asset as a `Song` row so the
    /// Learn-a-Song play-along has populated `midiData` /
    /// `learnerTrackIndex` on first launch.
    ///
    /// Idempotent — looks up an existing Song by `slugId` and skips the
    /// import when one is already present. Errors from any individual
    /// MXL are logged but do not block the seed flow; the JSON-seeded
    /// songs remain available regardless.
    ///
    /// - Parameter container: SwiftData ModelContainer to insert into.
    private static func importBundledMXLs(into container: ModelContainer) {
        let context = ModelContext(container)
        for entry in bundledMXLImports {
            do {
                if let existing = try existingSong(slug: entry.slug, in: context) {
                    // Upgrade-in-place: ensure existing rows have isFree=true
                    // (older seeds shipped before isFree was set).
                    if !existing.isFree {
                        existing.isFree = true
                        try context.save()
                        logger.info("Bundled MXL '\(entry.resource, privacy: .public)': flipped isFree=true")
                    } else {
                        logger.info("Bundled MXL '\(entry.resource, privacy: .public)' already imported; skipping")
                    }
                    continue
                }
                guard let url = Bundle.main.url(forResource: entry.resource, withExtension: "mxl") else {
                    logger.warning(
                        "Bundled MXL '\(entry.resource, privacy: .public)' missing from Bundle.main"
                    )
                    continue
                }
                let imported = try ContentImportManager.importMusicXMLAsSong(from: url, into: context)
                // Override the slug + display title that `makeSongStub`
                // derives from the file name with our canonical kebab-case
                // slug + "Title Case" display, so the row matches what the
                // SongLibrary expects.
                imported.slugId = entry.slug
                imported.title = displayTitle(forResource: entry.resource)
                imported.source = "bundled"
                imported.isFree = true  // Bundled MXLs are free-to-play (no premium gate).
                try context.save()
                logger.info(
                    "Imported bundled MXL '\(entry.resource, privacy: .public)' as Song slug=\(entry.slug, privacy: .public)"
                )
            } catch {
                logger.error(
                    "Failed to import bundled MXL '\(entry.resource, privacy: .public)': \(error, privacy: .public)"
                )
            }
        }
    }

    /// Look up an existing Song by slug. Returns `nil` when none matches.
    private static func existingSong(slug: String, in context: ModelContext) throws -> Song? {
        var descriptor = FetchDescriptor<Song>(
            predicate: #Predicate { $0.slugId == slug }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Map a bundled MXL resource basename to a human-readable display
    /// title. Falls back to the basename with underscores replaced by
    /// spaces.
    private static func displayTitle(forResource resource: String) -> String {
        switch resource {
        case "Sukhkarta_Dukhharta": return "Sukhkarta Dukhharta"
        case "james-bond-theme": return "James Bond Theme"
        default: return resource.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// Resets the seed content version flag after a schema migration.
    ///
    /// Called by `SurVibeApp` when `deleteSwiftDataStore()` wipes the store,
    /// ensuring seed content is re-imported into the empty store. Safe to call
    /// in both Debug and Release builds.
    static func resetForSchemaMigration() {
        UserDefaults.standard.removeObject(forKey: seedContentVersionKey)
        logger.info("Seed content version reset for schema migration")
    }

    /// Resets the seed content version flag (for testing/debug).
    ///
    /// - Warning: Use only in debug builds or testing contexts.
    static func resetSeedContentFlag() {
        #if DEBUG
            UserDefaults.standard.removeObject(forKey: seedContentVersionKey)
            logger.info("Seed content version flag reset (DEBUG only)")
        #else
            logger.warning("resetSeedContentFlag called in non-DEBUG build; ignoring")
        #endif
    }
}
