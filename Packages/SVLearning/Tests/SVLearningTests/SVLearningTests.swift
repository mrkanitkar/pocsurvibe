import Foundation
import Testing

@testable import SVLearning

@Suite("RiyazStreak Tests")
struct RiyazStreakTests {

    // MARK: - Helpers

    /// A fixed base date for deterministic test calculations.
    private var baseDate: Date {
        // 2026-01-01 noon UTC
        Date(timeIntervalSince1970: 1_767_261_600)
    }

    /// Returns a date that is `offset` calendar days after `baseDate`.
    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: baseDate)!
    }

    // MARK: - Default State

    @Test("Default streak is zero with nil date")
    func defaultStreakIsZero() {
        let streak = RiyazStreak()
        #expect(streak.currentStreak == 0)
        #expect(streak.longestStreak == 0)
        #expect(streak.lastPracticeDate == nil)
    }

    // MARK: - Consecutive Days

    @Test("Three consecutive days increment streak to 3")
    func consecutiveDaysIncrementStreak() {
        var streak = RiyazStreak()
        streak.recordPractice(on: day(0))
        #expect(streak.currentStreak == 1)

        streak.recordPractice(on: day(1))
        #expect(streak.currentStreak == 2)

        streak.recordPractice(on: day(2))
        #expect(streak.currentStreak == 3)
    }

    // MARK: - Missed Day Resets

    @Test("Missed day resets streak to 1")
    func missedDayResetsStreak() {
        var streak = RiyazStreak()
        streak.recordPractice(on: day(0))
        #expect(streak.currentStreak == 1)

        // Skip day 1, practice on day 2
        streak.recordPractice(on: day(2))
        #expect(streak.currentStreak == 1)
    }

    // MARK: - Same Day No Change

    @Test("Same-day duplicate practice does not change streak")
    func sameDayNoChange() {
        var streak = RiyazStreak()
        streak.recordPractice(on: day(0))
        #expect(streak.currentStreak == 1)

        // Practice again on the same day (different time)
        let laterSameDay = day(0).addingTimeInterval(3600)
        streak.recordPractice(on: laterSameDay)
        #expect(streak.currentStreak == 1)
        #expect(streak.longestStreak == 1)
    }

    // MARK: - First Practice

    @Test("First practice starts streak at 1")
    func firstPracticeStartsAt1() {
        var streak = RiyazStreak()
        streak.recordPractice(on: day(0))
        #expect(streak.currentStreak == 1)
        #expect(streak.longestStreak == 1)
        #expect(streak.lastPracticeDate != nil)
    }

    // MARK: - Longest Streak Tracking

    @Test("Longest streak tracks max across resets")
    func longestStreakTracksMax() {
        var streak = RiyazStreak()

        // Build streak to 5: days 0-4
        for i in 0..<5 {
            streak.recordPractice(on: day(i))
        }
        #expect(streak.currentStreak == 5)
        #expect(streak.longestStreak == 5)

        // Miss day 5, practice on day 6 -- resets current to 1
        streak.recordPractice(on: day(6))
        #expect(streak.currentStreak == 1)

        // Build back to 3: days 6, 7, 8
        streak.recordPractice(on: day(7))
        streak.recordPractice(on: day(8))
        #expect(streak.currentStreak == 3)

        // Longest remains 5 (max-wins)
        #expect(streak.longestStreak == 5)
    }

    // MARK: - Edge Cases

    @Test("RiyazStreak is Sendable")
    func isSendable() {
        func requireSendable<T: Sendable>(_: T) {}
        requireSendable(RiyazStreak())
    }

    @Test("Custom initial values are preserved")
    func customInitialValues() {
        let date = Date()
        let streak = RiyazStreak(currentStreak: 3, longestStreak: 7, lastPracticeDate: date)
        #expect(streak.currentStreak == 3)
        #expect(streak.longestStreak == 7)
        #expect(streak.lastPracticeDate == date)
    }

    @Test("Last practice date updates on each new day")
    func lastPracticeDateUpdates() {
        var streak = RiyazStreak()
        streak.recordPractice(on: day(0))
        #expect(Calendar.current.isDate(streak.lastPracticeDate!, inSameDayAs: day(0)))

        streak.recordPractice(on: day(1))
        #expect(Calendar.current.isDate(streak.lastPracticeDate!, inSameDayAs: day(1)))
    }
}
