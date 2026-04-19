// Packages/SVCore/Tests/SVCoreTests/TestDoubles/MockAnalyticsProvider.swift
import Foundation
@testable import SVCore

/// Minimal mock analytics provider for SVCoreTests.
///
/// Records all tracked events for assertion in unit tests.
/// Conforms to `AnalyticsProviding` — no PostHog dependency.
@MainActor
final class MockAnalyticsProvider: AnalyticsProviding {

    /// A captured analytics call.
    struct TrackedEvent {
        let event: AnalyticsEvent
        let properties: [String: any Sendable]?
    }

    /// All events tracked via `track(_:properties:)`, in order.
    private(set) var tracked: [TrackedEvent] = []

    /// The most recently identified user ID, if any.
    private(set) var identifiedUserId: String?

    func track(_ event: AnalyticsEvent, properties: [String: any Sendable]?) {
        tracked.append(TrackedEvent(event: event, properties: properties))
    }

    func identify(userId: String) {
        identifiedUserId = userId
    }

    /// Clears all captured state for test isolation.
    func reset() {
        tracked = []
        identifiedUserId = nil
    }
}
