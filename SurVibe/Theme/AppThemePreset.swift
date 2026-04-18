import SVCore
import SwiftUI

/// Pop Era sub-theme — selects accent color set for the Pop Era main theme.
///
/// Driven by the 2025-26 music zeitgeist. Persisted separately from the
/// main theme via `UserDefaults["appThemePopEra"]`.
enum PopEra: String, CaseIterable, Sendable {
    case taylor
    case olivia
    case sabrina
    case chappell
    case brat

    var displayName: String {
        switch self {
        case .taylor: "Taylor"
        case .olivia: "Olivia"
        case .sabrina: "Sabrina"
        case .chappell: "Chappell"
        case .brat: "Brat"
        }
    }

    var iconName: String {
        switch self {
        case .taylor: "heart.fill"
        case .olivia: "sparkles"
        case .sabrina: "snowflake"
        case .chappell: "crown.fill"
        case .brat: "bolt.fill"
        }
    }
}

/// Bundled theme presets for the SurVibe app.
///
/// Each preset defines:
/// - **Visual style:** background gradient, accent color, surface appearance
/// - **Play-along view mode:** falling notes or scrolling sheet
/// - **Notation mode:** sargam, western, sheet music, or combinations
///
/// This replaces the two separate pickers (`PlayAlongViewMode` and
/// `NotationDisplayMode`) in the play-along toolbar, reducing cognitive
/// load from 15 possible combinations to 5 curated experiences.
///
/// Persisted via `UserDefaults["appThemePreset"]`.
enum AppThemePreset: String, CaseIterable, Sendable {
    /// Teal gradient, grand staff, blue playhead. Simply Piano-inspired.
    case immersive

    /// Dark neon, falling Sargam blocks, LED piano. Gaming/rhythm feel.
    case neonRhythm

    /// Warm glassmorphism, Sargam + Staff, rang colors. Indian identity.
    case sargamGlass

    /// OLED black, amber accents, grand staff. Night practice.
    case midnight

    /// Dark falling note lanes, western labels. Synthesia-style.
    case synthesia

    // MARK: - New v2 Presets

    /// Hero / default: Sargam Glass with horizontal bar playhead (v2).
    case sargamGlassBars

    /// Western mode: Immersive with horizontal bar playhead (v2).
    case immersiveBars

    /// Night mode: Midnight with horizontal bar playhead (v2).
    case midnightBars

    /// Pop Era mode: zeitgeist accents (Taylor/Olivia/Sabrina/Chappell/Brat).
    case popEra

    /// User-visible presets in the Profile theme picker.
    /// Legacy cases are hidden compat fallbacks during migration.
    static let userVisibleCases: [AppThemePreset] = [
        .sargamGlassBars,
        .immersiveBars,
        .midnightBars,
        .popEra,
        .neonRhythm,
    ]

    // MARK: - Play-Along Derived Properties

    /// The play-along view mode this theme uses.
    ///
    /// Neon Rhythm and Synthesia use falling notes; all others use
    /// scrolling sheet music. This replaces the separate ViewMode picker.
    var viewMode: PlayAlongViewMode {
        switch self {
        case .neonRhythm, .synthesia: .fallingNotes
        case .immersive, .sargamGlass, .midnight: .scrollingSheet
        case .sargamGlassBars, .immersiveBars, .midnightBars, .popEra: .scrollingSheet
        }
    }

    /// The notation display mode this theme uses.
    ///
    /// Each theme selects the notation system that best matches its
    /// visual design. This replaces the separate NotationMode picker.
    var notationMode: NotationDisplayMode {
        switch self {
        case .immersive: .sheetMusic
        case .neonRhythm: .sargam
        case .sargamGlass: .sargamPlusSheet
        case .midnight: .sheetMusic
        case .synthesia: .western
        case .sargamGlassBars: .sargamPlusSheet
        case .immersiveBars: .sheetMusic
        case .midnightBars: .sargamPlusSheet
        case .popEra: .sheetMusic
        }
    }

    // MARK: - Visual Properties (Light Mode)

    /// Background gradient colors for the primary screen background.
    var backgroundGradient: [Color] {
        switch self {
        case .immersive:
            [
                Color(red: 0.00, green: 0.65, blue: 0.72),
                Color(red: 0.04, green: 0.47, blue: 0.54),
                Color(red: 0.10, green: 0.23, blue: 0.42),
                Color(red: 0.06, green: 0.12, blue: 0.23),
            ]
        case .neonRhythm:
            [Color(red: 0.07, green: 0.07, blue: 0.12)]
        case .sargamGlass:
            [
                Color(red: 1.00, green: 0.97, blue: 0.94),
                Color(red: 1.00, green: 0.88, blue: 0.70),
                Color(red: 1.00, green: 0.80, blue: 0.74),
                Color(red: 0.91, green: 0.84, blue: 0.96),
                Color(red: 0.82, green: 0.77, blue: 0.89),
            ]
        case .midnight:
            [Color.black]
        case .synthesia:
            [Color(red: 0.04, green: 0.04, blue: 0.08)]
        // TODO(Task 1.4-1.8): refine backgroundGradient for v2 bar presets
        case .sargamGlassBars:
            [
                Color(red: 1.00, green: 0.97, blue: 0.94),
                Color(red: 1.00, green: 0.88, blue: 0.70),
                Color(red: 1.00, green: 0.80, blue: 0.74),
                Color(red: 0.91, green: 0.84, blue: 0.96),
                Color(red: 0.82, green: 0.77, blue: 0.89),
            ]
        case .immersiveBars:
            [
                Color(red: 0.00, green: 0.65, blue: 0.72),
                Color(red: 0.04, green: 0.47, blue: 0.54),
                Color(red: 0.10, green: 0.23, blue: 0.42),
                Color(red: 0.06, green: 0.12, blue: 0.23),
            ]
        case .midnightBars:
            [Color.black]
        case .popEra:
            [Color.black]
        }
    }

    /// Dark mode background gradient.
    var darkBackgroundGradient: [Color] {
        switch self {
        case .immersive:
            [
                Color(red: 0.02, green: 0.20, blue: 0.25),
                Color(red: 0.03, green: 0.12, blue: 0.20),
                Color(red: 0.04, green: 0.08, blue: 0.14),
            ]
        case .sargamGlass:
            [
                Color(red: 0.15, green: 0.10, blue: 0.08),
                Color(red: 0.12, green: 0.08, blue: 0.15),
                Color(red: 0.10, green: 0.08, blue: 0.18),
            ]
        case .neonRhythm, .midnight, .synthesia:
            backgroundGradient  // Already dark — same in both modes
        // TODO(Task 1.4-1.8): refine darkBackgroundGradient for v2 bar presets
        case .sargamGlassBars:
            [
                Color(red: 0.15, green: 0.10, blue: 0.08),
                Color(red: 0.12, green: 0.08, blue: 0.15),
                Color(red: 0.10, green: 0.08, blue: 0.18),
            ]
        case .immersiveBars:
            [
                Color(red: 0.02, green: 0.20, blue: 0.25),
                Color(red: 0.03, green: 0.12, blue: 0.20),
                Color(red: 0.04, green: 0.08, blue: 0.14),
            ]
        case .midnightBars, .popEra:
            backgroundGradient
        }
    }

    /// Primary accent color for interactive elements and highlights.
    var accentColor: Color {
        switch self {
        case .immersive: Color(red: 0.00, green: 0.71, blue: 0.85)  // #00B4D8
        case .neonRhythm: Color(red: 1.00, green: 0.00, blue: 0.43)  // #FF006E
        case .sargamGlass: .rangNeel  // #3F51B5
        case .midnight: Color(red: 0.96, green: 0.65, blue: 0.14)  // #F5A623
        case .synthesia: Color(red: 0.30, green: 0.69, blue: 0.31)  // #4CAF50
        // TODO(Task 1.4-1.8): refine accentColor for v2 bar presets
        case .sargamGlassBars: .rangNeel
        case .immersiveBars: Color(red: 0.00, green: 0.71, blue: 0.85)
        case .midnightBars: Color(red: 0.96, green: 0.65, blue: 0.14)
        case .popEra: Color(red: 1.00, green: 0.00, blue: 0.43)
        }
    }

    /// Playhead color for the scrolling notation cursor.
    var playheadColor: Color {
        switch self {
        case .immersive: Color(red: 0.00, green: 0.63, blue: 1.00)  // #00A0FF
        case .neonRhythm: Color(red: 1.00, green: 0.00, blue: 0.43)  // #FF006E
        case .sargamGlass: .rangNeel
        case .midnight: Color(red: 0.96, green: 0.65, blue: 0.14)  // #F5A623
        case .synthesia: Color(red: 0.30, green: 0.69, blue: 0.31)  // #4CAF50
        // TODO(Task 1.4-1.8): refine playheadColor for v2 bar presets
        case .sargamGlassBars: .rangNeel
        case .immersiveBars: Color(red: 0.00, green: 0.63, blue: 1.00)
        case .midnightBars: Color(red: 0.96, green: 0.65, blue: 0.14)
        case .popEra: Color(red: 1.00, green: 0.00, blue: 0.43)
        }
    }

    /// Surface color for cards, panels, and overlays (light mode).
    var surfaceColor: Color {
        switch self {
        case .immersive: .white.opacity(0.93)
        case .neonRhythm: .white.opacity(0.04)
        case .sargamGlass: .white.opacity(0.38)
        case .midnight: Color(red: 0.04, green: 0.04, blue: 0.04)
        case .synthesia: .white.opacity(0.04)
        // TODO(Task 1.4-1.8): refine surfaceColor for v2 bar presets
        case .sargamGlassBars: .white.opacity(0.38)
        case .immersiveBars: .white.opacity(0.93)
        case .midnightBars: Color(red: 0.04, green: 0.04, blue: 0.04)
        case .popEra: .white.opacity(0.04)
        }
    }

    /// Surface color for dark mode.
    var darkSurfaceColor: Color {
        switch self {
        case .immersive: Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.85)
        case .sargamGlass: Color(red: 0.12, green: 0.08, blue: 0.10).opacity(0.65)
        case .neonRhythm, .midnight, .synthesia: surfaceColor
        // TODO(Task 1.4-1.8): refine darkSurfaceColor for v2 bar presets
        case .sargamGlassBars: Color(red: 0.12, green: 0.08, blue: 0.10).opacity(0.65)
        case .immersiveBars: Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.85)
        case .midnightBars, .popEra: surfaceColor
        }
    }

    /// Whether this theme is inherently dark (same appearance in both system modes).
    var isInherentlyDark: Bool {
        switch self {
        case .neonRhythm, .midnight, .synthesia: true
        case .immersive, .sargamGlass: false
        // TODO(Task 1.4-1.8): refine isInherentlyDark for v2 bar presets
        case .sargamGlassBars: false
        case .immersiveBars: false
        case .midnightBars, .popEra: true
        }
    }

    // MARK: - Piano Style

    /// Whether piano keys use dark styling (dark keys with colored highlights).
    var usesDarkPiano: Bool {
        switch self {
        case .neonRhythm, .midnight, .synthesia: true
        case .immersive, .sargamGlass: false
        // TODO(Task 1.4-1.8): refine usesDarkPiano for v2 bar presets
        case .sargamGlassBars: false
        case .immersiveBars: false
        case .midnightBars, .popEra: true
        }
    }

    /// Whether piano key highlights use the note's SargamColorMap color
    /// instead of the theme's accent color.
    var usesRangColoredPianoKeys: Bool {
        switch self {
        case .neonRhythm, .sargamGlass, .synthesia: true
        case .immersive, .midnight: false
        // TODO(Task 1.4-1.8): refine usesRangColoredPianoKeys for v2 bar presets
        case .sargamGlassBars: true
        case .immersiveBars: false
        case .midnightBars: false
        case .popEra: true
        }
    }

    // MARK: - UI Metadata

    /// Human-readable display name for the theme picker.
    var displayName: String {
        switch self {
        case .sargamGlassBars: String(localized: "Sargam")
        case .immersiveBars: String(localized: "Western")
        case .midnightBars: String(localized: "Night")
        case .popEra: String(localized: "Pop Era")
        case .neonRhythm: String(localized: "Arcade")
        // Legacy (hidden from picker; kept non-localized)
        case .immersive: "Immersive (legacy)"
        case .sargamGlass: "Sargam Glass (legacy)"
        case .midnight: "Midnight (legacy)"
        case .synthesia: "Synthesia (legacy)"
        }
    }

    /// SF Symbol icon name for the theme.
    var iconName: String {
        switch self {
        case .immersive: "waveform"
        case .neonRhythm: "bolt.fill"
        case .sargamGlass: "sparkles"
        case .midnight: "moon.fill"
        case .synthesia: "arrow.down.to.line"
        // TODO(Task 1.4-1.8): refine iconName for v2 bar presets
        case .sargamGlassBars: "sparkles"
        case .immersiveBars: "waveform"
        case .midnightBars: "moon.fill"
        case .popEra: "music.mic"
        }
    }

    /// Short description for the theme picker card.
    var subtitle: String {
        switch self {
        case .immersive: "Clean focus, sheet music"
        case .neonRhythm: "Neon falling notes"
        case .sargamGlass: "Indian glass, Sargam"
        case .midnight: "Dark, amber accents"
        case .synthesia: "Piano-roll falling notes"
        // TODO(Task 1.4-1.8): refine subtitle for v2 bar presets
        case .sargamGlassBars: "Indian glass, Sargam (v2)"
        case .immersiveBars: "Clean focus, sheet music (v2)"
        case .midnightBars: "Dark, amber accents (v2)"
        case .popEra: "Pop zeitgeist accents"
        }
    }

    // MARK: - Hand Colors (v2)

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

    // MARK: - Surface & Feedback Colors (v2)

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

    // MARK: - Karaoke & Era & Notation Colors (v2)

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

    // MARK: - Learn-Tab Tokens (v2 Phase 3)

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

    // MARK: - Migration (v2)

    /// Map a legacy raw value (v1) to its v2 equivalent.
    ///
    /// Returns the same value if already a v2 case. Returns `.sargamGlassBars`
    /// (the new default) if the raw value is unrecognized.
    static func migrateFromV1(_ rawValue: String) -> AppThemePreset {
        if let direct = AppThemePreset(rawValue: rawValue) {
            switch direct {
            case .immersive: return .immersiveBars
            case .sargamGlass: return .sargamGlassBars
            case .midnight: return .midnightBars
            case .synthesia: return .immersiveBars
            case .neonRhythm: return .neonRhythm
            case .sargamGlassBars, .immersiveBars, .midnightBars, .popEra:
                return direct  // already v2
            }
        }
        return .sargamGlassBars  // unknown → new default
    }
}
