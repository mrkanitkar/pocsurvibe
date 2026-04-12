import Foundation
import SwiftData
import Testing
@testable import SurVibe

/// Tests for XPManager and XPEntry gamification logic.
///
/// All tests use an in-memory ModelContainer (no disk, no CloudKit).
/// A UserProfile is pre-inserted in each test to match production expectations.
@Suite("XPManager Tests")
@MainActor
struct XPManagerTests {

    // MARK: - Test Helpers

    /// Creates an in-memory ModelContainer with all app model types.
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

    /// Creates a container, inserts a UserProfile, and returns a configured XPManager.
    @MainActor
    private func makeManager() throws -> (XPManager, ModelContext) {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = UserProfile(displayName: "Test User")
        context.insert(profile)
        try context.save()
        let manager = XPManager(modelContext: context)
        return (manager, context)
    }

    // MARK: - awardXP Tests

    @Test("awardXP increases totalXP on UserProfile")
    @MainActor
    func awardXPIncreasesTotalXP() throws {
        let (manager, _) = try makeManager()

        manager.awardXP(amount: 50, source: .lessonStep, sourceId: "lesson-01")

        #expect(manager.totalXP == 50)
    }

    @Test("awardXP creates XPEntry record")
    @MainActor
    func awardXPCreatesEntry() throws {
        let (manager, context) = try makeManager()

        manager.awardXP(amount: 25, source: .practice, sourceId: "session-abc")

        let descriptor = FetchDescriptor<XPEntry>()
        let entries = try context.fetch(descriptor)
        #expect(entries.count == 1)
        #expect(entries.first?.amount == 25)
        #expect(entries.first?.source == XPSource.practice.rawValue)
        #expect(entries.first?.sourceId == "session-abc")
    }

    @Test("awardXP with zero amount is no-op")
    @MainActor
    func awardXPZeroIsNoOp() throws {
        let (manager, context) = try makeManager()

        manager.awardXP(amount: 0, source: .lessonStep)

        #expect(manager.totalXP == 0)
        let descriptor = FetchDescriptor<XPEntry>()
        let entries = try context.fetch(descriptor)
        #expect(entries.isEmpty)
    }

    @Test("awardXP with negative amount is no-op")
    @MainActor
    func awardXPNegativeIsNoOp() throws {
        let (manager, context) = try makeManager()

        manager.awardXP(amount: -10, source: .achievement)

        #expect(manager.totalXP == 0)
        let descriptor = FetchDescriptor<XPEntry>()
        let entries = try context.fetch(descriptor)
        #expect(entries.isEmpty)
    }

    @Test("Multiple awards accumulate correctly")
    @MainActor
    func multipleAwardsAccumulate() throws {
        let (manager, context) = try makeManager()

        manager.awardXP(amount: 10, source: .lessonStep, sourceId: "lesson-01")
        manager.awardXP(amount: 20, source: .practice, sourceId: "session-01")
        manager.awardXP(amount: 50, source: .songProficiency, sourceId: "song-01")

        #expect(manager.totalXP == 80)

        let descriptor = FetchDescriptor<XPEntry>()
        let entries = try context.fetch(descriptor)
        #expect(entries.count == 3)
    }

    // MARK: - xpToday Tests

    @Test("xpToday returns only today's entries")
    @MainActor
    func xpTodayReturnsTodayOnly() throws {
        let (manager, context) = try makeManager()

        // Award some XP today
        manager.awardXP(amount: 30, source: .lessonStep)
        manager.awardXP(amount: 20, source: .practice)

        // Insert a backdated entry for yesterday
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let oldEntry = XPEntry(amount: 100, source: XPSource.streak.rawValue, sourceId: "")
        oldEntry.earnedAt = yesterday
        context.insert(oldEntry)
        try context.save()

        // xpToday should only include today's 30 + 20 = 50
        #expect(manager.xpToday == 50)
    }

    @Test("xpToday returns 0 when no entries today")
    @MainActor
    func xpTodayReturnsZeroWhenEmpty() throws {
        let (manager, context) = try makeManager()

        // Insert only a backdated entry
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let oldEntry = XPEntry(amount: 100, source: XPSource.practice.rawValue, sourceId: "")
        oldEntry.earnedAt = yesterday
        context.insert(oldEntry)
        try context.save()

        #expect(manager.xpToday == 0)
    }

    // MARK: - recentEntries Tests

    @Test("recentEntries returns last 20 sorted descending")
    @MainActor
    func recentEntriesReturnsLast20Descending() throws {
        let (manager, context) = try makeManager()

        // Insert 25 entries with staggered timestamps
        let now = Date()
        for i in 0..<25 {
            let entry = XPEntry(
                amount: i + 1,
                source: XPSource.lessonStep.rawValue,
                sourceId: "step-\(i)"
            )
            entry.earnedAt = now.addingTimeInterval(Double(i) * 60)
            context.insert(entry)
        }
        try context.save()

        let recent = manager.recentEntries
        #expect(recent.count == 20)

        // Most recent entry should be first (amount 25, inserted at +24 minutes)
        #expect(recent.first?.amount == 25)
        // Oldest in the result set should be amount 6 (index 5, skipping 0-4)
        #expect(recent.last?.amount == 6)

        // Verify descending order
        for i in 0..<(recent.count - 1) {
            #expect(recent[i].earnedAt >= recent[i + 1].earnedAt)
        }
    }

    @Test("recentEntries returns empty array initially")
    @MainActor
    func recentEntriesEmptyInitially() throws {
        let (manager, _) = try makeManager()

        let recent = manager.recentEntries
        #expect(recent.isEmpty)
    }

    // MARK: - XPSource Tests

    @Test("XPSource rawValues match expected strings")
    func xpSourceRawValues() {
        #expect(XPSource.lessonStep.rawValue == "lesson_step")
        #expect(XPSource.practice.rawValue == "practice")
        #expect(XPSource.songProficiency.rawValue == "song_mastery")
        #expect(XPSource.achievement.rawValue == "achievement")
        #expect(XPSource.streak.rawValue == "streak_bonus")
    }

    // MARK: - Edge Cases

    @Test("awardXP creates UserProfile if none exists")
    @MainActor
    func awardXPCreatesProfileIfMissing() throws {
        // Use a container WITHOUT a pre-inserted profile
        let container = try makeContainer()
        let context = container.mainContext
        let manager = XPManager(modelContext: context)

        manager.awardXP(amount: 10, source: .lessonStep)

        // Verify a profile was auto-created and XP was recorded
        let descriptor = FetchDescriptor<UserProfile>()
        let profiles = try context.fetch(descriptor)
        #expect(profiles.count == 1)
        #expect(profiles.first?.totalXP == 10)
    }

    @Test("awardXP records correct source for each XPSource case")
    @MainActor
    func awardXPRecordsCorrectSource() throws {
        let (manager, context) = try makeManager()

        let sources: [XPSource] = [.lessonStep, .practice, .songProficiency, .achievement, .streak]
        for source in sources {
            manager.awardXP(amount: 5, source: source)
        }

        var descriptor = FetchDescriptor<XPEntry>(
            sortBy: [SortDescriptor(\.earnedAt)]
        )
        descriptor.fetchLimit = 10
        let entries = try context.fetch(descriptor)
        #expect(entries.count == 5)

        let recordedSources = Set(entries.map(\.source))
        let expectedSources = Set(sources.map(\.rawValue))
        #expect(recordedSources == expectedSources)
    }
}
