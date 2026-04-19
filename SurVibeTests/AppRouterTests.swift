import Testing
@testable import SurVibe
@testable import SVCore

// MARK: - Fixtures

extension Song {
    /// Minimal test fixture. All @Model fields have defaults so no args are required.
    static func fixture() -> Song {
        Song()
    }
}

extension Lesson {
    /// Minimal test fixture. All @Model fields have defaults so no args are required.
    static func fixture() -> Lesson {
        Lesson()
    }
}

// MARK: - Tests

@MainActor
@Suite("AppRouter v2")
struct AppRouterV2Tests {

    @Test func openSongSwitchesTabAndSetsSelection() {
        let router = AppRouter()
        let song = Song.fixture()

        router.openSong(song.id)

        #expect(router.currentTab == .songs)
        #expect(router.selectedSongID == song.id)
    }

    @Test func openLessonSwitchesTabAndSetsSelection() {
        let router = AppRouter()
        let lesson = Lesson.fixture()

        router.openLesson(lesson.id)

        #expect(router.currentTab == .learn)
        #expect(router.selectedLessonID == lesson.id)
    }

    @Test func openSongFiresSidebarUsedAnalytics() {
        let router = AppRouter()
        let song = Song.fixture()
        let provider = MockAnalyticsProvider()

        router.openSong(song.id, analytics: provider)

        let hit = provider.trackedEvents.first { $0.event == .sidebarUsed }
        #expect(hit != nil)
        #expect(hit?.properties?["destination"] as? String == "song")
    }
}
