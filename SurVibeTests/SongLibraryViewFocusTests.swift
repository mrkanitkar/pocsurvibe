// SurVibeTests/SongLibraryViewFocusTests.swift
import Testing
@testable import SurVibe

@MainActor
@Suite("SongLibrary focus navigation")
struct SongLibraryViewFocusTests {

    @Test func openSongSelectsSongForDetailColumn() {
        let router = AppRouter()
        let song = Song.fixture()

        // Simulate what .onKeyPress(.return) on a focused row triggers.
        router.openSong(song.id)

        #expect(router.currentTab == .songs)
        #expect(router.selectedSongID == song.id)
    }

    @Test func openLessonSelectsLessonForDetailColumn() {
        let router = AppRouter()
        let lesson = Lesson.fixture()

        router.openLesson(lesson.id)

        #expect(router.currentTab == .learn)
        #expect(router.selectedLessonID == lesson.id)
    }
}
