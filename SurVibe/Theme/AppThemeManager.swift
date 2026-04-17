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
@MainActor
@Observable
final class AppThemeManager {

    // MARK: - Properties

    /// The currently active theme preset.
    private(set) var currentPreset: AppThemePreset

    /// The currently active Pop Era sub-theme.
    ///
    /// Only meaningful when `currentPreset == .popEra`. Persisted
    /// separately at `UserDefaults["appThemePopEra"]` so the user's
    /// sub-theme choice survives switching to another main preset
    /// and back.
    private(set) var popEra: PopEra

    /// Resolved color set for the current preset and system color scheme.
    ///
    /// Updated whenever `currentPreset` or `colorScheme` changes.
    /// Views should read individual properties from this struct.
    private(set) var resolved: AppThemeDefinition

    /// The last-known system color scheme, used for re-resolution.
    private var lastColorScheme: ColorScheme

    // MARK: - Storage Keys

    /// UserDefaults key for persisting the selected theme.
    private static let storageKey = "appThemePreset"

    /// UserDefaults key for persisting the selected Pop Era sub-theme.
    private static let popEraKey = "appThemePopEra"

    /// UserDefaults key for tracking whether v1→v2 rawValue migration has run.
    ///
    /// Set to `true` after the first init that observes (or creates) a
    /// persisted preset value. Prevents re-migration if a user manually
    /// flips the stored rawValue back to a legacy case.
    private static let migrationFlagKey = "appThemeMigratedV2"

    // MARK: - Initialization

    /// Creates the theme manager, restoring the persisted theme
    /// or defaulting to `.sargamGlassBars`.
    ///
    /// On first launch after v2 (detected via missing `appThemeMigratedV2`
    /// flag) any legacy rawValue stored at `appThemePreset` is remapped
    /// to its v2 equivalent via `AppThemePreset.migrateFromV1(_:)`, then
    /// the flag is set so migration never runs again.
    ///
    /// - Parameter colorScheme: The initial system color scheme.
    ///   Defaults to `.light`; updated via `updateColorScheme(_:)`
    ///   when the system setting changes.
    init(colorScheme: ColorScheme = .light) {
        let defaults = UserDefaults.standard
        let migrated = defaults.bool(forKey: Self.migrationFlagKey)
        let storedRaw = defaults.string(forKey: Self.storageKey)

        let preset: AppThemePreset
        if !migrated, let raw = storedRaw {
            preset = AppThemePreset.migrateFromV1(raw)
            defaults.set(preset.rawValue, forKey: Self.storageKey)
            defaults.set(true, forKey: Self.migrationFlagKey)
        } else if let raw = storedRaw, let direct = AppThemePreset(rawValue: raw) {
            preset = direct
        } else {
            preset = .sargamGlassBars
            defaults.set(preset.rawValue, forKey: Self.storageKey)
            defaults.set(true, forKey: Self.migrationFlagKey)
        }

        let storedEra = defaults.string(forKey: Self.popEraKey).flatMap(PopEra.init(rawValue:)) ?? .olivia

        self.currentPreset = preset
        self.popEra = storedEra
        self.lastColorScheme = colorScheme
        self.resolved = AppThemeDefinition.resolve(
            preset: preset,
            popEra: storedEra,
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
            popEra: popEra,
            colorScheme: lastColorScheme
        )
        AnalyticsManager.shared.track(
            .themeChanged,
            properties: ["theme": preset.rawValue, "source": source]
        )
    }

    /// Update the Pop Era sub-theme.
    ///
    /// Persists to UserDefaults and re-resolves the theme definition.
    /// Only has visible effect when `currentPreset == .popEra`.
    ///
    /// - Parameter era: The era to apply.
    func setEra(_ era: PopEra) {
        popEra = era
        UserDefaults.standard.set(era.rawValue, forKey: Self.popEraKey)
        resolved = AppThemeDefinition.resolve(
            preset: currentPreset,
            popEra: era,
            colorScheme: lastColorScheme
        )
        AnalyticsManager.shared.track(
            .themeChanged,
            properties: ["era": era.rawValue, "source": "era_picker"]
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
            popEra: popEra,
            colorScheme: colorScheme
        )
    }
}
