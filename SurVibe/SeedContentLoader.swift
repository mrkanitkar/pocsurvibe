import Foundation
import SwiftData
import os.log
import SVAudio
import SVCore

/// Manages seed content loading into SwiftData with version tracking.
///
/// Uses a UserDefaults integer version to detect when new seed content
/// is available. When the stored version is lower than `currentContentVersion`,
/// the seed migration runs.
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
    /// Bump this whenever the @Model schema or bundled seed set changes.
    /// - v1–v11: legacy JSON-seeded content (Hindi/Marathi/English songs).
    /// - v12: Format unification — wipe legacy JSON-seeded songs and re-seed
    ///        only the bundled MXL imports (Sukhkarta, James Bond).
    /// - v13: T5' (2026-05-01) — Song @Model schema redesign. Dropped the
    ///        `sargamNotation` / `westernNotation` JSON blobs (Pipeline B
    ///        legacy). Added `musicXMLData` + key/time/Sa metadata fields.
    ///        v13 wipes EVERY `Song` row (including user-imported ones —
    ///        sanctioned by plan-v2 locked decision: no users yet, CloudKit
    ///        dev container will also be wiped) and re-seeds the bundled
    ///        MXL imports through the new pipeline.
    private static let currentContentVersion = 13

    /// Resource basenames (no extension) of the bundled MXL audition
    /// assets that should be imported as `Song` rows on first launch.
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
        let stored = storedContentVersion
        if stored < currentContentVersion {
            logger.info("Seed content version \(stored) < \(currentContentVersion). Migrating.")
            // T5' v13: wipe ALL Song rows (legacy seed + user imports +
            // stale MXL rows from earlier pipelines) and re-seed only the
            // bundled MXL imports. Dropping the schema fields requires the
            // store to be cleared anyway.
            wipeAllSongs(in: container)
            wipeAllSongProgress(in: container)
            importBundledMXLs(into: container)
            UserDefaults.standard.set(currentContentVersion, forKey: seedContentVersionKey)
            logger.info("Seed content migrated to v\(currentContentVersion) — bundled MXL only")
            MultiChannelLog.shared.log(
                .info,
                "SEED-WIPE v13 wiped Song + SongProgress; re-imported bundled MXLs"
            )
        } else {
            logger.info(
                "Seed content at version \(stored); current is \(currentContentVersion). Skipping seed migration."
            )
        }
    }

    /// Delete every `Song` row regardless of source. Used by v13 migration:
    /// the schema redesign drops fields that older rows persisted, so a
    /// wholesale wipe is cleaner than per-row migration.
    private static func wipeAllSongs(in container: ModelContainer) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Song>()
        let songs: [Song]
        do {
            songs = try context.fetch(descriptor)
        } catch {
            logger.error("v13 wipe (Song): fetch failed: \(error, privacy: .public)")
            return
        }
        for song in songs {
            logger.info(
                "v13 wipe: deleting song slug=\(song.slugId, privacy: .public) source=\(song.source, privacy: .public)"
            )
            context.delete(song)
        }
        if !songs.isEmpty {
            do {
                try context.save()
                MultiChannelLog.shared.log(
                    .info,
                    "SEED-WIPE v13 deleted \(songs.count) Song row(s)"
                )
            } catch {
                logger.error("v13 wipe (Song): save failed: \(error, privacy: .public)")
            }
        }
    }

    /// Delete every `SongProgress` row. Paired with `wipeAllSongs` because
    /// progress rows reference songs by slug — keeping them around after a
    /// full song wipe leaves dangling references.
    private static func wipeAllSongProgress(in container: ModelContainer) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SongProgress>()
        let rows: [SongProgress]
        do {
            rows = try context.fetch(descriptor)
        } catch {
            logger.error("v13 wipe (SongProgress): fetch failed: \(error, privacy: .public)")
            return
        }
        for row in rows {
            context.delete(row)
        }
        if !rows.isEmpty {
            do {
                try context.save()
                MultiChannelLog.shared.log(
                    .info,
                    "SEED-WIPE v13 deleted \(rows.count) SongProgress row(s)"
                )
            } catch {
                logger.error("v13 wipe (SongProgress): save failed: \(error, privacy: .public)")
            }
        }
    }

    /// Import each bundled `.mxl` audition asset as a `Song` row so the
    /// Learn-a-Song play-along has populated `midiData` /
    /// `learnerTrackIndex` on first launch.
    ///
    /// Idempotent — looks up an existing Song by `slugId` and replaces it.
    /// Errors from any individual MXL are logged but do not block the
    /// remaining imports.
    ///
    /// - Parameter container: SwiftData ModelContainer to insert into.
    private static func importBundledMXLs(into container: ModelContainer) {
        let context = ModelContext(container)
        for entry in bundledMXLImports {
            do {
                if let existing = try existingSong(slug: entry.slug, in: context) {
                    logger.info(
                        "Bundled MXL '\(entry.resource, privacy: .public)': deleting stale row before re-import"
                    )
                    context.delete(existing)
                    try context.save()
                }
                guard let url = Bundle.main.url(forResource: entry.resource, withExtension: "mxl") else {
                    logger.warning(
                        "Bundled MXL '\(entry.resource, privacy: .public)' missing from Bundle.main"
                    )
                    continue
                }
                let imported = try ContentImportManager.importMusicXMLAsSong(from: url, into: context)
                imported.slugId = entry.slug
                imported.title = displayTitle(forResource: entry.resource)
                imported.source = "bundled"
                imported.isFree = true  // Bundled MXLs are free-to-play.
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

    /// Map a bundled MXL resource basename to a human-readable display title.
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
