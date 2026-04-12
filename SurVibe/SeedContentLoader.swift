import Foundation
import SwiftData
import os.log

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
    private static let logger = Logger(subsystem: "com.survibe", category: "SeedContentLoader")
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
    private static let currentContentVersion = 8

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
            UserDefaults.standard.set(currentContentVersion, forKey: seedContentVersionKey)
            logger.info("Seed content loaded successfully (v\(currentContentVersion)): \(summary.description)")
        } catch {
            logger.error("Seed content loading failed: \(error). App will continue without seed data.")
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
