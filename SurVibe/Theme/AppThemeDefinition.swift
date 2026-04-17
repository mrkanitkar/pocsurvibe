import SwiftUI

/// Resolved color set for a specific theme preset and color scheme.
///
/// `AppThemeManager` creates this struct once when the theme or
/// system color scheme changes. Views read these resolved values
/// as `let` parameters — never recomputed per frame.
///
/// ## Performance
/// This struct is a value type passed to child views as parameters.
/// Performance-critical views (`FallingNotesView`, `InteractivePianoView`)
/// receive individual color values from this struct — they must NEVER
/// read `@Environment(AppThemeManager.self)` directly, which would
/// trigger 60-120 Hz re-renders from the CADisplayLink highlight path.
struct AppThemeDefinition: Sendable {

    // MARK: - v1 properties (existing)

    /// Background gradient colors for the current color scheme.
    let backgroundGradient: [Color]

    /// Surface color for cards, panels, and overlays.
    let surfaceColor: Color

    /// Primary accent color for buttons, links, and interactive elements.
    let accentColor: Color

    /// Playhead cursor color in notation views.
    let playheadColor: Color

    /// Primary text color (light on dark backgrounds, dark on light).
    let primaryTextColor: Color

    /// Secondary text color for subtitles and supporting info.
    let secondaryTextColor: Color

    /// Whether the piano keyboard uses dark styling.
    let usesDarkPiano: Bool

    /// Whether piano key highlights use per-note SargamColorMap colors.
    let usesRangColoredPianoKeys: Bool

    /// Whether the current resolved appearance is dark.
    let isDark: Bool

    // MARK: - v2 — hand & chord

    let rightHandColor: Color
    let leftHandColor: Color
    let chordColor: Color

    // MARK: - v2 — surfaces & feedback

    let cardBackgroundColor: Color
    let badgeTextColor: Color
    let successColor: Color
    let errorColor: Color
    let celebrationColors: [Color]

    // MARK: - v2 — karaoke & era

    let karaokeBackgroundColor: Color
    let eraAccentColor: Color

    // MARK: - v2 — notation

    let notationLineColor: Color
    let notationSecondaryColor: Color

    // MARK: - Factory

    /// Resolve a theme preset for a given color scheme, with Pop Era awareness.
    ///
    /// Called once by `AppThemeManager` when the preset, era, or color scheme
    /// changes. The returned struct is stored and passed by value.
    static func resolve(
        preset: AppThemePreset,
        popEra: PopEra = .olivia,
        colorScheme: ColorScheme
    ) -> AppThemeDefinition {
        let isDark = preset.isInherentlyDark || colorScheme == .dark

        return AppThemeDefinition(
            backgroundGradient: isDark ? preset.darkBackgroundGradient : preset.backgroundGradient,
            surfaceColor: isDark ? preset.darkSurfaceColor : preset.surfaceColor,
            accentColor: preset == .popEra
                ? preset.eraAccentColor(for: popEra)
                : preset.accentColor,
            playheadColor: preset == .popEra
                ? preset.eraAccentColor(for: popEra)
                : preset.playheadColor,
            primaryTextColor: isDark ? .white : Color(.label),
            secondaryTextColor: isDark ? .white.opacity(0.6) : Color(.secondaryLabel),
            usesDarkPiano: preset.usesDarkPiano || colorScheme == .dark,
            usesRangColoredPianoKeys: preset.usesRangColoredPianoKeys,
            isDark: isDark,

            rightHandColor: isDark ? preset.darkRightHandColor : preset.rightHandColor,
            leftHandColor: isDark ? preset.darkLeftHandColor : preset.leftHandColor,
            chordColor: isDark ? preset.darkChordColor : preset.chordColor,

            cardBackgroundColor: isDark ? preset.darkCardBackgroundColor : preset.cardBackgroundColor,
            badgeTextColor: isDark ? preset.darkBadgeTextColor : preset.badgeTextColor,
            successColor: isDark ? preset.darkSuccessColor : preset.successColor,
            errorColor: isDark ? preset.darkErrorColor : preset.errorColor,
            celebrationColors: isDark ? preset.darkCelebrationColors : preset.celebrationColors,

            karaokeBackgroundColor: isDark ? preset.darkKaraokeBackgroundColor : preset.karaokeBackgroundColor,
            eraAccentColor: isDark
                ? preset.darkEraAccentColor(for: popEra)
                : preset.eraAccentColor(for: popEra),

            notationLineColor: isDark ? preset.darkNotationLineColor : preset.notationLineColor,
            notationSecondaryColor: isDark ? preset.darkNotationSecondaryColor : preset.notationSecondaryColor
        )
    }

    /// Backward-compatible overload (drops popEra, defaults to .olivia).
    static func resolve(preset: AppThemePreset, colorScheme: ColorScheme) -> AppThemeDefinition {
        resolve(preset: preset, popEra: .olivia, colorScheme: colorScheme)
    }
}
