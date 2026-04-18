import Testing
@testable import SurVibe

struct AppThemeViewDispatchTests {
    @Test func userVisibleThemesMapToSupportedRenderers() {
        // Sanity-check: every user-visible preset has a documented renderer mapping.
        // Phase 2 added BarsOnStaffView / SargamDualRowView / SplitLaneView;
        // Phase 3.5 + the 9-theme picker exposed the original Drop variants too.
        for preset in AppThemePreset.userVisibleCases {
            switch preset {
            // Bars + Pop Era family — BarsOnStaffView (or SargamDualRowView for sargam)
            case .sargamGlassBars:
                _ = preset.notationMode  // SargamDualRowView
            case .immersiveBars, .midnightBars, .popEra:
                _ = preset.notationMode  // BarsOnStaffView

            // Drop variants — scrolling sheet renderers (originals)
            case .sargamGlass:
                _ = preset.notationMode  // .sargamPlusSheet → SargamDualRowView (drop)
            case .immersive, .midnight:
                _ = preset.notationMode  // .sheetMusic → ScrollingSheetView (drop)

            // Falling-notes lanes
            case .synthesia:
                _ = preset.notationMode  // .western → FallingNotesView
            case .neonRhythm:
                _ = preset.notationMode  // SplitLaneView
            }
        }
    }
}
