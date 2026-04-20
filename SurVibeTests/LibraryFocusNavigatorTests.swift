import Testing
@testable import SurVibe

/// Index-math tests for `LibraryFocusNavigator`. Pure function, no UI.
struct LibraryFocusNavigatorTests {
    @Test
    func downArrowFromFirstItemAdvancesOneRow() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 0, count: 6, columns: 2
        )
        #expect(result == 2)
    }

    @Test
    func downArrowFromLastRowReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 4, count: 6, columns: 2
        )
        #expect(result == nil)
    }

    @Test
    func rightArrowFromEndOfRowReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .right, currentIndex: 1, count: 6, columns: 2
        )
        #expect(result == nil)
    }

    @Test
    func leftArrowFromStartOfRowReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .left, currentIndex: 0, count: 6, columns: 2
        )
        #expect(result == nil)
    }

    @Test
    func linearDownOnOneColumnList() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 2, count: 5, columns: 1
        )
        #expect(result == 3)
    }

    @Test
    func linearUpFromZeroReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .up, currentIndex: 0, count: 5, columns: 1
        )
        #expect(result == nil)
    }

    @Test
    func downArrowFromPartialLastRowReturnsNil() {
        // 5 items in a 2-column grid: rows are [0,1], [2,3], [4]. Index 4 is last-row; down clamps.
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 4, count: 5, columns: 2
        )
        #expect(result == nil)
    }

    @Test
    func rightArrowFromLastItemReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .right, currentIndex: 5, count: 6, columns: 2
        )
        #expect(result == nil)
    }
}
