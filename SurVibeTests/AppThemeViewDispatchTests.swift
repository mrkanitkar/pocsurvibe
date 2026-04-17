import Testing
@testable import SurVibe

struct AppThemeViewDispatchTests {
    @Test func userVisibleThemesMapToSupportedRenderers() {
        // In Phase 2 we add: BarsOnStaffView, SargamDualRowView, SplitLaneView
        // This test sanity-checks that no user-visible theme falls through
        for preset in AppThemePreset.userVisibleCases {
            switch preset {
            case .sargamGlassBars:
                _ = preset.notationMode  // SargamDualRowView
            case .immersiveBars, .midnightBars, .popEra:
                _ = preset.notationMode  // BarsOnStaffView
            case .neonRhythm:
                _ = preset.notationMode  // SplitLaneView
            default:
                Issue.record("Unexpected user-visible preset: \(preset)")
            }
        }
    }
}
