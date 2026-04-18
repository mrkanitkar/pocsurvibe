import SVCore
import SwiftUI

// MARK: - Hand Colors

extension AppThemePreset {
    /// Right-hand accent color (light mode).
    var rightHandColor: Color {
        switch self {
        case .immersive, .sargamGlass, .midnight, .synthesia,
            .immersiveBars, .sargamGlassBars, .neonRhythm:
            Color(red: 0.00, green: 0.48, blue: 1.00)  // #007AFF iOS blue
        case .midnightBars:
            Color(red: 0.31, green: 0.76, blue: 0.97)  // #4FC3F7 cyan (OLED contrast)
        case .popEra:
            Color(red: 0.66, green: 0.33, blue: 0.97)  // #A855F7 purple
        }
    }

    /// Left-hand accent color (light mode).
    var leftHandColor: Color {
        switch self {
        case .immersive, .sargamGlass, .midnight, .synthesia,
            .immersiveBars, .sargamGlassBars, .neonRhythm:
            Color(red: 1.00, green: 0.23, blue: 0.19)  // #FF3B30 iOS red
        case .midnightBars:
            Color(red: 0.96, green: 0.65, blue: 0.14)  // #F5A623 amber
        case .popEra:
            Color(red: 1.00, green: 0.25, blue: 0.51)  // #FF4081 pink
        }
    }

    /// Chord / both-hands color (light mode).
    var chordColor: Color {
        switch self {
        case .immersive, .sargamGlass, .midnight, .synthesia,
            .immersiveBars, .sargamGlassBars, .midnightBars, .neonRhythm:
            Color(red: 0.61, green: 0.15, blue: 0.69)  // #9C27B0 purple
        case .popEra:
            Color(red: 0.91, green: 0.47, blue: 0.98)  // #E879F9 fuchsia
        }
    }

    // Dark variants (WCAG-adjusted — these read in both modes)
    var darkRightHandColor: Color { rightHandColor }
    var darkLeftHandColor: Color { leftHandColor }
    var darkChordColor: Color { chordColor }
}
