import SVCore
import Testing

@testable import SurVibe

@Suite("MockAnalyticsProvider Tests")
@MainActor
struct MockAnalyticsProviderTests {
    @Test("Initially has no tracked events")
    func initiallyEmpty() {
        let mock = MockAnalyticsProvider()
        #expect(mock.trackedEvents.isEmpty)
        #expect(mock.identifiedUserId == nil)
    }

    @Test("track records events in order")
    func trackRecordsEvents() {
        let mock = MockAnalyticsProvider()
        mock.track(.appScaffoldingLoaded, properties: nil)
        mock.track(.tabSelected, properties: ["tab": "home"])
        #expect(mock.trackedEvents.count == 2)
        #expect(mock.trackedEvents[0].event == .appScaffoldingLoaded)
        #expect(mock.trackedEvents[1].event == .tabSelected)
    }

    @Test("track preserves properties")
    func trackPreservesProperties() {
        let mock = MockAnalyticsProvider()
        mock.track(.sessionStarted, properties: ["duration_ms": 500])
        #expect(mock.trackedEvents.count == 1)
        let props = mock.trackedEvents[0].properties
        #expect(props != nil)
    }

    @Test("identify stores user ID")
    func identifyStoresUserId() {
        let mock = MockAnalyticsProvider()
        mock.identify(userId: "user-123")
        #expect(mock.identifiedUserId == "user-123")
    }

    @Test("identify overwrites previous user ID")
    func identifyOverwrites() {
        let mock = MockAnalyticsProvider()
        mock.identify(userId: "user-1")
        mock.identify(userId: "user-2")
        #expect(mock.identifiedUserId == "user-2")
    }
}
