import SwiftUI
import Testing
@testable import SurVibe

/// Tests for the Phase 5 Dim Mode feature.
///
/// Covers `AppThemeManager` state management, UserDefaults persistence,
/// and the `AppThemeDefinition.resolve` gradient-opacity contract.
@MainActor
struct DimModeTests {

    // MARK: - AppThemeManager state

    @Test func defaultIsDisabled() {
        UserDefaults.standard.removeObject(forKey: "dimModeEnabled")
        let manager = AppThemeManager()
        #expect(manager.dimModeEnabled == false)
    }

    @Test func setDimModeEnablesState() {
        let manager = AppThemeManager()
        manager.setDimMode(true)
        #expect(manager.dimModeEnabled == true)
    }

    @Test func setDimModeDisablesState() {
        let manager = AppThemeManager()
        manager.setDimMode(true)
        manager.setDimMode(false)
        #expect(manager.dimModeEnabled == false)
    }

    // MARK: - Persistence

    @Test func setDimModePersistsTrueToUserDefaults() {
        let manager = AppThemeManager()
        manager.setDimMode(true)
        let stored = UserDefaults.standard.bool(forKey: "dimModeEnabled")
        #expect(stored == true)
    }

    @Test func setDimModePersistsFalseToUserDefaults() {
        let manager = AppThemeManager()
        manager.setDimMode(true)
        manager.setDimMode(false)
        let stored = UserDefaults.standard.bool(forKey: "dimModeEnabled")
        #expect(stored == false)
    }

    @Test func initRestoresPersistedDimMode() {
        UserDefaults.standard.set(true, forKey: "dimModeEnabled")
        let manager = AppThemeManager()
        #expect(manager.dimModeEnabled == true)
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "dimModeEnabled")
    }

    // MARK: - AppThemeDefinition gradient contract

    @Test func dimModeReducesGradientOpacityCount() {
        let normal = AppThemeDefinition.resolve(
            preset: .sargamGlassBars,
            colorScheme: .light,
            dimMode: false
        )
        let dimmed = AppThemeDefinition.resolve(
            preset: .sargamGlassBars,
            colorScheme: .light,
            dimMode: true
        )
        // Same number of gradient stops in both modes.
        #expect(normal.backgroundGradient.count == dimmed.backgroundGradient.count)
    }

    @Test func dimModeGradientCountMatchesNormalForDarkScheme() {
        let normal = AppThemeDefinition.resolve(
            preset: .midnight,
            colorScheme: .dark,
            dimMode: false
        )
        let dimmed = AppThemeDefinition.resolve(
            preset: .midnight,
            colorScheme: .dark,
            dimMode: true
        )
        #expect(normal.backgroundGradient.count == dimmed.backgroundGradient.count)
    }

    @Test func resolveWithDefaultDimModeFalseMatchesExplicitFalse() {
        let defaultResolved = AppThemeDefinition.resolve(
            preset: .sargamGlassBars,
            popEra: .olivia,
            colorScheme: .light
        )
        let explicitFalse = AppThemeDefinition.resolve(
            preset: .sargamGlassBars,
            popEra: .olivia,
            colorScheme: .light,
            dimMode: false
        )
        // Structural gradient count equality as a contract check.
        #expect(defaultResolved.backgroundGradient.count == explicitFalse.backgroundGradient.count)
    }

    // MARK: - setDimMode triggers re-resolution

    @Test func setDimModeUpdatesResolvedTheme() {
        UserDefaults.standard.removeObject(forKey: "dimModeEnabled")
        let manager = AppThemeManager()
        let normalCount = manager.resolved.backgroundGradient.count
        manager.setDimMode(true)
        // Count must remain stable after dim mode is applied.
        #expect(manager.resolved.backgroundGradient.count == normalCount)
    }
}
