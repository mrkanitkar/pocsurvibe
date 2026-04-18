import Foundation
import SwiftUI
import Testing
@testable import SurVibe

/// Tests for the PopEra enum and the new v2 AppThemePreset cases.
///
/// Verifies that the nested `PopEra` enum enumerates all 5 eras with
/// stable raw values, and that the new bar-variant / Pop Era presets
/// are declared on `AppThemePreset` with the expected user-visible set.
struct AppThemePopEraTests {

    @Test func fivePopErasExist() {
        #expect(PopEra.allCases.count == 5)
    }

    @Test func popEraRawValuesAreStable() {
        #expect(PopEra.taylor.rawValue == "taylor")
        #expect(PopEra.olivia.rawValue == "olivia")
        #expect(PopEra.sabrina.rawValue == "sabrina")
        #expect(PopEra.chappell.rawValue == "chappell")
        #expect(PopEra.brat.rawValue == "brat")
    }

    @Test func popEraDisplayNamesAreNonEmpty() {
        for era in PopEra.allCases {
            #expect(!era.displayName.isEmpty)
        }
    }

    @Test func userVisibleCasesHasNinePresets() {
        // All 9 themes are first-class — both Bars and Drop play-along styles
        // are user-selectable. Pop Era's 5 era sub-variants are exposed via the
        // inline era picker inside the Pop Era card, not as separate presets.
        #expect(AppThemePreset.userVisibleCases.count == 9)
    }

    @Test func allCasesHasNineTotal() {
        // Pin the total (5 legacy + 4 new v2). If someone adds or removes a case,
        // this test catches it — forcing an intentional update to userVisibleCases
        // and any switch statements.
        #expect(AppThemePreset.allCases.count == 9)
    }

    @Test func newPresetRawValuesAreStable() {
        // Raw values persist in UserDefaults — renaming any of these would
        // silently migrate users to an unrelated theme on upgrade.
        #expect(AppThemePreset.sargamGlassBars.rawValue == "sargamGlassBars")
        #expect(AppThemePreset.immersiveBars.rawValue == "immersiveBars")
        #expect(AppThemePreset.midnightBars.rawValue == "midnightBars")
        #expect(AppThemePreset.popEra.rawValue == "popEra")
    }

    @Test @MainActor func setEraUpdatesResolvedAndPersists() {
        UserDefaults.standard.removeObject(forKey: "appThemePopEra")
        let manager = AppThemeManager(colorScheme: .light)
        manager.apply(.popEra)

        let initialAccent = manager.resolved.eraAccentColor

        manager.setEra(.brat)

        #expect(manager.popEra == .brat)
        #expect(manager.resolved.eraAccentColor != initialAccent)
        #expect(UserDefaults.standard.string(forKey: "appThemePopEra") == "brat")
    }

    @Test @MainActor func setEraOnNonPopEraDoesNotMutateResolved() {
        let manager = AppThemeManager(colorScheme: .light)
        manager.apply(.sargamGlassBars)
        let before = manager.resolved.accentColor
        manager.setEra(.brat)
        #expect(manager.resolved.accentColor == before)
    }
}
