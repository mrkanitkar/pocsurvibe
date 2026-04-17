import Foundation
import SwiftUI
import Testing
@testable import SurVibe

struct AppThemeEraPersistenceTests {
    private static func clear() {
        UserDefaults.standard.removeObject(forKey: "appThemePopEra")
    }

    @Test @MainActor func eraRoundTripsThroughUserDefaults() {
        Self.clear()
        UserDefaults.standard.set("brat", forKey: "appThemePopEra")
        let manager = AppThemeManager(colorScheme: .light)
        #expect(manager.popEra == .brat)
    }

    @Test @MainActor func invalidEraFallsBackToOlivia() {
        Self.clear()
        UserDefaults.standard.set("garbage", forKey: "appThemePopEra")
        let manager = AppThemeManager(colorScheme: .light)
        #expect(manager.popEra == .olivia)
    }

    @Test @MainActor func eraSequentialUpdatesPersist() {
        Self.clear()
        let manager = AppThemeManager(colorScheme: .light)
        manager.setEra(.taylor)
        #expect(UserDefaults.standard.string(forKey: "appThemePopEra") == "taylor")
        manager.setEra(.sabrina)
        #expect(UserDefaults.standard.string(forKey: "appThemePopEra") == "sabrina")
        manager.setEra(.chappell)
        #expect(UserDefaults.standard.string(forKey: "appThemePopEra") == "chappell")
    }
}
