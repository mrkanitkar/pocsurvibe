import Foundation
import SVCore
import SwiftData
import Testing
@testable import SurVibe

/// Tests for GamificationService integration wiring.
///
/// Verifies that gameplay events (step completion, lesson completion,
/// practice completion) flow through to XPManager, RangSystem, and
/// AchievementManager correctly.
@Suite("GamificationService Tests")
@MainActor
struct GamificationServiceTests {

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

    /// Creates a container, inserts a UserProfile, and returns a configured GamificationService.
    @MainActor
    private func makeService() throws -> (GamificationService, ModelContext) {
        let container = try makeContainer()
        let context = container.mainContext
        let profile = UserProfile(displayName: "Test User")
        context.insert(profile)
        try context.save()
        let service = GamificationService(modelContext: context)
        return (service, context)
    }

    // MARK: - Step Completion Tests

    @Test @MainActor
    func stepCompletionAwardsXP() throws {
        let (service, _) = try makeService()

        service.handleStepCompleted(lessonId: "lesson-01", stepType: "listen")

        #expect(service.xpManager.totalXP == 10)
    }

    @Test @MainActor
    func multipleStepsAccumulateXP() throws {
        let (service, _) = try makeService()

        service.handleStepCompleted(lessonId: "lesson-01", stepType: "listen")
        service.handleStepCompleted(lessonId: "lesson-01", stepType: "sing")
        service.handleStepCompleted(lessonId: "lesson-01", stepType: "exercise")

        #expect(service.xpManager.totalXP == 30)
    }

    // MARK: - Lesson Completion Tests

    @Test @MainActor
    func lessonCompletionAwardsBonusXP() throws {
        let (service, _) = try makeService()

        service.handleLessonCompleted(lessonId: "lesson-01")

        #expect(service.xpManager.totalXP == 25)
    }

    @Test @MainActor
    func fullLessonFlowAccumulatesCorrectXP() throws {
        let (service, _) = try makeService()

        // 3 steps × 10 XP + 25 XP lesson bonus = 55 XP
        service.handleStepCompleted(lessonId: "lesson-01", stepType: "listen")
        service.handleStepCompleted(lessonId: "lesson-01", stepType: "sing")
        service.handleStepCompleted(lessonId: "lesson-01", stepType: "quiz", quizScore: 0.85)
        service.handleLessonCompleted(lessonId: "lesson-01", quizScore: 0.85)

        #expect(service.xpManager.totalXP == 55)
    }

    // MARK: - Practice Completion Tests

    @Test @MainActor
    func practiceCompletionAwardsXP() throws {
        let (service, _) = try makeService()

        service.handlePracticeCompleted(xp: 20, songId: "song-01", songMastered: false)

        #expect(service.xpManager.totalXP == 20)
    }

    @Test @MainActor
    func practiceWithMasteryAwardsBonusXP() throws {
        let (service, _) = try makeService()

        // 20 practice XP + 50 mastery XP = 70 XP
        service.handlePracticeCompleted(xp: 20, songId: "song-01", songMastered: true)

        #expect(service.xpManager.totalXP == 70)
    }

    // MARK: - Rang Progression Tests

    @Test @MainActor
    func rangRecalculatesAfterXPAward() throws {
        let (service, _) = try makeService()

        // Award enough XP to reach Hara (500 XP threshold)
        for i in 0..<50 {
            service.handleStepCompleted(lessonId: "lesson-\(i)", stepType: "listen")
        }

        #expect(service.xpManager.totalXP == 500)
        #expect(service.rangSystem.currentRang == .hara)
    }

    // MARK: - Achievement Tests

    @Test @MainActor
    func firstLessonAchievementUnlocks() throws {
        let (service, context) = try makeService()

        // Create a completed lesson progress to satisfy the achievement trigger
        let progress = LessonProgress(lessonId: "lesson-01")
        progress.isCompleted = true
        context.insert(progress)
        try context.save()

        service.handleLessonCompleted(lessonId: "lesson-01")

        #expect(service.achievementManager.isEarned("first_lesson"))
    }

    @Test @MainActor
    func xpMilestoneAchievementUnlocks() throws {
        let (service, _) = try makeService()

        // Award 100+ XP to trigger "Century" achievement
        for i in 0..<10 {
            service.handleStepCompleted(lessonId: "lesson-\(i)", stepType: "listen")
        }

        #expect(service.xpManager.totalXP == 100)
        #expect(service.achievementManager.isEarned("xp_100"))
    }

    @Test @MainActor
    func perfectQuizAchievementUnlocks() throws {
        let (service, _) = try makeService()

        service.handleStepCompleted(
            lessonId: "lesson-01",
            stepType: "quiz",
            quizScore: 1.0
        )

        #expect(service.achievementManager.isEarned("perfect_quiz"))
    }

    @Test @MainActor
    func firstPitchAchievementUnlocks() throws {
        let (service, _) = try makeService()

        service.handleFirstPitchDetected()

        #expect(service.achievementManager.isEarned("first_note"))
    }

    // MARK: - XPEntry Record Tests

    @Test @MainActor
    func stepCompletionCreatesXPEntry() throws {
        let (service, context) = try makeService()

        service.handleStepCompleted(lessonId: "lesson-01", stepType: "sing")

        let descriptor = FetchDescriptor<XPEntry>()
        let entries = try context.fetch(descriptor)
        #expect(entries.count == 1)
        #expect(entries.first?.amount == 10)
        #expect(entries.first?.source == "lesson_step")
    }

    @Test @MainActor
    func practiceCompletionCreatesXPEntries() throws {
        let (service, context) = try makeService()

        service.handlePracticeCompleted(xp: 30, songId: "song-01", songMastered: true)

        let descriptor = FetchDescriptor<XPEntry>(
            sortBy: [SortDescriptor(\.earnedAt)]
        )
        let entries = try context.fetch(descriptor)
        // 1 practice entry + 1 mastery entry = 2
        #expect(entries.count == 2)

        let practiceEntry = entries.first { $0.source == "practice" }
        let masteryEntry = entries.first { $0.source == "song_mastery" }
        #expect(practiceEntry?.amount == 30)
        #expect(masteryEntry?.amount == 50)
    }
}
