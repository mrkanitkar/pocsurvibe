// Packages/SVCore/Sources/SVCore/FeatureFlags/FeatureFlagStore.swift
import Foundation
import Observation

/// `@Observable`, `@MainActor` store for feature-flag state.
///
/// Uses `UserDefaults` for persistence. SwiftUI views observe `cache` access,
/// so toggles in the debug UI re-render automatically.
///
/// Flags default to `false` across the lifetime of a fresh install.
///
/// The `analytics` parameter accepts any `AnalyticsProviding` implementation,
/// enabling test-injection without modifying `AnalyticsManager`.
@MainActor
@Observable
public final class FeatureFlagStore: FeatureFlagStoring {

    /// Shared instance used by production code.
    public static let shared = FeatureFlagStore()

    private let defaults: UserDefaults
    private let analytics: any AnalyticsProviding
    /// Observation mirror — `UserDefaults` is not observable by `@Observable`.
    private var cache: [FeatureFlag: Bool]

    /// Creates a `FeatureFlagStore`.
    ///
    /// - Parameters:
    ///   - defaults: The `UserDefaults` suite used for flag persistence.
    ///     Defaults to `.standard`. Pass a named suite in tests to avoid cross-test pollution.
    ///   - analytics: The analytics provider used to record flag toggles.
    ///     Defaults to `AnalyticsManager.shared`. Pass a mock in tests for assertion.
    public init(
        defaults: UserDefaults = .standard,
        analytics: any AnalyticsProviding = AnalyticsManager.shared
    ) {
        self.defaults = defaults
        self.analytics = analytics
        self.cache = Dictionary(
            uniqueKeysWithValues: FeatureFlag.allCases.map {
                ($0, defaults.bool(forKey: Self.key($0)))
            }
        )
    }

    /// Returns `true` if the flag is currently enabled.
    ///
    /// - Parameter flag: The feature flag to query.
    /// - Returns: The flag's current enabled state; `false` if never set.
    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        cache[flag] ?? false
    }

    /// Sets the flag's enabled state, persists it to `UserDefaults`,
    /// and fires a `featureFlagToggled` analytics event.
    ///
    /// - Parameters:
    ///   - flag: The feature flag to update.
    ///   - enabled: The new enabled state.
    public func setEnabled(_ flag: FeatureFlag, _ enabled: Bool) {
        cache[flag] = enabled
        defaults.set(enabled, forKey: Self.key(flag))
        analytics.track(
            .featureFlagToggled,
            properties: ["flag": flag.rawValue, "enabled": enabled]
        )
    }

    /// Returns the `UserDefaults` key for a given flag.
    ///
    /// - Parameter flag: The feature flag.
    /// - Returns: A dot-prefixed key string, e.g. `"ff.onDeviceAI"`.
    private static func key(_ flag: FeatureFlag) -> String { "ff.\(flag.rawValue)" }
}
