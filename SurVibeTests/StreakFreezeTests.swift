import Foundation
import SwiftData
import Testing

@testable import SurVibe

/// Tests for the streak-freeze token lifecycle: grant, burn, idempotency, and cap.
///
/// All tests use an in-memory `ModelContainer` to avoid CloudKit and disk I/O.
/// Serialized + shared container — see `SwiftDataTestContainer.swift`
/// for why per-test `isStoredInMemoryOnly` containers crash the host.
@Suite("StreakFreeze Tests", .serialized)
@MainActor
struct StreakFreezeTests {

    // MARK: - Default State

    @Test("New profile starts with zero freeze tokens")
    func newProfileHasZeroTokens() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        context.insert(profile)
        try context.save()

        #expect(profile.streakFreezeTokens == 0)
        #expect(profile.lastFreezeGrantWeekISO.isEmpty)
    }

    // MARK: - Grant Logic

    @Test("Practicing this week grants 2 tokens")
    func grantingTokensAfterPracticeAddsTwo() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        context.insert(profile)
        // Entry for today — current ISO week
        let entry = RiyazEntry(date: Date(), durationMinutes: 10)
        context.insert(entry)
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute(profile: profile)

        #expect(profile.streakFreezeTokens == 2)
        #expect(!profile.lastFreezeGrantWeekISO.isEmpty)
    }

    @Test("No tokens granted if user has not practiced this week")
    func noGrantIfNoPracticeThisWeek() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        context.insert(profile)
        // Entry from 8 days ago — last ISO week
        let oldDate = Calendar.current.date(byAdding: .day, value: -8, to: Date())!
        let entry = RiyazEntry(date: oldDate, durationMinutes: 10)
        context.insert(entry)
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        // Directly call grant (not recompute) to isolate grant logic
        let granted = tracker.grantWeeklyFreezeTokensIfEligible(profile: profile)

        #expect(granted == 0)
        #expect(profile.streakFreezeTokens == 0)
    }

    @Test("Granting tokens is idempotent within the same ISO week")
    func grantingIsIdempotentWithinSameWeek() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        context.insert(profile)
        let entry = RiyazEntry(date: Date(), durationMinutes: 10)
        context.insert(entry)
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute(profile: profile)
        let after1 = profile.streakFreezeTokens
        tracker.recompute(profile: profile)
        let after2 = profile.streakFreezeTokens

        #expect(after1 == after2, "Re-running recompute in the same week must not add more tokens")
    }

    @Test("Granting caps at maxTokens (default 4)")
    func grantingCapsAtFour() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        profile.streakFreezeTokens = 3 // already 3, only 1 slot left
        context.insert(profile)
        let entry = RiyazEntry(date: Date(), durationMinutes: 10)
        context.insert(entry)
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute(profile: profile)

        #expect(profile.streakFreezeTokens == 4, "Should cap at 4 — only 1 token granted on top of 3")
    }

    @Test("Granting when already at cap marks week without adding tokens")
    func grantingAtCapMarksWeek() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        profile.streakFreezeTokens = 4 // already at cap
        context.insert(profile)
        // Must have a today entry so grant logic considers the user eligible
        let entry = RiyazEntry(date: Date(), durationMinutes: 10)
        context.insert(entry)
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        // Run recompute so lastPracticeDate is populated before calling grant
        tracker.recompute()
        let granted = tracker.grantWeeklyFreezeTokensIfEligible(profile: profile)

        #expect(granted == 0)
        #expect(profile.streakFreezeTokens == 4)
        // Week should be marked to prevent re-checking
        #expect(!profile.lastFreezeGrantWeekISO.isEmpty)
    }

    // MARK: - Burn Logic

    @Test("Burns 1 token when streak at risk (practiced yesterday, not today)")
    func burnFreezeWhenStreakAtRisk() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        profile.streakFreezeTokens = 2
        context.insert(profile)
        // Entry for yesterday only — no entry today
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let entry = RiyazEntry(date: yesterday, durationMinutes: 10)
        context.insert(entry)
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute(profile: profile)

        #expect(profile.streakFreezeTokens == 1, "Should burn 1 token to preserve streak")
    }

    @Test("No burn when no tokens available")
    func noBurnIfNoTokens() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        profile.streakFreezeTokens = 0
        context.insert(profile)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let entry = RiyazEntry(date: yesterday, durationMinutes: 10)
        context.insert(entry)
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute(profile: profile)

        #expect(profile.streakFreezeTokens == 0, "No tokens to burn — still zero")
    }

    @Test("No burn when practiced today (streak not at risk)")
    func noBurnWhenPracticedToday() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        profile.streakFreezeTokens = 2
        context.insert(profile)
        let entry = RiyazEntry(date: Date(), durationMinutes: 10)
        context.insert(entry)
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        let burned = tracker.burnFreezeIfStreakAtRisk(profile: profile)

        #expect(burned == false)
        #expect(profile.streakFreezeTokens == 2, "Should not burn when practiced today")
    }

    @Test("No burn when gap is more than 1 day")
    func noBurnForLargerGap() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        profile.streakFreezeTokens = 2
        context.insert(profile)
        // Entry 2 days ago — gap is too large for freeze to save
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let entry = RiyazEntry(date: twoDaysAgo, durationMinutes: 10)
        context.insert(entry)
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        let burned = tracker.burnFreezeIfStreakAtRisk(profile: profile)

        #expect(burned == false)
        #expect(profile.streakFreezeTokens == 2, "Longer gap not covered by freeze")
    }

    @Test("No burn when no practice entries exist")
    func noBurnWhenNoEntries() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        profile.streakFreezeTokens = 2
        context.insert(profile)
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute(profile: profile)

        // No lastPracticeDate → nothing to preserve
        #expect(profile.streakFreezeTokens == 2, "No entries means no burn")
    }

    // MARK: - Regression: existing StreakTracker callers

    @Test("recompute() with no profile param still works (backward compat)")
    func recomputeWithoutProfileDoesNotCrash() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let entry = RiyazEntry(date: Date(), durationMinutes: 10)
        context.insert(entry)
        try context.save()

        let tracker = StreakTracker(modelContext: context)
        tracker.recompute() // default nil profile — must not crash

        #expect(tracker.currentStreak == 1)
    }
}
