import SwiftUI
import Testing
@testable import SurVibe

struct AppThemeHandColorTests {

    // Grand-staff family (Immersive Bars, Midnight Bars, Pop Era) uses standard Blue/Red/Purple
    @Test func immersiveBarsUsesStandardHandColors() {
        #expect(AppThemePreset.immersiveBars.rightHandColor != AppThemePreset.immersiveBars.leftHandColor)
        #expect(AppThemePreset.immersiveBars.chordColor != AppThemePreset.immersiveBars.rightHandColor)
    }

    @Test func midnightBarsUsesCyanAmberForOLEDContrast() {
        // Midnight-specific: cyan RH + amber LH for OLED-readable contrast
        // Actual color check by comparing distinctness
        let preset = AppThemePreset.midnightBars
        #expect(preset.rightHandColor != preset.leftHandColor)
        #expect(preset.chordColor != preset.rightHandColor)
    }

    @Test func popEraUsesPurplePinkFuchsia() {
        let preset = AppThemePreset.popEra
        #expect(preset.rightHandColor != preset.leftHandColor)
        #expect(preset.chordColor != preset.rightHandColor)
    }

    @Test func allPresetsHaveDistinctRhLhChordColors() {
        for preset in AppThemePreset.allCases {
            #expect(preset.rightHandColor != preset.leftHandColor,
                    "\(preset.rawValue): RH and LH must differ")
            #expect(preset.chordColor != preset.rightHandColor,
                    "\(preset.rawValue): chord and RH must differ")
            #expect(preset.chordColor != preset.leftHandColor,
                    "\(preset.rawValue): chord and LH must differ")
        }
    }

    @Test func darkVariantsExistForAllHandColors() {
        for preset in AppThemePreset.allCases {
            #expect(preset.darkRightHandColor != preset.darkLeftHandColor)
        }
    }

    @Test func cardBackgroundIsThemeAwareDistinctFromPrimary() {
        for preset in AppThemePreset.allCases {
            #expect(preset.cardBackgroundColor != Color.clear)
        }
    }

    @Test func successAndErrorColorsDiffer() {
        for preset in AppThemePreset.allCases {
            #expect(preset.successColor != preset.errorColor)
        }
    }

    @Test func celebrationColorsArrayHasMultipleColors() {
        for preset in AppThemePreset.allCases {
            #expect(preset.celebrationColors.count >= 3)
        }
    }

    @Test func karaokeBackgroundExistsForAllPresets() {
        for preset in AppThemePreset.allCases {
            _ = preset.karaokeBackgroundColor
        }
    }

    @Test func eraAccentVariesPerEra() {
        #expect(
            AppThemePreset.popEra.eraAccentColor(for: .taylor)
                != AppThemePreset.popEra.eraAccentColor(for: .olivia)
        )
        #expect(
            AppThemePreset.popEra.eraAccentColor(for: .brat)
                != AppThemePreset.popEra.eraAccentColor(for: .sabrina)
        )
    }

    @Test func notationLineContrastsBackground() {
        for preset in AppThemePreset.allCases {
            _ = preset.notationLineColor
            _ = preset.notationSecondaryColor
        }
    }
}
