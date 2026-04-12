import Foundation
import Testing

@testable import SVLearning

/// Dedicated tests for `RiyazStreak` consecutive-day logic.
///
/// Validates all five rules: same-day idempotency, consecutive increment,
/// missed-day reset, first-practice initialization, and longest-streak max-wins.
@Suite("RiyazStreak Consecutive Day Logic")
struct RiyazStreakConsecutiveDayTests {

    // MARK: - Helpers

    /// A fixed base date for deterministic test calculations (2026-01-15 noon UTC).
    private var baseDate: Date {
        Date(timeIntervalSince1970: 1_768_471_200)
    }

    /// Returns a date that is `offset` calendar days after `baseDate`.
    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: baseDate)!
    }

    // MARK: - Consecutive Days Increment

    @Test("Three consecutive days produce streak of 3")
    func consecutiveDaysIncrementStreak() {
        var streak = RiyazStreak()
        streak.recordPractice(on: day(0))
        streak.recordPractice(on: day(1))
        streak.recordPractice(on: day(2))
        #expect(streak.currentStreak == 3)
        #expect(streak.longestStreak == 3)
    }

    // MARK: - Missed Day Resets

    @Test("Skipping a day resets current streak to 1")
    func missedDayResetsStreak() {
        var streak = RiyazStreak()
        streak.recordPractice(on: day(0))
        // Skip day 1
        streak.recordPractice(on: day(2))
        #expect(streak.currentStreak == 1)
    }

    // MARK: - Same Day No Change

    @Test("Practicing twice on the same day does not change streak")
    func sameDayNoChange() {
        var streak = RiyazStreak()
        streak.recordPractice(on: day(0))
        let beforeStreak = streak.currentStreak

        // 2 hours later on the same day
        streak.recordPractice(on: day(0).addingTimeInterval(7200))
        #expect(streak.currentStreak == beforeStreak)
    }

    // MARK: - First Practice

    @Test("First-ever practice sets streak to 1")
    func firstPracticeStartsAt1() {
        var streak = RiyazStreak()
        streak.recordPractice(on: day(0))
        #expect(streak.currentStreak == 1)
        #expect(streak.longestStreak == 1)
    }

    // MARK: - Longest Streak Max-Wins

    @Test("Longest streak survives after reset: build 5, miss, build 3 -> longest 5")
    func longestStreakTracksMax() {
        var streak = RiyazStreak()

        // Build to 5
        for i in 0..<5 {
            streak.recordPractice(on: day(i))
        }
        #expect(streak.currentStreak == 5)
        #expect(streak.longestStreak == 5)

        // Miss day 5, resume on day 6
        streak.recordPractice(on: day(6))
        #expect(streak.currentStreak == 1)

        // Build to 3 (days 6, 7, 8)
        streak.recordPractice(on: day(7))
        streak.recordPractice(on: day(8))
        #expect(streak.currentStreak == 3)
        #expect(streak.longestStreak == 5)
    }
}
