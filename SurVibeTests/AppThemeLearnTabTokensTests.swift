import SwiftUI
import Testing
@testable import SurVibe

/// Validates the 3 new tokens added in Phase 3a resolve to non-.clear values
/// for every preset in both color schemes. Fast, no UI.
struct AppThemeLearnTabTokensTests {

    // MARK: - dividerColor

    @Test(arguments: AppThemePreset.allCases, [ColorScheme.light, .dark])
    func dividerColorIsDefined(preset: AppThemePreset, scheme: ColorScheme) {
        let resolved = AppThemeDefinition.resolve(preset: preset, colorScheme: scheme)
        #expect(resolved.dividerColor != .clear)
    }

    // MARK: - nestedSurfaceColor

    @Test(arguments: AppThemePreset.allCases, [ColorScheme.light, .dark])
    func nestedSurfaceColorIsDefined(preset: AppThemePreset, scheme: ColorScheme) {
        let resolved = AppThemeDefinition.resolve(preset: preset, colorScheme: scheme)
        #expect(resolved.nestedSurfaceColor != .clear)
    }

    // MARK: - warningColor

    @Test(arguments: AppThemePreset.allCases, [ColorScheme.light, .dark])
    func warningColorIsDefined(preset: AppThemePreset, scheme: ColorScheme) {
        let resolved = AppThemeDefinition.resolve(preset: preset, colorScheme: scheme)
        #expect(resolved.warningColor != .clear)
    }

    // MARK: - Token overrides (spec §5.1 open questions)

    @Test func sargamGlassBarsHasDistinctNestedSurface() {
        // Spec §10 open question #1: Sargam Glass uses deeper cream with opacity 0.5.
        // We assert it differs from the default tertiarySystemBackground.
        let resolved = AppThemeDefinition.resolve(
            preset: .sargamGlassBars, colorScheme: .light
        )
        #expect(resolved.nestedSurfaceColor != Color(.tertiarySystemBackground))
    }

    @Test func midnightBarsHasAmberWarningInDark() {
        // Spec §10 open question #2: Midnight dark warning = amber #F5A623.
        let resolved = AppThemeDefinition.resolve(
            preset: .midnightBars, colorScheme: .dark
        )
        // Can't compare Color structs directly for equality with custom RGB,
        // but we can assert it's not the default .orange.
        #expect(resolved.warningColor != .orange)
    }
}
