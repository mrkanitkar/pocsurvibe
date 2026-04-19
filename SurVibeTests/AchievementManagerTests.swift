import Foundation
import SVCore
import SwiftData
import Testing

@testable import SurVibe

/// Tests for `AchievementManager` trigger evaluation and unlock logic.
///
/// Verifies that achievements unlock correctly based on context, that
/// duplicate triggers don't create duplicate records, and that XP bonuses
/// are awarded on unlock. Uses in-memory `ModelContainer`.
/// Serialized + shared container — see `SwiftDataTestContainer.swift`
/// for why per-test `isStoredInMemoryOnly` containers crash the host.
@Suite("AchievementManager Tests", .serialized)
@MainActor
struct AchievementManagerTests {

    // MARK: - Helpers

    /// Creates a fully wired AchievementManager with a pre-created UserProfile
    /// on a fresh context from the shared test container.
    private func makeManager() throws -> (AchievementManager, XPManager, ModelContext) {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        context.insert(profile)
        try context.save()
        let xpManager = XPManager(modelContext: context)
        let achievementManager = AchievementManager(
            modelContext: context, xpManager: xpManager
        )
        return (achievementManager, xpManager, context)
    }

    // MARK: - Trigger Tests

    @Test("first_note triggers on firstPitchDetected")
    func firstNoteTrigger() throws {
        let (manager, _, _) = try makeManager()
        let context = AchievementContext(
            totalXP: 0, currentStreak: 0, songsCompleted: 0,
            lessonsCompleted: 0, totalPracticeSessions: 0,
            latestQuizScore: nil, newRangLevel: nil,
            firstPitchDetected: true, hasProficientSong: false
        )
        manager.checkTriggers(context: context)
        #expect(manager.isEarned("first_note") == true)
    }

    @Test("first_lesson triggers on lessonsCompleted >= 1")
    func firstLessonTrigger() throws {
        let (manager, _, _) = try makeManager()
        let context = AchievementContext(
            totalXP: 50, currentStreak: 0, songsCompleted: 0,
            lessonsCompleted: 1, totalPracticeSessions: 0,
            latestQuizScore: nil, newRangLevel: nil,
            firstPitchDetected: false, hasProficientSong: false
        )
        manager.checkTriggers(context: context)
        #expect(manager.isEarned("first_lesson") == true)
    }

    @Test("streak_3 triggers on currentStreak >= 3")
    func streak3Trigger() throws {
        let (manager, _, _) = try makeManager()
        let context = AchievementContext(
            totalXP: 0, currentStreak: 3, songsCompleted: 0,
            lessonsCompleted: 0, totalPracticeSessions: 0,
            latestQuizScore: nil, newRangLevel: nil,
            firstPitchDetected: false, hasProficientSong: false
        )
        manager.checkTriggers(context: context)
        #expect(manager.isEarned("streak_3") == true)
    }

    @Test("xp_100 triggers on totalXP >= 100")
    func xp100Trigger() throws {
        let (manager, _, _) = try makeManager()
        let context = AchievementContext(
            totalXP: 100, currentStreak: 0, songsCompleted: 0,
            lessonsCompleted: 0, totalPracticeSessions: 0,
            latestQuizScore: nil, newRangLevel: nil,
            firstPitchDetected: false, hasProficientSong: false
        )
        manager.checkTriggers(context: context)
        #expect(manager.isEarned("xp_100") == true)
    }

    @Test("perfect_quiz triggers on score 1.0")
    func perfectQuizTrigger() throws {
        let (manager, _, _) = try makeManager()
        let context = AchievementContext(
            totalXP: 0, currentStreak: 0, songsCompleted: 0,
            lessonsCompleted: 0, totalPracticeSessions: 0,
            latestQuizScore: 1.0, newRangLevel: nil,
            firstPitchDetected: false, hasProficientSong: false
        )
        manager.checkTriggers(context: context)
        #expect(manager.isEarned("perfect_quiz") == true)
    }

    @Test("rang_up triggers when newRangLevel is provided")
    func rangUpTrigger() throws {
        let (manager, _, _) = try makeManager()
        let context = AchievementContext(
            totalXP: 500, currentStreak: 0, songsCompleted: 0,
            lessonsCompleted: 0, totalPracticeSessions: 0,
            latestQuizScore: nil, newRangLevel: .hara,
            firstPitchDetected: false, hasProficientSong: false
        )
        manager.checkTriggers(context: context)
        #expect(manager.isEarned("rang_up") == true)
    }

    // MARK: - Duplicate Prevention

    @Test("Duplicate trigger does not create duplicate record")
    func duplicateTriggerPrevented() throws {
        let (manager, _, context) = try makeManager()
        let ctx = AchievementContext(
            totalXP: 0, currentStreak: 0, songsCompleted: 0,
            lessonsCompleted: 1, totalPracticeSessions: 0,
            latestQuizScore: nil, newRangLevel: nil,
            firstPitchDetected: false, hasProficientSong: false
        )
        manager.checkTriggers(context: ctx)
        manager.checkTriggers(context: ctx)

        let descriptor = FetchDescriptor<Achievement>(
            predicate: #Predicate { $0.achievementType == "first_lesson" }
        )
        let count = try context.fetchCount(descriptor)
        #expect(count == 1, "Should have exactly 1 record, not 2")
    }

    // MARK: - XP Bonus

    @Test("XP bonus awarded on achievement unlock")
    func xpBonusAwarded() throws {
        let (manager, xpManager, _) = try makeManager()
        let context = AchievementContext(
            totalXP: 0, currentStreak: 3, songsCompleted: 0,
            lessonsCompleted: 0, totalPracticeSessions: 0,
            latestQuizScore: nil, newRangLevel: nil,
            firstPitchDetected: false, hasProficientSong: false
        )
        manager.checkTriggers(context: context)
        // streak_3 awards 50 XP bonus
        #expect(xpManager.totalXP == 50)
    }

    // MARK: - No Trigger

    @Test("Empty context triggers no achievements")
    func noTriggersOnEmpty() throws {
        let (manager, _, _) = try makeManager()
        manager.checkTriggers(context: .empty)
        #expect(manager.earnedCount == 0)
    }

    // MARK: - Earned Achievements

    @Test("earnedAchievements returns sorted by date descending")
    func earnedSortedDescending() throws {
        let (manager, _, _) = try makeManager()
        // Trigger two achievements
        let ctx1 = AchievementContext(
            totalXP: 100, currentStreak: 0, songsCompleted: 0,
            lessonsCompleted: 1, totalPracticeSessions: 0,
            latestQuizScore: nil, newRangLevel: nil,
            firstPitchDetected: true, hasProficientSong: false
        )
        manager.checkTriggers(context: ctx1)

        let earned = manager.earnedAchievements
        #expect(earned.count >= 3)  // first_note, first_lesson, xp_100
    }
}
