import SwiftUI
import Testing
@testable import SurVibe

struct AppThemeDefinitionV2Tests {

    @Test func resolvedContainsHandColors() {
        let def = AppThemeDefinition.resolve(preset: .sargamGlassBars, colorScheme: .light)
        _ = def.rightHandColor
        _ = def.leftHandColor
        _ = def.chordColor
    }

    @Test func resolvedContainsCardBackground() {
        let def = AppThemeDefinition.resolve(preset: .immersiveBars, colorScheme: .light)
        _ = def.cardBackgroundColor
    }

    @Test func resolvedContainsSuccessError() {
        let def = AppThemeDefinition.resolve(preset: .neonRhythm, colorScheme: .dark)
        _ = def.successColor
        _ = def.errorColor
    }

    @Test func resolvedContainsCelebration() {
        let def = AppThemeDefinition.resolve(preset: .popEra, colorScheme: .light)
        #expect(def.celebrationColors.count >= 3)
    }

    @Test func resolvedContainsKaraokeBg() {
        let def = AppThemeDefinition.resolve(preset: .popEra, colorScheme: .light)
        _ = def.karaokeBackgroundColor
    }

    @Test func resolvedContainsEraAccent() {
        let def = AppThemeDefinition.resolve(preset: .popEra, popEra: .taylor, colorScheme: .light)
        _ = def.eraAccentColor
    }

    @Test func resolvedContainsNotationColors() {
        let def = AppThemeDefinition.resolve(preset: .midnightBars, colorScheme: .dark)
        _ = def.notationLineColor
        _ = def.notationSecondaryColor
    }
}
