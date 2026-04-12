import Foundation
import SVCore
import SwiftData
import Testing

@testable import SurVibe

/// Tests for `AchievementUnlockToast` initialization and the
/// `lastUnlockedAchievement` property on `AchievementManager`.
///
/// Verifies toast properties are correctly passed through and that
/// the manager's observable property is set on unlock and can be cleared.
@Suite("AchievementUnlockToast Tests")
struct AchievementUnlockToastTests {

    // MARK: - Toast Property Tests

    @Test("Toast initializes with correct title")
    func toastInitializesWithTitle() {
        let toast = AchievementUnlockToast(
            title: "First Note",
            xpBonus: 10,
            onDismiss: {}
        )
        #expect(toast.title == "First Note")
        #expect(toast.xpBonus == 10)
    }

    @Test("Toast exposes non-zero XP bonus")
    func toastShowsXPWhenNonZero() {
        let toast = AchievementUnlockToast(
            title: "3-Day Streak",
            xpBonus: 25,
            onDismiss: {}
        )
        #expect(toast.xpBonus > 0)
    }

    @Test("Toast exposes zero XP bonus")
    func toastHidesXPWhenZero() {
        let toast = AchievementUnlockToast(
            title: "Century",
            xpBonus: 0,
            onDismiss: {}
        )
        #expect(toast.xpBonus == 0)
    }

    // MARK: - Manager Integration Tests

    /// Creates an in-memory ModelContainer with all required models.
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

    @Test("lastUnlockedAchievement is set on unlock")
    @MainActor
    func lastUnlockedSetOnUnlock() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = UserProfile()
        context.insert(profile)
        try context.save()

        let xpManager = XPManager(modelContext: context)
        let manager = AchievementManager(modelContext: context, xpManager: xpManager)

        #expect(manager.lastUnlockedAchievement == nil)

        // Trigger first_note achievement
        let achievementContext = AchievementContext(
            totalXP: 0, currentStreak: 0, songsCompleted: 0,
            lessonsCompleted: 0, totalPracticeSessions: 0,
            latestQuizScore: nil, newRangLevel: nil,
            firstPitchDetected: true, hasProficientSong: false
        )
        manager.checkTriggers(context: achievementContext)

        #expect(manager.lastUnlockedAchievement != nil)
        #expect(manager.lastUnlockedAchievement?.title == "First Note")
    }

    @Test("lastUnlockedAchievement clears on nil assignment")
    @MainActor
    func lastUnlockedClearsOnNil() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = UserProfile()
        context.insert(profile)
        try context.save()

        let xpManager = XPManager(modelContext: context)
        let manager = AchievementManager(modelContext: context, xpManager: xpManager)

        // Trigger an achievement
        let achievementContext = AchievementContext(
            totalXP: 0, currentStreak: 0, songsCompleted: 0,
            lessonsCompleted: 0, totalPracticeSessions: 0,
            latestQuizScore: nil, newRangLevel: nil,
            firstPitchDetected: true, hasProficientSong: false
        )
        manager.checkTriggers(context: achievementContext)
        #expect(manager.lastUnlockedAchievement != nil)

        // Simulate toast dismissal
        manager.lastUnlockedAchievement = nil
        #expect(manager.lastUnlockedAchievement == nil)
    }
}
