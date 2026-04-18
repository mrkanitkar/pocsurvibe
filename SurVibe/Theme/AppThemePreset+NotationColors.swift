import SVCore
import SwiftUI

// MARK: - Notation Colors

extension AppThemePreset {
    var notationLineColor: Color {
        switch self {
        case .immersive, .immersiveBars, .sargamGlass, .sargamGlassBars, .popEra:
            Color(red: 0.13, green: 0.13, blue: 0.13)
        case .midnight, .midnightBars:
            Color(red: 0.96, green: 0.65, blue: 0.14)  // amber
        case .neonRhythm, .synthesia:
            Color.white.opacity(0.55)
        }
    }

    var darkNotationLineColor: Color {
        switch self {
        case .immersive, .immersiveBars, .sargamGlass, .sargamGlassBars, .popEra:
            Color.white.opacity(0.75)
        default:
            notationLineColor
        }
    }

    var notationSecondaryColor: Color { notationLineColor.opacity(0.55) }
    var darkNotationSecondaryColor: Color { darkNotationLineColor.opacity(0.55) }
}
