// SurVibe/Commands/AppCommands.swift
import SVCore
import SwiftUI

/// Root-level menu-bar commands for the SurVibe app.
///
/// Provides ⌘1–⌘4 tab switching and ⌘, for Preferences. Shortcut presses
/// dispatch through `AppRouter.switchTab(to:)`; the existing
/// `.onChange(of: router.currentTab)` handler in `ContentView` propagates
/// the update to the TabView's `selectedTab` binding.
///
/// Per-surface commands (transport, find, new) land with SP-2 via
/// `@FocusedValue` for surface-scoped dispatch.
struct AppCommands: Commands {
    let router: AppRouter

    var body: some Commands {
        CommandMenu("Navigate") {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button(tab.label) {
                    Self.performTabSwitch(tab, router: router)
                }
                .keyboardShortcut(tab.keyEquivalent, modifiers: .command)
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Preferences…") {
                Self.performPreferences()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    // MARK: - Testable actions

    /// Switches the app's active tab and fires a `shortcutInvoked`
    /// analytics event.
    ///
    /// - Parameters:
    ///   - tab: The target tab to switch to.
    ///   - router: The `AppRouter` instance that owns navigation state.
    ///   - analytics: Analytics provider to receive the event. Pass `nil` to
    ///     use `AnalyticsManager.shared` (the default). Pass a mock in tests.
    @MainActor
    static func performTabSwitch(
        _ tab: AppTab,
        router: AppRouter,
        analytics: (any AnalyticsProviding)? = nil
    ) {
        router.switchTab(to: tab)
        let provider: any AnalyticsProviding = analytics ?? AnalyticsManager.shared
        provider.track(
            .shortcutInvoked,
            properties: ["action": "tab.\(tab.label)"]
        )
    }

    /// Fires the `shortcutInvoked` analytics event for the Preferences
    /// shortcut. On macOS the `CommandGroup(replacing: .appSettings)`
    /// wiring causes AppKit to open the `Settings` scene; on iOS the
    /// shortcut exists in the command tree but renders no user-visible UI.
    ///
    /// - Parameter analytics: Analytics provider to receive the event. Pass
    ///   `nil` to use `AnalyticsManager.shared` (the default). Pass a mock
    ///   in tests.
    @MainActor
    static func performPreferences(
        analytics: (any AnalyticsProviding)? = nil
    ) {
        let provider: any AnalyticsProviding = analytics ?? AnalyticsManager.shared
        provider.track(
            .shortcutInvoked,
            properties: ["action": "preferences"]
        )
    }
}
