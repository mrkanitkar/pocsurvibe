// Packages/SVCore/Sources/SVCore/FeatureFlags/FeatureFlagStoring.swift
import Foundation

/// Read/write access to feature-flag state.
///
/// Callers from non-main actors must hop to MainActor before invoking.
@MainActor
public protocol FeatureFlagStoring: AnyObject {
    /// Returns `true` if the flag is currently enabled.
    func isEnabled(_ flag: FeatureFlag) -> Bool
    /// Sets the flag's enabled state and persists the change.
    func setEnabled(_ flag: FeatureFlag, _ enabled: Bool)
}
