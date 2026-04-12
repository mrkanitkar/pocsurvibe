import Foundation
import SVCore
import SwiftUI

/// Manages the active app theme and resolves colors for the current color scheme.
///
/// Injected into the SwiftUI environment at the app root via
/// `.environment(themeManager)` in `SurVibeApp`. Views read the
/// resolved theme definition for colors and visual properties.
///
/// ## Performance
/// The manager resolves colors ONCE when the preset or color scheme
/// changes — never per frame. Performance-critical views
/// (`FallingNotesView`, `InteractivePianoView`) must NOT read this
/// via `@Environment`. Instead, `SongPlayAlongView` reads it once
/// and passes resolved values as `let` parameters to children.
///
/// ## Persistence
/// The selected preset is stored in `UserDefaults["appThemePreset"]`.
/// On first launch (key absent), defaults to `.immersive`.
@MainActor @Observable
final class AppThemeManager {

    // MARK: - Properties

    /// The currently active theme preset.
    private(set) var currentPreset: AppThemePreset

    /// Resolved color set for the current preset and system color scheme.
    ///
    /// Updated whenever `currentPreset` or `colorScheme` changes.
    /// Views should read individual properties from this struct.
    private(set) var resolved: AppThemeDefinition

    /// The last-known system color scheme, used for re-resolution.
    private var lastColorScheme: ColorScheme

    // MARK: - Storage Key

    /// UserDefaults key for persisting the selected theme.
    private static let storageKey = "appThemePreset"

    // MARK: - Initialization

    /// Creates the theme manager, restoring the persisted theme
    /// or defaulting to `.immersive`.
    ///
    /// - Parameter colorScheme: The initial system color scheme.
    ///   Defaults to `.light`; updated via `updateColorScheme(_:)`
    ///   when the system setting changes.
    init(colorScheme: ColorScheme = .light) {
        let storedRaw = UserDefaults.standard.string(forKey: Self.storageKey)
        let preset = AppThemePreset(rawValue: storedRaw ?? "") ?? .immersive
        self.currentPreset = preset
        self.lastColorScheme = colorScheme
        self.resolved = AppThemeDefinition.resolve(
            preset: preset,
            colorScheme: colorScheme
        )
    }

    // MARK: - Public Methods

    /// Apply a new theme preset.
    ///
    /// Persists the selection to UserDefaults, resolves colors for
    /// the current color scheme, and updates the `resolved` property.
    ///
    /// - Parameter preset: The theme to apply.
    func apply(_ preset: AppThemePreset, source: String = "profile") {
        currentPreset = preset
        UserDefaults.standard.set(preset.rawValue, forKey: Self.storageKey)
        resolved = AppThemeDefinition.resolve(
            preset: preset,
            colorScheme: lastColorScheme
        )
        AnalyticsManager.shared.track(
            .themeChanged,
            properties: ["theme": preset.rawValue, "source": source]
        )
    }

    /// Update the resolved colors when the system color scheme changes.
    ///
    /// Called from `ContentView.onChange(of: colorScheme)`.
    ///
    /// - Parameter colorScheme: The new system color scheme.
    func updateColorScheme(_ colorScheme: ColorScheme) {
        guard colorScheme != lastColorScheme else { return }
        lastColorScheme = colorScheme
        resolved = AppThemeDefinition.resolve(
            preset: currentPreset,
            colorScheme: colorScheme
        )
    }
}
