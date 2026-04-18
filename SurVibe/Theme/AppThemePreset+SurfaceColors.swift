import SVCore
import SwiftUI

// MARK: - Surface & Feedback Colors

extension AppThemePreset {
    /// Card background surface color (light mode). Used by elevated content cards.
    var cardBackgroundColor: Color {
        switch self {
        case .immersive, .immersiveBars:
            Color.white.opacity(0.92)
        case .sargamGlass, .sargamGlassBars:
            Color.white.opacity(0.55)
        case .midnight, .midnightBars, .neonRhythm, .synthesia:
            Color(red: 0.10, green: 0.10, blue: 0.12)
        case .popEra:
            Color.white.opacity(0.78)
        }
    }

    /// Card background surface color (dark mode).
    var darkCardBackgroundColor: Color {
        switch self {
        case .immersive, .immersiveBars:
            Color(red: 0.10, green: 0.12, blue: 0.18).opacity(0.85)
        case .sargamGlass, .sargamGlassBars:
            Color(red: 0.14, green: 0.10, blue: 0.12).opacity(0.72)
        case .midnight, .midnightBars, .neonRhythm, .synthesia:
            cardBackgroundColor
        case .popEra:
            Color(red: 0.16, green: 0.08, blue: 0.22).opacity(0.78)
        }
    }

    /// Badge text color (light mode) — always white for maximum contrast on colored badges.
    var badgeTextColor: Color { .white }
    /// Badge text color (dark mode).
    var darkBadgeTextColor: Color { .white }

    /// Success feedback color (light mode) — Apple system green (#34C759).
    var successColor: Color { Color(red: 0.20, green: 0.78, blue: 0.35) }
    /// Success feedback color (dark mode) — Apple system green dark (#30D158).
    var darkSuccessColor: Color { Color(red: 0.19, green: 0.82, blue: 0.35) }
    /// Error feedback color (light mode) — Apple system red (#FF3B30).
    var errorColor: Color { Color(red: 1.00, green: 0.23, blue: 0.19) }
    /// Error feedback color (dark mode) — Apple system red dark (#FF453A).
    var darkErrorColor: Color { Color(red: 1.00, green: 0.27, blue: 0.23) }

    /// Palette used for confetti, sparkles, and celebration animations (light mode).
    var celebrationColors: [Color] {
        switch self {
        case .popEra:
            [
                Color(red: 1.00, green: 0.41, blue: 0.71),  // pink
                Color(red: 0.66, green: 0.33, blue: 0.97),  // purple
                Color(red: 0.76, green: 0.97, blue: 1.00),  // sky
                Color(red: 1.00, green: 0.84, blue: 0.00),  // gold
                Color(red: 0.91, green: 0.47, blue: 0.98),  // fuchsia
                Color(red: 1.00, green: 1.00, blue: 1.00),
            ]  // white sparkle
        case .neonRhythm:
            [
                Color(red: 1.00, green: 0.00, blue: 0.43),
                Color(red: 0.00, green: 1.00, blue: 0.82),
                Color(red: 1.00, green: 0.74, blue: 0.04),
                Color(red: 0.51, green: 0.22, blue: 0.93),
                Color(red: 0.23, green: 0.52, blue: 1.00),
            ]
        default:
            // Rang-inspired palette for Sargam + Western + Night + legacy
            [
                Color(red: 0.25, green: 0.32, blue: 0.71),  // Neel
                Color(red: 0.22, green: 0.56, blue: 0.24),  // Hara
                Color(red: 0.98, green: 0.66, blue: 0.14),  // Peela
                Color(red: 0.83, green: 0.18, blue: 0.18),  // Lal
                Color(red: 1.00, green: 0.70, blue: 0.00),
            ]  // Sona
        }
    }

    /// Celebration palette (dark mode) — saturated palette reads in both modes.
    var darkCelebrationColors: [Color] { celebrationColors }
}
