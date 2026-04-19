// SurVibeTests/AppCommandsTests.swift
import SwiftUI
import Testing
@testable import SurVibe
@testable import SVCore

/// Behavioural tests for `AppCommands`. We do not render the `Commands`
/// view hierarchy — we invoke the underlying action closures directly by
/// reproducing what a `.keyboardShortcut` press would do (call
/// `router.switchTab` and `analytics.track`).
///
/// This keeps the test fast and isolated from SwiftUI scene machinery.
@MainActor
@Suite("AppCommands")
struct AppCommandsTests {

    @Test func tabSwitchActionUpdatesRouterCurrentTab() {
        for tab in AppTab.allCases {
            let router = AppRouter()
            AppCommands.performTabSwitch(tab, router: router)
            #expect(router.currentTab == tab,
                    "Switching to \(tab) should update router.currentTab")
        }
    }

    @Test func tabSwitchFiresShortcutInvokedAnalytics() {
        let router = AppRouter()
        let provider = MockAnalyticsProvider()
        AppCommands.performTabSwitch(.learn, router: router, analytics: provider)

        let hit = provider.trackedEvents.first { $0.event == .shortcutInvoked }
        #expect(hit != nil)
        #expect(hit?.properties?["action"] as? String == "tab.\(AppTab.learn.label)")
    }

    @Test func preferencesActionFiresShortcutInvokedAnalytics() {
        let provider = MockAnalyticsProvider()
        AppCommands.performPreferences(analytics: provider)

        let hit = provider.trackedEvents.first { $0.event == .shortcutInvoked }
        #expect(hit != nil)
        #expect(hit?.properties?["action"] as? String == "preferences")
    }
}
