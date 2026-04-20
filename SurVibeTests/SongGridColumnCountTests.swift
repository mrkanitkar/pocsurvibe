import Foundation
import Testing
@testable import SurVibe

/// Verifies `SongLibraryView.columnCount(for:)` breakpoints.
struct SongGridColumnCountTests {
    @Test
    func iPhone15ProReturns2() {
        // iPhone 15 Pro portrait width ≈ 393pt
        #expect(SongLibraryView.columnCount(for: 393) == 2)
    }

    @Test
    func iPadSplitRegularReturns2() {
        // iPad regular width split-view (e.g., 500pt)
        #expect(SongLibraryView.columnCount(for: 500) == 2)
    }

    @Test
    func iPadPortraitFullReturns3() {
        // iPad 11-inch portrait full width ≈ 834pt
        #expect(SongLibraryView.columnCount(for: 834) == 3)
    }

    @Test
    func iPadLandscapeFullReturns4() {
        // iPad 13-inch landscape full width ≈ 1366pt
        #expect(SongLibraryView.columnCount(for: 1366) == 4)
    }

    @Test
    func exactlyAt700Returns3() {
        // Boundary between 2 and 3 columns
        #expect(SongLibraryView.columnCount(for: 700) == 3)
    }
}
