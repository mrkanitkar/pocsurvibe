import SwiftUI
import Testing
@testable import SurVibe

struct AppThemeDarkModeTests {

    @Test func everyPresetHasDistinctLightAndDarkBackgrounds() {
        for preset in AppThemePreset.allCases where !preset.isInherentlyDark {
            #expect(preset.backgroundGradient != preset.darkBackgroundGradient,
                    "\(preset.rawValue): light and dark gradients must differ")
        }
    }

    @Test func everyPresetHasDistinctLightAndDarkCardBg() {
        for preset in AppThemePreset.allCases where !preset.isInherentlyDark {
            // Inherently dark themes use same card in both modes
            #expect(preset.cardBackgroundColor != preset.darkCardBackgroundColor,
                    "\(preset.rawValue): card bg differs light/dark")
        }
    }

    @Test func darkModeResolveIsDarkFlagSet() {
        for preset in AppThemePreset.allCases {
            let resolved = AppThemeDefinition.resolve(preset: preset, colorScheme: .dark)
            #expect(resolved.isDark, "\(preset.rawValue): isDark should be true in dark mode")
        }
    }

    @Test func successErrorColorsReadableInBothModes() {
        for preset in AppThemePreset.allCases {
            #expect(preset.successColor != preset.errorColor)
            #expect(preset.darkSuccessColor != preset.darkErrorColor)
        }
    }
}
