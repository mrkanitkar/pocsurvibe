import SwiftUI
import Testing

@testable import SurVibe

// MARK: - AppTab Tests

@Suite("Day 4 — AppTab Tests")
@MainActor
struct Day04AppTabTests {

    @Test("AppTab has exactly 5 cases")
    func appTabCaseCount() {
        // Practice tab was merged into the play-along experience (SongPlayAlongView).
        // Play tab was added in Wave 1 (free-form practice surface).
        #expect(AppTab.allCases.count == 5)
    }

    @Test("AppTab cases are in correct order")
    func appTabOrder() {
        let cases = AppTab.allCases
        #expect(cases[0] == .home)
        #expect(cases[1] == .learn)
        #expect(cases[2] == .play)
        #expect(cases[3] == .songs)
        #expect(cases[4] == .profile)
    }

    @Test("AppTab labels are human-readable")
    func appTabLabels() {
        #expect(AppTab.home.label == "Home")
        #expect(AppTab.learn.label == "Learn")
        #expect(AppTab.play.label == "Play")
        #expect(AppTab.songs.label == "Songs")
        #expect(AppTab.profile.label == "Profile")
    }

    @Test("AppTab system images are valid SF Symbol names")
    func appTabSystemImages() {
        #expect(AppTab.home.systemImage == "house.fill")
        #expect(AppTab.learn.systemImage == "book.fill")
        #expect(AppTab.play.systemImage == "pianokeys")
        #expect(AppTab.songs.systemImage == "music.note.list")
        #expect(AppTab.profile.systemImage == "person.circle.fill")
    }

    @Test("AppTab rawValues are lowercase strings")
    func appTabRawValues() {
        for tab in AppTab.allCases {
            #expect(tab.rawValue == tab.rawValue.lowercased())
        }
    }

    @Test("AppTab conforms to Hashable")
    func appTabHashable() {
        let set: Set<AppTab> = [.home, .learn, .play, .songs, .profile]
        #expect(set.count == 5)
    }
}

// MARK: - AppRouter Tests

@Suite("Day 4 — AppRouter Tests")
@MainActor
struct Day04AppRouterTests {

    @MainActor
    @Test("AppRouter initial tab is home")
    func routerInitialState() {
        let router = AppRouter()
        #expect(router.currentTab == .home)
    }

    @MainActor
    @Test("AppRouter switchTab updates currentTab")
    func routerSwitchTab() {
        let router = AppRouter()
        router.switchTab(to: .songs)
        #expect(router.currentTab == .songs)
    }

    @MainActor
    @Test("AppRouter switchTab to same tab is no-op")
    func routerSwitchSameTab() {
        let router = AppRouter()
        router.switchTab(to: .home)
        #expect(router.currentTab == .home)
    }

    @MainActor
    @Test("AppRouter can cycle through all tabs")
    func routerCycleAllTabs() {
        let router = AppRouter()
        for tab in AppTab.allCases {
            router.switchTab(to: tab)
            #expect(router.currentTab == tab)
        }
    }

    @MainActor
    @Test("AppRouter navigate appends destination to current tab path")
    func routerNavigateAppends() {
        let router = AppRouter()
        router.navigate(to: .songLibrary)
        let path = router.pathForTab(.home)
        #expect(path.wrappedValue.count == 1)
        #expect(path.wrappedValue.first == .songLibrary)
    }

    @MainActor
    @Test("AppRouter navigate appends multiple destinations in order")
    func routerNavigateMultiple() {
        let router = AppRouter()
        router.navigate(to: .songLibrary)
        router.navigate(to: .profile)
        let path = router.pathForTab(.home)
        #expect(path.wrappedValue.count == 2)
        #expect(path.wrappedValue[0] == .songLibrary)
        #expect(path.wrappedValue[1] == .profile)
    }

    @MainActor
    @Test("AppRouter popToRoot clears current tab navigation path")
    func routerPopToRoot() {
        let router = AppRouter()
        router.navigate(to: .songLibrary)
        router.navigate(to: .profile)
        router.popToRoot()
        let path = router.pathForTab(.home)
        #expect(path.wrappedValue.isEmpty)
    }

    @MainActor
    @Test("AppRouter popToRoot on empty path is no-op")
    func routerPopToRootEmpty() {
        let router = AppRouter()
        router.popToRoot()
        let path = router.pathForTab(.home)
        #expect(path.wrappedValue.isEmpty)
    }

    @MainActor
    @Test("AppRouter pop removes last destination only")
    func routerPopRemovesLast() {
        let router = AppRouter()
        router.navigate(to: .songLibrary)
        router.navigate(to: .profile)
        router.pop()
        let path = router.pathForTab(.home)
        #expect(path.wrappedValue.count == 1)
        #expect(path.wrappedValue.first == .songLibrary)
    }

    @MainActor
    @Test("AppRouter pop on empty path is no-op")
    func routerPopOnEmpty() {
        let router = AppRouter()
        router.pop()
        let path = router.pathForTab(.home)
        #expect(path.wrappedValue.isEmpty)
    }

    @MainActor
    @Test("AppRouter tabs maintain independent navigation paths")
    func routerIndependentPaths() {
        let router = AppRouter()

        // Navigate on home tab
        router.navigate(to: .songLibrary)

        // Switch to songs tab and navigate there
        router.switchTab(to: .songs)
        router.navigate(to: .lessonList)

        // Verify independent paths
        let homePath = router.pathForTab(.home)
        let songsPath = router.pathForTab(.songs)
        let learnPath = router.pathForTab(.learn)

        #expect(homePath.wrappedValue.count == 1)
        #expect(songsPath.wrappedValue.count == 1)
        #expect(learnPath.wrappedValue.isEmpty)
    }

    @MainActor
    @Test("AppRouter popToRoot only affects current tab")
    func routerPopToRootAffectsOnlyCurrentTab() {
        let router = AppRouter()

        // Navigate on home tab
        router.navigate(to: .songLibrary)

        // Switch to songs tab, navigate, then pop to root
        router.switchTab(to: .songs)
        router.navigate(to: .lessonList)
        router.popToRoot()

        // Songs tab is cleared, home tab untouched
        let homePath = router.pathForTab(.home)
        let songsPath = router.pathForTab(.songs)
        #expect(homePath.wrappedValue.count == 1)
        #expect(songsPath.wrappedValue.isEmpty)
    }

    @MainActor
    @Test("AppRouter pathForTab binding setter updates path")
    func routerPathBindingSetter() {
        let router = AppRouter()
        let binding = router.pathForTab(.home)
        binding.wrappedValue = [.songLibrary, .settings]
        let path = router.pathForTab(.home)
        #expect(path.wrappedValue.count == 2)
    }
}

// MARK: - AppDestination Tests

@Suite("Day 4 — AppDestination Tests")
@MainActor
struct Day04AppDestinationTests {

    @Test("AppDestination simple cases are equal")
    func simpleEquality() {
        #expect(AppDestination.songLibrary == AppDestination.songLibrary)
        #expect(AppDestination.lessonList == AppDestination.lessonList)
        #expect(AppDestination.profile == AppDestination.profile)
        #expect(AppDestination.settings == AppDestination.settings)
    }

    @Test("AppDestination different simple cases are not equal")
    func simpleDifferentCases() {
        #expect(AppDestination.songLibrary != AppDestination.lessonList)
        #expect(AppDestination.profile != AppDestination.settings)
        #expect(AppDestination.songLibrary != AppDestination.profile)
    }

    @Test("AppDestination simple cases are Hashable")
    func simpleHashable() {
        let set: Set<AppDestination> = [.songLibrary, .lessonList, .profile, .settings]
        #expect(set.count == 4)
    }

    @Test("AppDestination songLibrary hashes consistently")
    func consistentHash() {
        let dest1 = AppDestination.songLibrary
        let dest2 = AppDestination.songLibrary
        #expect(dest1.hashValue == dest2.hashValue)
    }
}
