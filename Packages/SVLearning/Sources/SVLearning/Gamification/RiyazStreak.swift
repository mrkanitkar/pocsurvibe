import Foundation

/// Tracks daily practice (riyaz) streaks for gamification.
///
/// Maintains a running count of consecutive practice days. The streak increments
/// when the user practices on the next calendar day after their last session,
/// resets to 1 if any day(s) are missed, and stays unchanged for duplicate
/// same-day entries. `longestStreak` uses max-wins so it never decreases.
public struct RiyazStreak: Sendable {
    /// Current streak length in consecutive days.
    public var currentStreak: Int

    /// Longest streak ever achieved (max-wins: never decreases).
    public var longestStreak: Int

    /// Date of the last recorded practice session, or nil if never practiced.
    public var lastPracticeDate: Date?

    /// Creates a new streak tracker with optional initial values.
    ///
    /// - Parameters:
    ///   - currentStreak: Starting streak count. Default 0.
    ///   - longestStreak: Starting longest streak. Default 0.
    ///   - lastPracticeDate: Date of most recent practice, or nil. Default nil.
    public init(currentStreak: Int = 0, longestStreak: Int = 0, lastPracticeDate: Date? = nil) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastPracticeDate = lastPracticeDate
    }

    /// Record a practice session on the given date. Updates streak accordingly.
    ///
    /// The method applies four rules in order:
    /// 1. Same calendar day as `lastPracticeDate` -- no change (early return).
    /// 2. Consecutive calendar day (next day after `lastPracticeDate`) -- increment `currentStreak`.
    /// 3. Missed day(s) between sessions -- reset `currentStreak` to 1.
    /// 4. First-ever practice (`lastPracticeDate` is nil) -- set `currentStreak` to 1.
    ///
    /// After any change, `longestStreak` is updated via `max(longestStreak, currentStreak)`.
    ///
    /// - Parameter date: The date of the practice session. Defaults to now.
    public mutating func recordPractice(on date: Date = Date()) {
        let calendar = Calendar.current

        if let lastDate = lastPracticeDate {
            // Rule 1: Same day -- no change
            if calendar.isDate(date, inSameDayAs: lastDate) {
                return
            }

            // Check if date is the next consecutive calendar day after lastDate
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: lastDate),
               calendar.isDate(date, inSameDayAs: nextDay) {
                // Rule 2: Consecutive day -- increment
                currentStreak += 1
            } else {
                // Rule 3: Missed day(s) -- reset
                currentStreak = 1
            }
        } else {
            // Rule 4: First ever practice
            currentStreak = 1
        }

        longestStreak = max(longestStreak, currentStreak)
        lastPracticeDate = date
    }
}
