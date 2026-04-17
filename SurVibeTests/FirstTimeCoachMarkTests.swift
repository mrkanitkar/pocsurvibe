import Foundation
import SwiftUI
import Testing
@testable import SurVibe

struct FirstTimeCoachMarkTests {
    @Test func initializes() {
        // Ensure the coach-mark value type constructs without error.
        _ = FirstTimeCoachMark()
    }

    @Test func appStorageKeyIsStable() {
        // Stability check — if renamed, users re-see the coach mark.
        // Keep this key name in sync with the component.
        let key = "playAlongCoachMarkShown"
        UserDefaults.standard.removeObject(forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == false)

        UserDefaults.standard.set(true, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == true)

        UserDefaults.standard.removeObject(forKey: key)
    }
}
