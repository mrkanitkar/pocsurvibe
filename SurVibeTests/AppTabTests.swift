import SwiftUI
import Testing
@testable import SurVibe

@Suite("AppTab")
struct AppTabTests {

    @Test func allCasesCoversAllFourTabs() {
        let tabs = AppTab.allCases
        #expect(tabs.count == 4)
        #expect(tabs.contains(.home))
        #expect(tabs.contains(.learn))
        #expect(tabs.contains(.songs))
        #expect(tabs.contains(.profile))
    }

    @Test func keyEquivalentUsesDigits1Through4() {
        #expect(AppTab.home.keyEquivalent == KeyEquivalent("1"))
        #expect(AppTab.learn.keyEquivalent == KeyEquivalent("2"))
        #expect(AppTab.songs.keyEquivalent == KeyEquivalent("3"))
        #expect(AppTab.profile.keyEquivalent == KeyEquivalent("4"))
    }

    @Test func keyEquivalentsAreUnique() {
        let chars = AppTab.allCases.map { $0.keyEquivalent.character }
        #expect(Set(chars).count == chars.count)
    }
}
