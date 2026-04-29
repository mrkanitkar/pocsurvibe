import SwiftUI
import Testing

@testable import SurVibe

@Suite("AppTab")
struct AppTabTests {

    @Test
    func allCasesCoversAllFiveTabs() {
        let tabs = AppTab.allCases
        #expect(tabs.count == 5)
        #expect(tabs.contains(.home))
        #expect(tabs.contains(.learn))
        #expect(tabs.contains(.play))
        #expect(tabs.contains(.songs))
        #expect(tabs.contains(.profile))
    }

    @Test
    func keyEquivalentUsesDigits1Through5() {
        #expect(AppTab.home.keyEquivalent == KeyEquivalent("1"))
        #expect(AppTab.learn.keyEquivalent == KeyEquivalent("2"))
        #expect(AppTab.play.keyEquivalent == KeyEquivalent("3"))
        #expect(AppTab.songs.keyEquivalent == KeyEquivalent("4"))
        #expect(AppTab.profile.keyEquivalent == KeyEquivalent("5"))
    }

    @Test
    func keyEquivalentsAreUnique() {
        let chars = AppTab.allCases.map { $0.keyEquivalent.character }
        #expect(Set(chars).count == chars.count)
    }

    @Test
    func playCaseExists() {
        let cases = AppTab.allCases
        #expect(cases.contains(.play))
    }

    @Test
    func playTabOrderIsThird() {
        let cases = AppTab.allCases
        #expect(cases == [.home, .learn, .play, .songs, .profile])
    }
}
