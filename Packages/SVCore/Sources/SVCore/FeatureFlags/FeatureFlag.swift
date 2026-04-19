// Packages/SVCore/Sources/SVCore/FeatureFlags/FeatureFlag.swift
import Foundation

/// Development-time feature flags. Every flag defaults to `false` and is
/// toggled only from the debug UI or tests.
///
/// Reused across SP-3 (PlayAlongViewModel A/B), SP-5 (on-device AI gate),
/// and SP-6 (Mac destination enablement).
public enum FeatureFlag: String, CaseIterable, Sendable {
    /// SP-3: new split-out PlayAlong view-model architecture.
    case playAlongViewModelV2
    /// SP-5: gate for on-device Generative AI features.
    case onDeviceAI
    /// SP-6: Mac destination build path.
    case macDestination
}
