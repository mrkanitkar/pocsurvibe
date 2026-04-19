// SurVibe/Commands/TransportCommands.swift
import SVCore
import SwiftUI

/// Menu-bar commands for play-along transport. Shortcuts dispatch only
/// when a play-along surface publishes `\.transportActions` via
/// `.focusedSceneValue`; otherwise the buttons are disabled.
///
/// `AnalyticsManager.shared.track(.shortcutInvoked)` fires on every action
/// — even when the action closure is nil (useful for tracking menu-bar
/// engagement independent of the focus state).
struct TransportCommands: Commands {
    @FocusedValue(\.transportActions)
    private var transport

    var body: some Commands {
        CommandMenu("Playback") {
            Button("Play / Pause") {
                Self.performPlayPause(transport)
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(transport == nil)

            Button("Seek Backward 5s") {
                Self.performSeekBackward(transport)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(transport == nil)

            Button("Seek Forward 5s") {
                Self.performSeekForward(transport)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(transport == nil)

            Button("Stop") {
                Self.performStop(transport)
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(transport == nil)
        }
    }

    // MARK: - Testable static actions

    /// Invokes the play/pause action and fires a `shortcutInvoked` analytics event.
    ///
    /// - Parameters:
    ///   - actions: The `TransportActions` published by the focused surface, or `nil`
    ///     when no play-along surface is focused.
    ///   - analytics: Analytics provider to receive the event. Pass `nil` to use
    ///     `AnalyticsManager.shared` (the default). Pass a mock in tests.
    @MainActor
    static func performPlayPause(
        _ actions: TransportActions?,
        analytics: (any AnalyticsProviding)? = nil
    ) {
        actions?.playPause()
        let provider: any AnalyticsProviding = analytics ?? AnalyticsManager.shared
        provider.track(.shortcutInvoked, properties: ["action": "transport.playPause"])
    }

    /// Invokes the seek-backward action and fires a `shortcutInvoked` analytics event.
    ///
    /// - Parameters:
    ///   - actions: The `TransportActions` published by the focused surface, or `nil`
    ///     when no play-along surface is focused.
    ///   - analytics: Analytics provider to receive the event. Pass `nil` to use
    ///     `AnalyticsManager.shared` (the default). Pass a mock in tests.
    @MainActor
    static func performSeekBackward(
        _ actions: TransportActions?,
        analytics: (any AnalyticsProviding)? = nil
    ) {
        actions?.seekBackward()
        let provider: any AnalyticsProviding = analytics ?? AnalyticsManager.shared
        provider.track(.shortcutInvoked, properties: ["action": "transport.seekBackward"])
    }

    /// Invokes the seek-forward action and fires a `shortcutInvoked` analytics event.
    ///
    /// - Parameters:
    ///   - actions: The `TransportActions` published by the focused surface, or `nil`
    ///     when no play-along surface is focused.
    ///   - analytics: Analytics provider to receive the event. Pass `nil` to use
    ///     `AnalyticsManager.shared` (the default). Pass a mock in tests.
    @MainActor
    static func performSeekForward(
        _ actions: TransportActions?,
        analytics: (any AnalyticsProviding)? = nil
    ) {
        actions?.seekForward()
        let provider: any AnalyticsProviding = analytics ?? AnalyticsManager.shared
        provider.track(.shortcutInvoked, properties: ["action": "transport.seekForward"])
    }

    /// Invokes the stop action and fires a `shortcutInvoked` analytics event.
    ///
    /// - Parameters:
    ///   - actions: The `TransportActions` published by the focused surface, or `nil`
    ///     when no play-along surface is focused.
    ///   - analytics: Analytics provider to receive the event. Pass `nil` to use
    ///     `AnalyticsManager.shared` (the default). Pass a mock in tests.
    @MainActor
    static func performStop(
        _ actions: TransportActions?,
        analytics: (any AnalyticsProviding)? = nil
    ) {
        actions?.stop()
        let provider: any AnalyticsProviding = analytics ?? AnalyticsManager.shared
        provider.track(.shortcutInvoked, properties: ["action": "transport.stop"])
    }
}
