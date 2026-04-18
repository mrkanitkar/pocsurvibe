import Testing
@testable import SurVibe

struct AppThemeViewDispatchTests {
    @Test func userVisibleThemesMapToSupportedRenderers() {
        // Sanity-check: every user-visible preset has a documented renderer mapping.
        // Phase 2 added BarsOnStaffView / SargamDualRowView / SplitLaneView;
        // Phase 3.5 + the 9-theme picker exposed the original Drop variants too.
        for preset in AppThemePreset.userVisibleCases {
            switch preset {
            // Bars-style grand staff with horizontal colored bars
            case .sargamGlassBars:
                _ = preset.notationMode  // SargamDualRowView (dual-row Sargam)
            case .immersiveBars, .midnightBars, .popEra:
                _ = preset.notationMode  // BarsOnStaffView (grand staff + bars)

            // Drop variants — ScrollingSheetView with classical round notes
            case .immersive, .midnight, .sargamGlass:
                _ = preset.notationMode  // ScrollingSheetView (sheetMusic / sargamPlusSheet)

            // Falling-notes lanes (vertical drop)
            case .synthesia, .neonRhythm:
                _ = preset.notationMode  // SplitLaneView
            }
        }
    }
}
