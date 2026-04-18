import SVCore
import SwiftUI

// MARK: - Learn-Tab Tokens (v2 Phase 3)

extension AppThemePreset {
    /// Divider / progress-track color (light mode).
    ///
    /// Used for hairline separators, progress-bar rails, and disabled-state
    /// strokes. Replaces hardcoded `Color(.systemGray4)` / `Color(.systemGray5)`
    /// references in Learn-tab views.
    var dividerColor: Color {
        switch self {
        case .immersive, .immersiveBars, .sargamGlass, .sargamGlassBars:
            Color(red: 0.82, green: 0.82, blue: 0.84)  // system gray 4 equivalent
        case .midnight, .midnightBars, .neonRhythm, .synthesia:
            Color.white.opacity(0.18)
        case .popEra:
            Color(red: 0.70, green: 0.62, blue: 0.78)  // muted lavender
        }
    }

    /// Divider / progress-track color (dark mode).
    var darkDividerColor: Color {
        switch self {
        case .immersive, .immersiveBars, .sargamGlass, .sargamGlassBars, .popEra:
            Color.white.opacity(0.22)
        default:
            dividerColor
        }
    }

    /// Nested surface color (light mode).
    ///
    /// Used for chips, capsules, and inset cards rendered INSIDE a
    /// `cardBackgroundColor` container. Preserves an elevation hierarchy:
    /// `cardBackgroundColor` > `nestedSurfaceColor`. Replaces hardcoded
    /// `Color(.tertiarySystemBackground)` in Learn-tab views.
    ///
    /// Spec §10 open question #1: Sargam Glass variants use a deeper cream
    /// with 0.5 opacity to preserve depth against the warm gradient.
    var nestedSurfaceColor: Color {
        switch self {
        case .immersive, .immersiveBars:
            Color.white.opacity(0.75)
        case .sargamGlass, .sargamGlassBars:
            Color(red: 1.00, green: 0.93, blue: 0.85).opacity(0.5)  // deeper cream
        case .midnight, .midnightBars, .neonRhythm, .synthesia:
            Color(red: 0.18, green: 0.18, blue: 0.20)
        case .popEra:
            Color.white.opacity(0.60)
        }
    }

    /// Nested surface color (dark mode).
    var darkNestedSurfaceColor: Color {
        switch self {
        case .immersive, .immersiveBars:
            Color(red: 0.14, green: 0.16, blue: 0.22).opacity(0.80)
        case .sargamGlass, .sargamGlassBars:
            Color(red: 0.18, green: 0.14, blue: 0.16).opacity(0.65)
        case .midnight, .midnightBars, .neonRhythm, .synthesia:
            nestedSurfaceColor
        case .popEra:
            Color(red: 0.20, green: 0.10, blue: 0.26).opacity(0.72)
        }
    }

    /// Warning / attention feedback color (light mode).
    ///
    /// Used for time pressure, streak-at-risk, and attention cues. Replaces
    /// hardcoded `.foregroundStyle(.orange)` / `.tint(.orange)` references
    /// in Learn-tab views.
    var warningColor: Color {
        switch self {
        case .popEra:
            Color(red: 1.00, green: 0.41, blue: 0.71)  // pink-warning for era palette
        default:
            Color(red: 1.00, green: 0.58, blue: 0.00)  // Apple system orange (#FF9500)
        }
    }

    /// Warning / attention feedback color (dark mode).
    ///
    /// Spec §10 open question #2: Midnight dark uses amber (#F5A623) to match
    /// the OLED palette (same as the existing `accentColor` for `.midnight`).
    var darkWarningColor: Color {
        switch self {
        case .midnight, .midnightBars:
            Color(red: 0.96, green: 0.65, blue: 0.14)  // #F5A623 amber
        case .popEra:
            warningColor
        default:
            Color(red: 1.00, green: 0.62, blue: 0.04)  // Apple system orange dark
        }
    }
}
