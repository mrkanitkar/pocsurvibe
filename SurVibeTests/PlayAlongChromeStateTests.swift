// SurVibeTests/PlayAlongChromeStateTests.swift
import Foundation
import SVCore
import SwiftUI
import Testing

@testable import SurVibe

/// Unit tests for `PlayAlongChromeState` (SP-3c).
///
/// `PlayAlongChromeState` owns chrome visibility, view/notation modes, and
/// resolved theme colors — the UI presentation domain extracted from
/// `PlayAlongViewModel`. No audio, no SwiftData, no concurrency boundaries
/// beyond the auto-hide `Task`.
@MainActor
@Suite("PlayAlongChromeState")
struct PlayAlongChromeStateTests {

    // MARK: - Helpers

    /// Clears theme-related UserDefaults entries so `AppThemeManager`
    /// always starts from a clean, deterministic state (`.sargamGlassBars`).
    private static func clearThemeDefaults() {
        UserDefaults.standard.removeObject(forKey: "appThemePreset")
        UserDefaults.standard.removeObject(forKey: "appThemePopEra")
        UserDefaults.standard.removeObject(forKey: "appThemeMigratedV2")
    }

    // MARK: - Tests

    @Test
    func initialStateIsSummonedAndHasDefaultModes() {
        let chrome = PlayAlongChromeState()

        #expect(chrome.chromeVisibility == .summoned, "Starts summoned so users see controls on first open")
        #expect(chrome.viewMode == .fallingNotes, "Default view mode")
        #expect(chrome.notationMode == .sargam, "Default notation mode")
    }

    @Test
    func summonChromeShowsItAndStartsAutoHideTimer() async throws {
        let chrome = PlayAlongChromeState()
        chrome.hideChrome()
        #expect(chrome.chromeVisibility == .hidden)

        chrome.summonChrome()
        #expect(chrome.chromeVisibility == .summoned)

        // Auto-hide timer should be scheduled — wait past the constant duration.
        try await Task.sleep(for: .seconds(PlayAlongChromeState.autoHideDuration + 0.5))
        #expect(chrome.chromeVisibility == .hidden, "Auto-hides after autoHideDuration seconds")
    }

    @Test
    func hideChromeImmediatelyCancelsTimer() {
        let chrome = PlayAlongChromeState()
        chrome.summonChrome()
        chrome.hideChrome()

        #expect(chrome.chromeVisibility == .hidden)
    }

    @Test
    func resetAutoHideRestartsTimer() async throws {
        let chrome = PlayAlongChromeState()
        chrome.summonChrome()

        // Wait less than autoHideDuration — chrome should still be visible.
        try await Task.sleep(for: .seconds(PlayAlongChromeState.autoHideDuration / 2))
        chrome.resetAutoHide()
        // Wait another half-duration — would have hidden by now WITHOUT reset.
        try await Task.sleep(for: .seconds(PlayAlongChromeState.autoHideDuration / 2 + 0.1))
        #expect(chrome.chromeVisibility == .summoned, "Reset extended the auto-hide window")
    }

    @Test
    func autoHideDurationConstantIsSixSeconds() {
        // Magic-number elimination per D-SP3c-4.
        #expect(PlayAlongChromeState.autoHideDuration == 6.0)
    }

    @Test
    func updateThemeResolvesAllSevenColors() async {
        Self.clearThemeDefaults()
        let chrome = PlayAlongChromeState()
        let themeManager = AppThemeManager(colorScheme: .light)
        // Apply a known preset so resolved colors are deterministic.
        themeManager.apply(.immersive, source: "test")

        chrome.updateTheme(themeManager)

        #expect(chrome.rhColor == themeManager.resolved.rightHandColor)
        #expect(chrome.lhColor == themeManager.resolved.leftHandColor)
        #expect(chrome.chordColor == themeManager.resolved.chordColor)
        #expect(chrome.notationLineColor == themeManager.resolved.notationLineColor)
        #expect(chrome.notationSecondaryColor == themeManager.resolved.notationSecondaryColor)
        #expect(chrome.cardBackgroundColor == themeManager.resolved.cardBackgroundColor)
        #expect(chrome.karaokeBackgroundColor == themeManager.resolved.karaokeBackgroundColor)
    }
}
