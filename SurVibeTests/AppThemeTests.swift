import SwiftUI
import Testing
@testable import SurVibe

/// Tests for the app-wide theme system.
///
/// Verifies preset-to-mode mapping, persistence, dark mode resolution,
/// and raw value stability for all 5 theme presets.
struct AppThemeTests {

    // MARK: - Preset → ViewMode Mapping

    @Test func immersiveUsesScrollingSheet() {
        #expect(AppThemePreset.immersive.viewMode == .scrollingSheet)
    }

    @Test func neonRhythmUsesFallingNotes() {
        #expect(AppThemePreset.neonRhythm.viewMode == .fallingNotes)
    }

    @Test func sargamGlassUsesScrollingSheet() {
        #expect(AppThemePreset.sargamGlass.viewMode == .scrollingSheet)
    }

    @Test func midnightUsesScrollingSheet() {
        #expect(AppThemePreset.midnight.viewMode == .scrollingSheet)
    }

    @Test func synthesiaUsesFallingNotes() {
        #expect(AppThemePreset.synthesia.viewMode == .fallingNotes)
    }

    // MARK: - Preset → NotationMode Mapping

    @Test func immersiveUsesSheetMusic() {
        #expect(AppThemePreset.immersive.notationMode == .sheetMusic)
    }

    @Test func neonRhythmUsesSargam() {
        #expect(AppThemePreset.neonRhythm.notationMode == .sargam)
    }

    @Test func sargamGlassUsesSargamPlusSheet() {
        #expect(AppThemePreset.sargamGlass.notationMode == .sargamPlusSheet)
    }

    @Test func midnightUsesSheetMusic() {
        #expect(AppThemePreset.midnight.notationMode == .sheetMusic)
    }

    @Test func synthesiaUsesWestern() {
        #expect(AppThemePreset.synthesia.notationMode == .western)
    }

    // MARK: - Raw Value Stability

    @Test func rawValuesAreStable() {
        #expect(AppThemePreset.immersive.rawValue == "immersive")
        #expect(AppThemePreset.neonRhythm.rawValue == "neonRhythm")
        #expect(AppThemePreset.sargamGlass.rawValue == "sargamGlass")
        #expect(AppThemePreset.midnight.rawValue == "midnight")
        #expect(AppThemePreset.synthesia.rawValue == "synthesia")
    }

    @Test func rawValueRoundTrips() {
        for preset in AppThemePreset.allCases {
            let restored = AppThemePreset(rawValue: preset.rawValue)
            #expect(restored == preset)
        }
    }

    @Test func invalidRawValueReturnsNil() {
        #expect(AppThemePreset(rawValue: "nonexistent") == nil)
    }

    // MARK: - All Cases Count

    @Test func nineTotalPresetsExist() {
        #expect(AppThemePreset.allCases.count == 9)
    }

    // MARK: - Display Names

    @Test func displayNamesAreNonEmpty() {
        for preset in AppThemePreset.allCases {
            #expect(!preset.displayName.isEmpty)
        }
    }

    // MARK: - Dark Mode

    @Test func neonRhythmIsInherentlyDark() {
        #expect(AppThemePreset.neonRhythm.isInherentlyDark)
    }

    @Test func midnightIsInherentlyDark() {
        #expect(AppThemePreset.midnight.isInherentlyDark)
    }

    @Test func synthesiaIsInherentlyDark() {
        #expect(AppThemePreset.synthesia.isInherentlyDark)
    }

    @Test func immersiveIsNotInherentlyDark() {
        #expect(!AppThemePreset.immersive.isInherentlyDark)
    }

    @Test func sargamGlassIsNotInherentlyDark() {
        #expect(!AppThemePreset.sargamGlass.isInherentlyDark)
    }

    // MARK: - Theme Definition Resolution

    @Test func resolvedDefinitionHasNonEmptyGradient() {
        for preset in AppThemePreset.allCases {
            let resolved = AppThemeDefinition.resolve(preset: preset, colorScheme: .light)
            #expect(!resolved.backgroundGradient.isEmpty)
        }
    }

    @Test func inherentlyDarkThemesResolveDarkInLightMode() {
        let resolved = AppThemeDefinition.resolve(preset: .midnight, colorScheme: .light)
        #expect(resolved.isDark)
    }

    @Test func nonDarkThemesResolveLightInLightMode() {
        let resolved = AppThemeDefinition.resolve(preset: .immersive, colorScheme: .light)
        #expect(!resolved.isDark)
    }

    @Test func nonDarkThemesResolveDarkInDarkMode() {
        let resolved = AppThemeDefinition.resolve(preset: .immersive, colorScheme: .dark)
        #expect(resolved.isDark)
    }

    // MARK: - Background Gradients

    @Test func backgroundGradientsAreNonEmpty() {
        for preset in AppThemePreset.allCases {
            #expect(!preset.backgroundGradient.isEmpty)
            #expect(!preset.darkBackgroundGradient.isEmpty)
        }
    }

    // MARK: - Piano Styles

    @Test func darkThemesUseDarkPiano() {
        #expect(AppThemePreset.neonRhythm.usesDarkPiano)
        #expect(AppThemePreset.midnight.usesDarkPiano)
        #expect(AppThemePreset.synthesia.usesDarkPiano)
    }

    @Test func lightThemesUseClassicPiano() {
        #expect(!AppThemePreset.immersive.usesDarkPiano)
        #expect(!AppThemePreset.sargamGlass.usesDarkPiano)
    }

    // MARK: - New Preset → ViewMode Mapping (v2)

    @Test func sargamGlassBarsUsesScrollingSheet() {
        #expect(AppThemePreset.sargamGlassBars.viewMode == .scrollingSheet)
    }

    @Test func immersiveBarsUsesScrollingSheet() {
        #expect(AppThemePreset.immersiveBars.viewMode == .scrollingSheet)
    }

    @Test func midnightBarsUsesScrollingSheet() {
        #expect(AppThemePreset.midnightBars.viewMode == .scrollingSheet)
    }

    @Test func popEraUsesScrollingSheet() {
        #expect(AppThemePreset.popEra.viewMode == .scrollingSheet)
    }

    // MARK: - New Preset → NotationMode Mapping (v2)

    @Test func sargamGlassBarsUsesSargamPlusSheet() {
        #expect(AppThemePreset.sargamGlassBars.notationMode == .sargamPlusSheet)
    }

    @Test func immersiveBarsUsesSheetMusic() {
        #expect(AppThemePreset.immersiveBars.notationMode == .sheetMusic)
    }

    @Test func midnightBarsUsesSargamPlusSheet() {
        #expect(AppThemePreset.midnightBars.notationMode == .sargamPlusSheet)
    }

    @Test func popEraUsesSheetMusic() {
        #expect(AppThemePreset.popEra.notationMode == .sheetMusic)
    }
}
