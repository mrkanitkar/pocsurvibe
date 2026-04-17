import Foundation
import SwiftUI
import Testing
@testable import SurVibe

/// End-to-end smoke test for the 9-theme + PlayAlong redesign.
///
/// Exercises the theme system, Pop Era sub-selection, chrome visibility,
/// and legacy-rawValue migration through the PlayAlongViewModel surface.
/// These tests are distinct from `PlayAlongIntegrationTests` (which covers
/// session lifecycle / tempo / scoring) — they lock the v2 theme contract.
struct PlayAlongThemeIntegrationTests {

    private static func clearUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "appThemePreset")
        UserDefaults.standard.removeObject(forKey: "appThemePopEra")
        UserDefaults.standard.removeObject(forKey: "appThemeMigratedV2")
    }

    @Test @MainActor func endToEndThemeSwitchPropagatesColors() {
        Self.clearUserDefaults()

        let themeManager = AppThemeManager(colorScheme: .light)
        #expect(themeManager.currentPreset == .sargamGlassBars)

        // Simulate the `.task` push in SongPlayAlongView
        let viewModel = PlayAlongViewModel()
        viewModel.rhColor = themeManager.resolved.rightHandColor
        viewModel.lhColor = themeManager.resolved.leftHandColor
        viewModel.chordColor = themeManager.resolved.chordColor

        let initialRH = viewModel.rhColor

        // Switch theme to Pop Era and re-push colors (what .onChange does)
        themeManager.apply(.popEra)
        viewModel.rhColor = themeManager.resolved.rightHandColor
        viewModel.lhColor = themeManager.resolved.leftHandColor
        viewModel.chordColor = themeManager.resolved.chordColor

        #expect(viewModel.rhColor != initialRH,
                "RH color must change when switching from Sargam to Pop Era")
    }

    @Test @MainActor func chromeSummonHideCycle() {
        let viewModel = PlayAlongViewModel()
        #expect(viewModel.chromeVisibility == .summoned)
        viewModel.hideChrome()
        #expect(viewModel.chromeVisibility == .hidden)
        viewModel.summonChrome()
        #expect(viewModel.chromeVisibility == .summoned)
    }

    @Test @MainActor func popEraRotationUpdatesAccent() {
        Self.clearUserDefaults()
        let themeManager = AppThemeManager(colorScheme: .light)
        themeManager.apply(.popEra)
        themeManager.setEra(.olivia)
        let oliviaAccent = themeManager.resolved.eraAccentColor

        themeManager.setEra(.brat)
        #expect(themeManager.resolved.eraAccentColor != oliviaAccent,
                "Era accent must change on setEra(.brat)")

        themeManager.setEra(.chappell)
        #expect(themeManager.resolved.eraAccentColor != oliviaAccent)
    }

    @Test @MainActor func darkModeToggleResolvesConsistently() {
        Self.clearUserDefaults()
        let themeManager = AppThemeManager(colorScheme: .light)
        let viewModel = PlayAlongViewModel()

        viewModel.rhColor = themeManager.resolved.rightHandColor

        themeManager.updateColorScheme(.dark)
        viewModel.rhColor = themeManager.resolved.rightHandColor

        #expect(themeManager.resolved.isDark)
    }

    @Test @MainActor func migrationThenThemeSwitchWorks() {
        Self.clearUserDefaults()
        UserDefaults.standard.set("immersive", forKey: "appThemePreset")

        let themeManager = AppThemeManager(colorScheme: .light)
        #expect(themeManager.currentPreset == .immersiveBars,
                "Legacy .immersive must migrate to .immersiveBars")

        themeManager.apply(.neonRhythm)
        #expect(themeManager.currentPreset == .neonRhythm)
        #expect(themeManager.resolved.isDark,
                ".neonRhythm is inherently dark")
    }
}
