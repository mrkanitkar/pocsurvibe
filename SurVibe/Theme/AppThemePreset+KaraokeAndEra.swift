import SVCore
import SwiftUI

// MARK: - Karaoke & Era Colors

extension AppThemePreset {
    var karaokeBackgroundColor: Color {
        switch self {
        case .popEra:
            Color(red: 0.35, green: 0.09, blue: 0.44).opacity(0.82)
        default:
            Color.black.opacity(0.55)
        }
    }

    var darkKaraokeBackgroundColor: Color { karaokeBackgroundColor }

    /// Era-specific accent color for Pop Era theme.
    ///
    /// Only consumed when `preset == .popEra`. Returns `accentColor` for others.
    func eraAccentColor(for era: PopEra) -> Color {
        guard self == .popEra else { return accentColor }
        switch era {
        case .taylor: return Color(red: 1.00, green: 0.25, blue: 0.51)  // #FF4081 pink
        case .olivia: return Color(red: 0.66, green: 0.33, blue: 0.97)  // #A855F7 purple
        case .sabrina: return Color(red: 0.02, green: 0.71, blue: 0.83)  // #06B6D4 cyan
        case .chappell: return Color(red: 1.00, green: 0.41, blue: 0.71)  // #FF69B4 hot pink
        case .brat: return Color(red: 0.76, green: 0.97, blue: 0.23)  // #C3F73A lime
        }
    }

    func darkEraAccentColor(for era: PopEra) -> Color { eraAccentColor(for: era) }
}
