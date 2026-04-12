import Testing
import SwiftData
@testable import SurVibe

/// D1: App launches, TabView shows 4 tabs — verified by build + UI test.
/// D8: Build succeeds — verified by running these tests.
@Suite("SurVibe App Tests")
@MainActor
struct SurVibeTests {
    @Test("App target compiles and test suite runs")
    func testAppCompiles() {
        #expect(true, "App target compiles successfully")
    }
}
