import Foundation

/// Shared error protocol for all SurVibe domain errors.
///
/// Provides a structured contract for cross-package error handling,
/// enabling centralized logging and analytics without coupling
/// packages to each other's concrete error types.
///
/// All domain error enums should conform to this protocol in addition
/// to `LocalizedError` and `Sendable`.
///
/// - Note: The `domain` property groups errors by originating package
///   (e.g., "SVAudio", "SVLearning"). The `code` property provides a
///   machine-readable identifier for analytics tracking.
public protocol SurVibeError: LocalizedError, Sendable {
    /// The originating package domain (e.g., "SVAudio", "SVCore").
    var domain: String { get }
    /// Machine-readable error code for analytics (e.g., "engine_start_failed").
    var code: String { get }
}
