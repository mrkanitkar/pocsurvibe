import Testing
import Foundation
import SwiftUI
@testable import SurVibe

struct AppThemeMigrationTests {

    private static func clearUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "appThemePreset")
        UserDefaults.standard.removeObject(forKey: "appThemePopEra")
        UserDefaults.standard.removeObject(forKey: "appThemeMigratedV2")
    }

    @Test @MainActor func legacyImmersiveMigratesToImmersiveBars() {
        Self.clearUserDefaults()
        UserDefaults.standard.set("immersive", forKey: "appThemePreset")

        let manager = AppThemeManager(colorScheme: .light)

        #expect(manager.currentPreset == .immersiveBars)
        #expect(UserDefaults.standard.bool(forKey: "appThemeMigratedV2"))
    }

    @Test @MainActor func legacySargamGlassMigratesToSargamGlassBars() {
        Self.clearUserDefaults()
        UserDefaults.standard.set("sargamGlass", forKey: "appThemePreset")

        let manager = AppThemeManager(colorScheme: .light)

        #expect(manager.currentPreset == .sargamGlassBars)
    }

    @Test @MainActor func legacyMidnightMigratesToMidnightBars() {
        Self.clearUserDefaults()
        UserDefaults.standard.set("midnight", forKey: "appThemePreset")

        let manager = AppThemeManager(colorScheme: .light)

        #expect(manager.currentPreset == .midnightBars)
    }

    @Test @MainActor func legacySynthesiaMigratesToImmersiveBars() {
        Self.clearUserDefaults()
        UserDefaults.standard.set("synthesia", forKey: "appThemePreset")

        let manager = AppThemeManager(colorScheme: .light)

        #expect(manager.currentPreset == .immersiveBars)
    }

    @Test @MainActor func legacyNeonRhythmStaysNeonRhythm() {
        Self.clearUserDefaults()
        UserDefaults.standard.set("neonRhythm", forKey: "appThemePreset")

        let manager = AppThemeManager(colorScheme: .light)

        #expect(manager.currentPreset == .neonRhythm)
    }

    @Test @MainActor func firstLaunchDefaultsToSargamGlassBars() {
        Self.clearUserDefaults()

        let manager = AppThemeManager(colorScheme: .light)

        #expect(manager.currentPreset == .sargamGlassBars)
    }

    @Test @MainActor func migrationRunsOnceOnly() {
        Self.clearUserDefaults()
        UserDefaults.standard.set("immersive", forKey: "appThemePreset")

        _ = AppThemeManager(colorScheme: .light)

        // Manually set a newer preset
        UserDefaults.standard.set("sargamGlassBars", forKey: "appThemePreset")

        let manager2 = AppThemeManager(colorScheme: .light)

        // Should not re-migrate (already migrated flag is set)
        #expect(manager2.currentPreset == .sargamGlassBars)
    }
}
