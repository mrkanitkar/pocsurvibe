import Foundation
import SwiftData
import Testing

@testable import SurVibe

/// Tests for `StreakTracker` which reads RiyazEntry from SwiftData to compute streaks.
///
/// All tests use an in-memory `ModelContainer` (no disk, no CloudKit).
@Suite("StreakTracker Tests")
@MainActor
struct StreakTrackerTests {

    // MARK: - Helpers

    /// Creates an in-memory ModelContainer for testing, including all app models.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            UserProfile.self,
            RiyazEntry.self,
            Achievement.self,
            SongProgress.self,
            LessonProgress.self,
            SubscriptionState.self,
            Song.self,
            Lesson.self,
            Curriculum.self,
            XPEntry.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// A fixed base date for deterministic tests (2026-01-15 noon UTC).
    private var baseDate: Date {
        Date(timeIntervalSince1970: 1_768_471_200)
    }

    /// Returns a date that is `offset` calendar days after `baseDate`.
    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: baseDate)!
    }

    /// Inserts a RiyazEntry with the given date into the context.
    @MainActor
    private func insertEntry(context: ModelContext, date: Date, durationMinutes: Int = 15) {
        let entry = RiyazEntry(date: date, durationMinutes: durationMinutes)
        context.insert(entry)
    }

    // MARK: - Empty Entries

    @Test("Empty entries give zero streak")
    @MainActor
    func emptyEntriesGiveZeroStreak() throws {
        let container = try makeContainer()
        let tracker = StreakTracker(modelContext: container.mainContext)
        tracker.recompute()
        #expect(tracker.currentStreak == 0)
        #expect(tracker.longestStreak == 0)
        #expect(tracker.lastPracticeDate == nil)
    }

    // MARK: - Single Entry

    @Test("Single entry gives streak of 1")
    @MainActor
    func singleEntryGivesStreak1() throws {
        let container = try makeContainer()
        let context = container.mainContext

        insertEntry(context: context, date: day(0))
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute()
        #expect(tracker.currentStreak == 1)
        #expect(tracker.longestStreak == 1)
        #expect(tracker.lastPracticeDate != nil)
    }

    // MARK: - Consecutive Days

    @Test("Three consecutive days give streak of 3")
    @MainActor
    func threeConsecutiveDaysGivesStreak3() throws {
        let container = try makeContainer()
        let context = container.mainContext

        insertEntry(context: context, date: day(0))
        insertEntry(context: context, date: day(1))
        insertEntry(context: context, date: day(2))
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute()
        #expect(tracker.currentStreak == 3)
        #expect(tracker.longestStreak == 3)
    }

    // MARK: - Gap in Middle

    @Test("Gap in middle resets streak to most recent consecutive run")
    @MainActor
    func gapInMiddleResetsToRecent() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Days 0, 1, 2 (streak of 3), then gap, then days 4, 5 (streak of 2)
        insertEntry(context: context, date: day(0))
        insertEntry(context: context, date: day(1))
        insertEntry(context: context, date: day(2))
        // Skip day 3
        insertEntry(context: context, date: day(4))
        insertEntry(context: context, date: day(5))
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute()
        // Current streak = most recent run = 2 (days 4-5)
        #expect(tracker.currentStreak == 2)
        // Longest streak = 3 (days 0-2)
        #expect(tracker.longestStreak == 3)
    }

    // MARK: - Practiced Today

    @Test("practicedToday is true when entry exists for today")
    @MainActor
    func practicedTodayTrueWhenEntryToday() throws {
        let container = try makeContainer()
        let context = container.mainContext

        insertEntry(context: context, date: Date())
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute()
        #expect(tracker.practicedToday == true)
    }

    @Test("practicedToday is false when no entry for today")
    @MainActor
    func practicedTodayFalseWhenNoEntryToday() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Entry from yesterday only
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        insertEntry(context: context, date: yesterday)
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute()
        #expect(tracker.practicedToday == false)
    }

    // MARK: - Duplicate Same-Day Entries

    @Test("Multiple entries on the same day count as one day in streak")
    @MainActor
    func duplicateSameDayEntriesCountOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Three entries on day 0, two on day 1
        insertEntry(context: context, date: day(0))
        insertEntry(context: context, date: day(0).addingTimeInterval(3600))
        insertEntry(context: context, date: day(0).addingTimeInterval(7200))
        insertEntry(context: context, date: day(1))
        insertEntry(context: context, date: day(1).addingTimeInterval(1800))
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute()
        #expect(tracker.currentStreak == 2)
        #expect(tracker.longestStreak == 2)
    }
}
