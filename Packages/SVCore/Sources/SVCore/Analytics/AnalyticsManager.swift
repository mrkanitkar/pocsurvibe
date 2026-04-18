import Foundation
import PostHog
import os

/// Thin PostHog analytics wrapper with privacy-first configuration.
/// Uses @MainActor isolation for thread-safe state access.
///
/// Privacy settings applied:
/// - `captureApplicationLifecycleEvents`: disabled
/// - `captureScreenViews`: disabled
/// - `sendFeatureFlagEvent`: disabled
/// - `personProfiles`: `.identifiedOnly`
/// - IP anonymization: requires server-side PostHog project setting
/// - No IDFA collection (no ATTrackingManager usage)
@MainActor
public final class AnalyticsManager: AnalyticsProviding {
    public static let shared = AnalyticsManager()

    /// Whether analytics tracking is enabled. Defaults to true.
    /// Set to false to disable all tracking (user privacy toggle).
    public private(set) var isTrackingEnabled: Bool = true

    /// Whether the SDK has been configured via `configure(apiKey:host:)`.
    public private(set) var isConfigured: Bool = false

    private static let logger = Logger.survibe(category: "Analytics")

    private init() {}

    /// Configure PostHog analytics with privacy mode. Call once at app launch.
    ///
    /// - Parameters:
    ///   - apiKey: PostHog project API key (write-only key, safe in binary). Must not be empty.
    ///   - host: PostHog host URL (defaults to PostHog cloud).
    public func configure(apiKey: String, host: String = "https://app.posthog.com") {
        guard !apiKey.isEmpty else {
            Self.logger.warning("Analytics configure called with empty API key.")
            return
        }
        let config = PostHogConfig(apiKey: apiKey, host: host)

        // Privacy-first configuration
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.sendFeatureFlagEvent = false
        config.personProfiles = .identifiedOnly

        PostHogSDK.shared.setup(config)
        isConfigured = true
        Self.logger.info("Analytics configured with privacy-first settings.")
    }

    /// Track an analytics event with optional properties.
    ///
    /// No-op if tracking is disabled or the SDK is not configured.
    /// PostHog capture is dispatched off `@MainActor` at utility priority to
    /// avoid blocking the UI thread during high-frequency tracking calls.
    ///
    /// - Parameters:
    ///   - event: The event to track, from the `AnalyticsEvent` enum.
    ///   - properties: Optional Sendable key-value metadata (e.g., `["tab": "practice"]`).
    ///     Keys should be `snake_case`. All values must conform to `Sendable`.
    public func track(_ event: AnalyticsEvent, properties: [String: any Sendable]? = nil) {
        guard isTrackingEnabled, isConfigured else { return }
        let eventName = event.rawValue
        // AUD-008: Dispatch PostHog capture off MainActor to avoid blocking UI thread.
        // `properties` is [String: any Sendable]? — safe to send across isolation boundaries.
        // The bridge to PostHog's [String: Any] happens inside the detached Task.
        let sendableProps = properties
        Task.detached(priority: .utility) {
            let posthogProps: [String: Any]? = sendableProps.map { dict in
                dict.mapValues { $0 as Any }
            }
            PostHogSDK.shared.capture(eventName, properties: posthogProps)
        }
        Self.logger.debug("Tracked event: \(eventName, privacy: .public)")
    }

    /// Identify a user for analytics.
    ///
    /// - Parameter userId: Anonymous user identifier (e.g., CloudKit record ID or app-generated UUID).
    ///   Must not contain PII (email, name, phone). Validated in debug builds.
    public func identify(userId: String) {
        guard isTrackingEnabled, isConfigured else { return }

        // AUD-020: PII guard active in ALL builds — not just DEBUG.
        // Reject strings that look like emails, phone numbers, or are too long.
        if userId.contains("@") || userId.hasPrefix("+") || userId.count > 128 {
            Self.logger.error("identify() rejected — userId appears to contain PII.")
            #if DEBUG
            assertionFailure(
                "identify() userId appears to contain PII or exceeds 128 chars: \(userId.prefix(20))..."
            )
            #endif
            return
        }

        PostHogSDK.shared.identify(userId)
        Self.logger.info("User identified for analytics.")
    }

    /// Enable or disable all analytics tracking.
    ///
    /// When disabled, calls PostHog `optOut()`. When re-enabled, calls `optIn()`.
    /// This persists across the session but does not persist across app launches
    /// — the default is always `true`.
    ///
    /// - Parameter enabled: `true` to enable tracking, `false` to disable.
    public func setTrackingEnabled(_ enabled: Bool) {
        isTrackingEnabled = enabled
        if isConfigured {
            if !enabled {
                PostHogSDK.shared.optOut()
                Self.logger.info("Analytics tracking disabled (user opted out).")
            } else {
                PostHogSDK.shared.optIn()
                Self.logger.info("Analytics tracking enabled (user opted in).")
            }
        }
    }

    /// Track a latency performance snapshot from the audio pipeline.
    ///
    /// Accepts decomposed values instead of `PerformanceSnapshot` directly to
    /// avoid a circular dependency (SVCore cannot import SVAudio). The caller
    /// in the app target decomposes the snapshot before calling this method.
    ///
    /// Fires the `.latencySnapshot` event with six diagnostic properties.
    ///
    /// - Parameters:
    ///   - p50: Median latency in microseconds.
    ///   - p95: 95th percentile latency in microseconds.
    ///   - p99: 99th percentile latency in microseconds.
    ///   - droppedFrames: Number of dropped display frames.
    ///   - bufferFillLevel: SPSC ring buffer fill level (0.0--1.0).
    ///   - probeCount: Number of completed latency probe measurements.
    public func trackLatencySnapshot(
        p50: UInt64,
        p95: UInt64,
        p99: UInt64,
        droppedFrames: Int,
        bufferFillLevel: Double,
        probeCount: Int
    ) {
        track(.latencySnapshot, properties: [
            "p50_micros": p50,
            "p95_micros": p95,
            "p99_micros": p99,
            "dropped_frames": droppedFrames,
            "buffer_fill_level": bufferFillLevel,
            "probe_count": probeCount,
        ])
    }

    /// Reset analytics identity and clear all cached state.
    ///
    /// Call on user logout to ensure the next user gets a fresh analytics session.
    /// No-op if the SDK is not configured.
    public func reset() {
        guard isConfigured else { return }
        PostHogSDK.shared.reset()
        Self.logger.info("Analytics identity reset.")
    }
}
