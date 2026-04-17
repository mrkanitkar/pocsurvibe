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
        .neonRhythm
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
        // TODO(Task 1.2): refine viewMode mapping for v2 bar presets
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
        // TODO(Task 1.2): refine notationMode mapping for v2 bar presets
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
            [Color(red: 0.00, green: 0.65, blue: 0.72),
             Color(red: 0.04, green: 0.47, blue: 0.54),
             Color(red: 0.10, green: 0.23, blue: 0.42),
             Color(red: 0.06, green: 0.12, blue: 0.23)]
        case .neonRhythm:
            [Color(red: 0.07, green: 0.07, blue: 0.12)]
        case .sargamGlass:
            [Color(red: 1.00, green: 0.97, blue: 0.94),
             Color(red: 1.00, green: 0.88, blue: 0.70),
             Color(red: 1.00, green: 0.80, blue: 0.74),
             Color(red: 0.91, green: 0.84, blue: 0.96),
             Color(red: 0.82, green: 0.77, blue: 0.89)]
        case .midnight:
            [Color.black]
        case .synthesia:
            [Color(red: 0.04, green: 0.04, blue: 0.08)]
        // TODO(Task 1.4-1.8): refine backgroundGradient for v2 bar presets
        case .sargamGlassBars:
            [Color(red: 1.00, green: 0.97, blue: 0.94),
             Color(red: 1.00, green: 0.88, blue: 0.70),
             Color(red: 1.00, green: 0.80, blue: 0.74),
             Color(red: 0.91, green: 0.84, blue: 0.96),
             Color(red: 0.82, green: 0.77, blue: 0.89)]
        case .immersiveBars:
            [Color(red: 0.00, green: 0.65, blue: 0.72),
             Color(red: 0.04, green: 0.47, blue: 0.54),
             Color(red: 0.10, green: 0.23, blue: 0.42),
             Color(red: 0.06, green: 0.12, blue: 0.23)]
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
            [Color(red: 0.02, green: 0.20, blue: 0.25),
             Color(red: 0.03, green: 0.12, blue: 0.20),
             Color(red: 0.04, green: 0.08, blue: 0.14)]
        case .sargamGlass:
            [Color(red: 0.15, green: 0.10, blue: 0.08),
             Color(red: 0.12, green: 0.08, blue: 0.15),
             Color(red: 0.10, green: 0.08, blue: 0.18)]
        case .neonRhythm, .midnight, .synthesia:
            backgroundGradient // Already dark — same in both modes
        // TODO(Task 1.4-1.8): refine darkBackgroundGradient for v2 bar presets
        case .sargamGlassBars:
            [Color(red: 0.15, green: 0.10, blue: 0.08),
             Color(red: 0.12, green: 0.08, blue: 0.15),
             Color(red: 0.10, green: 0.08, blue: 0.18)]
        case .immersiveBars:
            [Color(red: 0.02, green: 0.20, blue: 0.25),
             Color(red: 0.03, green: 0.12, blue: 0.20),
             Color(red: 0.04, green: 0.08, blue: 0.14)]
        case .midnightBars, .popEra:
            backgroundGradient
        }
    }

    /// Primary accent color for interactive elements and highlights.
    var accentColor: Color {
        switch self {
        case .immersive: Color(red: 0.00, green: 0.71, blue: 0.85) // #00B4D8
        case .neonRhythm: Color(red: 1.00, green: 0.00, blue: 0.43) // #FF006E
        case .sargamGlass: .rangNeel // #3F51B5
        case .midnight: Color(red: 0.96, green: 0.65, blue: 0.14) // #F5A623
        case .synthesia: Color(red: 0.30, green: 0.69, blue: 0.31) // #4CAF50
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
        case .immersive: Color(red: 0.00, green: 0.63, blue: 1.00) // #00A0FF
        case .neonRhythm: Color(red: 1.00, green: 0.00, blue: 0.43) // #FF006E
        case .sargamGlass: .rangNeel
        case .midnight: Color(red: 0.96, green: 0.65, blue: 0.14) // #F5A623
        case .synthesia: Color(red: 0.30, green: 0.69, blue: 0.31) // #4CAF50
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
        case .immersive: "Immersive"
        case .neonRhythm: "Neon Rhythm"
        case .sargamGlass: "Sargam Glass"
        case .midnight: "Midnight"
        case .synthesia: "Synthesia"
        // TODO(Task 1.4-1.8): refine displayName for v2 bar presets
        case .sargamGlassBars: "Sargam"
        case .immersiveBars: "Western"
        case .midnightBars: "Night"
        case .popEra: "Pop Era"
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
}
