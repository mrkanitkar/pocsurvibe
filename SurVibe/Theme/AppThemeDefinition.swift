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

    // MARK: - v2 Phase 3 — Learn-tab tokens

    /// Divider / progress-track color. Light mode and dark variants resolved
    /// via `AppThemePreset.dividerColor` / `darkDividerColor`.
    let dividerColor: Color

    /// Nested surface color — for chips, capsules, and inset content inside
    /// a `cardBackgroundColor` container. Preserves elevation hierarchy.
    let nestedSurfaceColor: Color

    /// Warning / attention feedback color — for time pressure, streak-at-risk,
    /// and attention cues.
    let warningColor: Color

    // MARK: - Factory

    /// Resolve a theme preset for a given color scheme, with Pop Era and Dim Mode awareness.
    ///
    /// Called once by `AppThemeManager` when the preset, era, color scheme, or dim
    /// mode changes. The returned struct is stored and passed by value.
    ///
    /// When `dimMode` is `true`, the background gradient colors are rendered at
    /// 88% opacity, reducing perceived brightness for late-night practice without
    /// mutating every color token in the theme.
    ///
    /// - Parameters:
    ///   - preset: The selected theme preset.
    ///   - popEra: The active Pop Era sub-theme. Defaults to `.olivia`.
    ///   - colorScheme: The current system color scheme.
    ///   - dimMode: Whether Dim Mode is active. Defaults to `false`.
    /// - Returns: A fully resolved `AppThemeDefinition` ready for use in views.
    static func resolve(
        preset: AppThemePreset,
        popEra: PopEra = .olivia,
        colorScheme: ColorScheme,
        dimMode: Bool = false
    ) -> AppThemeDefinition {
        let isDark = preset.isInherentlyDark || colorScheme == .dark
        let dimMultiplier: Double = dimMode ? 0.88 : 1.0

        let baseGradient = isDark ? preset.darkBackgroundGradient : preset.backgroundGradient
        let resolvedGradient = dimMode
            ? baseGradient.map { $0.opacity(dimMultiplier) }
            : baseGradient

        return AppThemeDefinition(
            backgroundGradient: resolvedGradient,
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
            notationSecondaryColor: isDark ? preset.darkNotationSecondaryColor : preset.notationSecondaryColor,

            dividerColor: isDark ? preset.darkDividerColor : preset.dividerColor,
            nestedSurfaceColor: isDark ? preset.darkNestedSurfaceColor : preset.nestedSurfaceColor,
            warningColor: isDark ? preset.darkWarningColor : preset.warningColor
        )
    }

    /// Backward-compatible overload — drops `popEra` and `dimMode`, both default to off.
    static func resolve(preset: AppThemePreset, colorScheme: ColorScheme) -> AppThemeDefinition {
        resolve(preset: preset, popEra: .olivia, colorScheme: colorScheme, dimMode: false)
    }
}
