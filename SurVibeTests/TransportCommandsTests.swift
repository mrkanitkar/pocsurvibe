// SurVibeTests/TransportCommandsTests.swift
import SwiftUI
import Testing
@testable import SurVibe
@testable import SVCore

@MainActor
@Suite("TransportCommands")
struct TransportCommandsTests {

    private func makeActions(
        playPause: @escaping () -> Void = {},
        seekBack: @escaping () -> Void = {},
        seekFwd: @escaping () -> Void = {},
        stop: @escaping () -> Void = {}
    ) -> TransportActions {
        TransportActions(
            playPause: playPause,
            seekBackward: seekBack,
            seekForward: seekFwd,
            stop: stop
        )
    }

    @Test func performPlayPauseInvokesActionClosure() {
        var calls = 0
        let actions = makeActions(playPause: { calls += 1 })
        TransportCommands.performPlayPause(actions)
        #expect(calls == 1)
    }

    @Test func performSeekBackwardInvokesActionClosure() {
        var calls = 0
        let actions = makeActions(seekBack: { calls += 1 })
        TransportCommands.performSeekBackward(actions)
        #expect(calls == 1)
    }

    @Test func performSeekForwardInvokesActionClosure() {
        var calls = 0
        let actions = makeActions(seekFwd: { calls += 1 })
        TransportCommands.performSeekForward(actions)
        #expect(calls == 1)
    }

    @Test func performStopInvokesActionClosure() {
        var calls = 0
        let actions = makeActions(stop: { calls += 1 })
        TransportCommands.performStop(actions)
        #expect(calls == 1)
    }

    @Test func performActionsFireShortcutInvokedAnalytics() {
        let provider = MockAnalyticsProvider()

        TransportCommands.performPlayPause(makeActions(), analytics: provider)
        TransportCommands.performSeekBackward(makeActions(), analytics: provider)
        TransportCommands.performSeekForward(makeActions(), analytics: provider)
        TransportCommands.performStop(makeActions(), analytics: provider)

        let actions = provider.trackedEvents
            .filter { $0.event == .shortcutInvoked }
            .compactMap { $0.properties?["action"] as? String }

        #expect(actions.contains("transport.playPause"))
        #expect(actions.contains("transport.seekBackward"))
        #expect(actions.contains("transport.seekForward"))
        #expect(actions.contains("transport.stop"))
    }

    @Test func performWithNilActionsDoesNotCrashAndStillLogsAnalytics() {
        let provider = MockAnalyticsProvider()
        TransportCommands.performPlayPause(nil, analytics: provider)
        #expect(provider.trackedEvents.contains { $0.event == .shortcutInvoked })
    }
}
