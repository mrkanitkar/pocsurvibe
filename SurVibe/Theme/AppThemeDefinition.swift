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

    // MARK: - Background & Surfaces

    /// Background gradient colors for the current color scheme.
    let backgroundGradient: [Color]

    /// Surface color for cards, panels, and overlays.
    let surfaceColor: Color

    // MARK: - Accent & Highlights

    /// Primary accent color for buttons, links, and interactive elements.
    let accentColor: Color

    /// Playhead cursor color in notation views.
    let playheadColor: Color

    // MARK: - Text

    /// Primary text color (light on dark backgrounds, dark on light).
    let primaryTextColor: Color

    /// Secondary text color for subtitles and supporting info.
    let secondaryTextColor: Color

    // MARK: - Piano

    /// Whether the piano keyboard uses dark styling.
    let usesDarkPiano: Bool

    /// Whether piano key highlights use per-note SargamColorMap colors.
    let usesRangColoredPianoKeys: Bool

    // MARK: - Metadata

    /// Whether the current resolved appearance is dark.
    let isDark: Bool

    // MARK: - Factory

    /// Resolve a theme preset for a given color scheme.
    ///
    /// Called once by `AppThemeManager` when the preset or color scheme
    /// changes. The returned struct is stored and passed by value.
    ///
    /// - Parameters:
    ///   - preset: The active theme preset.
    ///   - colorScheme: The current system color scheme.
    /// - Returns: Fully resolved theme definition.
    static func resolve(
        preset: AppThemePreset,
        colorScheme: ColorScheme
    ) -> AppThemeDefinition {
        let isDark = preset.isInherentlyDark || colorScheme == .dark

        let gradient = isDark ? preset.darkBackgroundGradient : preset.backgroundGradient
        let surface = isDark ? preset.darkSurfaceColor : preset.surfaceColor

        return AppThemeDefinition(
            backgroundGradient: gradient,
            surfaceColor: surface,
            accentColor: preset.accentColor,
            playheadColor: preset.playheadColor,
            primaryTextColor: isDark ? .white : Color(.label),
            secondaryTextColor: isDark
                ? .white.opacity(0.6)
                : Color(.secondaryLabel),
            usesDarkPiano: preset.usesDarkPiano || colorScheme == .dark,
            usesRangColoredPianoKeys: preset.usesRangColoredPianoKeys,
            isDark: isDark
        )
    }
}
