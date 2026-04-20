import Foundation

/// Pure index-math helper for hardware-keyboard arrow-key navigation
/// across a single-column list or a fixed-width grid.
///
/// Used by `LessonLibraryView` (columns = 1) and `SongLibraryView` (columns = 2)
/// to compute the next focused index when the user presses an arrow key.
/// Returns `nil` at grid edges (no wrap-around).
enum LibraryFocusNavigator {
    /// Direction in which focus should move.
    enum FocusDirection {
        case up, down, left, right
    }

    /// Computes the next focused index after an arrow-key press.
    ///
    /// Math assumes row-major ordering: index = row * columns + col.
    /// Returns `nil` if the move would leave the grid (edge clamp, no wrap).
    ///
    /// - Parameters:
    ///   - direction: Which arrow key was pressed.
    ///   - currentIndex: Index of the currently focused item.
    ///   - count: Total item count.
    ///   - columns: Grid column count. `1` for a linear list.
    /// - Returns: New index to focus, or `nil` if the move is a no-op at an edge.
    static func nextIndex(
        for direction: FocusDirection,
        currentIndex: Int,
        count: Int,
        columns: Int
    ) -> Int? {
        guard count > 0, columns > 0, currentIndex >= 0, currentIndex < count else {
            return nil
        }
        let col = currentIndex % columns
        let row = currentIndex / columns
        let lastIndex = count - 1

        switch direction {
        case .up:
            guard row > 0 else { return nil }
            return currentIndex - columns
        case .down:
            let next = currentIndex + columns
            guard next <= lastIndex else { return nil }
            return next
        case .left:
            guard col > 0 else { return nil }
            return currentIndex - 1
        case .right:
            guard col < columns - 1, currentIndex + 1 <= lastIndex else { return nil }
            return currentIndex + 1
        }
    }
}
