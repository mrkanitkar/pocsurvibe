import SVCore

/// Mock analytics provider for testing event tracking.
///
/// Records all tracked events and identify calls for assertion in tests.
@MainActor
final class MockAnalyticsProvider: AnalyticsProviding {
    /// All events tracked via `track(_:properties:)`, in order.
    var trackedEvents: [(event: AnalyticsEvent, properties: [String: any Sendable]?)] = []

    /// The most recently identified user ID, if any.
    var identifiedUserId: String?

    func track(_ event: AnalyticsEvent, properties: [String: any Sendable]?) {
        trackedEvents.append((event, properties))
    }

    func identify(userId: String) {
        identifiedUserId = userId
    }
}
