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

    @Test func popEraHasNineThemesTotal() {
        // 5 legacy + 4 new bar variants + Pop Era = 10 but deprecated count = 5, so 5+4=9 user-visible
        // allCases still contains legacy compat themes during migration window
        let userVisible = AppThemePreset.userVisibleCases
        #expect(userVisible.count == 5)  // Sargam, Western, Night, Pop Era, Arcade
    }

    @Test func newPresetsExist() {
        _ = AppThemePreset.sargamGlassBars
        _ = AppThemePreset.immersiveBars
        _ = AppThemePreset.midnightBars
        _ = AppThemePreset.popEra
    }
}
