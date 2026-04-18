import SwiftUI
import Testing
@testable import SurVibe

/// Validates Pop Era picker state coordination with AppThemeManager.
struct PopEraPickerTests {

    @Test @MainActor func defaultEraIsOlivia() {
        UserDefaults.standard.removeObject(forKey: "appThemePopEra")
        let manager = AppThemeManager()
        // Fresh defaults — should pick the Olivia default per AppThemeManager.init logic.
        #expect(manager.popEra == .olivia)
    }

    @Test @MainActor func setEraUpdatesPopEra() {
        let manager = AppThemeManager()
        manager.setEra(.taylor)
        #expect(manager.popEra == .taylor)
    }

    @Test @MainActor func setEraPersistsToUserDefaults() {
        let manager = AppThemeManager()
        manager.setEra(.brat)
        let stored = UserDefaults.standard.string(forKey: "appThemePopEra")
        #expect(stored == "brat")
    }

    @Test @MainActor func setEraTriggersResolveUpdate() {
        let manager = AppThemeManager()
        manager.apply(.popEra)
        manager.setEra(.chappell)
        // resolved should now reflect chappell era's accent color
        let chappellAccent = AppThemePreset.popEra.eraAccentColor(for: .chappell)
        #expect(manager.resolved.eraAccentColor == chappellAccent)
    }

    @Test func allFivePopErasAreEnumerated() {
        #expect(PopEra.allCases.count == 5)
        #expect(PopEra.allCases.contains(.taylor))
        #expect(PopEra.allCases.contains(.olivia))
        #expect(PopEra.allCases.contains(.sabrina))
        #expect(PopEra.allCases.contains(.chappell))
        #expect(PopEra.allCases.contains(.brat))
    }
}
