import Testing
@testable import SurVibe

/// Verifies `HomeDoorID` arrow-key nav math via `LibraryFocusNavigator`.
/// Grid assumed 2 columns (SP-4c Task 4 default).
struct HomeTabFocusTests {
    @Test
    func rightFromSongsGoesToLearn() {
        // songs = 0, learn = 1; columns = 2 → right at col 0 → col 1
        let result = LibraryFocusNavigator.nextIndex(
            for: .right, currentIndex: 0, count: 5, columns: 2
        )
        #expect(result == 1)
    }

    @Test
    func downFromSongsGoesToMoods() {
        // songs = 0, moods = 2; columns = 2 → down from row 0 → row 1
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 0, count: 5, columns: 2
        )
        #expect(result == 2)
    }

    @Test
    func downFromRagasReturnsNil() {
        // ragas = 4 (last, partial row); down clamps
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 4, count: 5, columns: 2
        )
        #expect(result == nil)
    }

    @Test
    func rightFromLearnReturnsNil() {
        // learn = 1 (col 1, rightmost in 2-col); right clamps
        let result = LibraryFocusNavigator.nextIndex(
            for: .right, currentIndex: 1, count: 5, columns: 2
        )
        #expect(result == nil)
    }
}
