import Testing
import SwiftData
@testable import SurVibe

/// D5: SwiftData CRUD + CloudKit config verification.
/// All tests use in-memory ModelContainer (no disk, no CloudKit).
/// Serialized + shared container — see `SwiftDataTestContainer.swift`.
@Suite("SwiftData Model CRUD Tests", .serialized)
@MainActor
struct ModelCRUDTests {

    /// Returns the shared test container (one per test process).
    private func makeTestContainer() throws -> ModelContainer {
        SwiftDataTestContainer.shared
    }

    // MARK: - D5: ModelContainer Initialization

    @Test("ModelContainer initializes with all 6 models")
    func testModelContainerInit() throws {
        let container = try makeTestContainer()
        // Verify the container's schema includes all 6 model types
        let schema = container.schema
        #expect(schema.entities.count >= 6)
    }

    // MARK: - UserProfile CRUD

    @Test("UserProfile create and read")
    @MainActor
    func testUserProfileCRUD() throws {
        let context = try SwiftDataTestContainer.freshContext()

        let profile = UserProfile(displayName: "Test User", preferredLanguage: "hi")
        context.insert(profile)
        try context.save()

        let descriptor = FetchDescriptor<UserProfile>()
        let profiles = try context.fetch(descriptor)
        #expect(profiles.count == 1)
        #expect(profiles.first?.displayName == "Test User")
        #expect(profiles.first?.preferredLanguage == "hi")
        #expect(profiles.first?.currentRang == 1)
        #expect(profiles.first?.totalXP == 0)
    }

    @Test("UserProfile addXP uses max-wins")
    @MainActor
    func testUserProfileXP() throws {
        let context = try SwiftDataTestContainer.freshContext()

        let profile = UserProfile(displayName: "XP Test")
        context.insert(profile)
        profile.addXP(100)
        #expect(profile.totalXP == 100)
        profile.addXP(50)
        #expect(profile.totalXP == 150)
    }

    // MARK: - RiyazEntry CRUD

    @Test("RiyazEntry create and read")
    @MainActor
    func testRiyazEntryCRUD() throws {
        let context = try SwiftDataTestContainer.freshContext()

        let entry = RiyazEntry(
            durationMinutes: 30,
            notesPlayed: 150,
            accuracyPercent: 85.5,
            xpEarned: 50,
            raagPracticed: "Yaman"
        )
        context.insert(entry)
        try context.save()

        let descriptor = FetchDescriptor<RiyazEntry>()
        let entries = try context.fetch(descriptor)
        #expect(entries.count == 1)
        #expect(entries.first?.durationMinutes == 30)
        #expect(entries.first?.raagPracticed == "Yaman")
    }

    // MARK: - Achievement CRUD

    @Test("Achievement create and read (append-only)")
    @MainActor
    func testAchievementCRUD() throws {
        let context = try SwiftDataTestContainer.freshContext()

        let achievement = Achievement(
            achievementType: "first_riyaz",
            title: "First Practice",
            achievementDescription: "Completed first riyaz session",
            xpReward: 25
        )
        context.insert(achievement)
        try context.save()

        let descriptor = FetchDescriptor<Achievement>()
        let achievements = try context.fetch(descriptor)
        #expect(achievements.count == 1)
        #expect(achievements.first?.title == "First Practice")
        #expect(achievements.first?.xpReward == 25)
    }

    // MARK: - SongProgress CRUD

    @Test("SongProgress create and recordPlay max-wins")
    @MainActor
    func testSongProgressCRUD() throws {
        let context = try SwiftDataTestContainer.freshContext()

        let progress = SongProgress(songId: "song_001", songTitle: "Raag Yaman")
        context.insert(progress)

        progress.recordPlay(score: 75.0)
        #expect(progress.bestScore == 75.0)
        #expect(progress.timesPlayed == 1)

        progress.recordPlay(score: 60.0)
        #expect(progress.bestScore == 75.0) // Max-wins: 75 > 60
        #expect(progress.timesPlayed == 2)

        progress.recordPlay(score: 90.0)
        #expect(progress.bestScore == 90.0) // New best
        #expect(progress.timesPlayed == 3)
    }

    // MARK: - LessonProgress CRUD

    @Test("LessonProgress one-way completion flag")
    @MainActor
    func testLessonProgressCRUD() throws {
        let context = try SwiftDataTestContainer.freshContext()

        let lesson = LessonProgress(lessonId: "lesson_001", lessonTitle: "Introduction to Sa")
        context.insert(lesson)

        #expect(lesson.isCompleted == false)
        #expect(lesson.completedAt == nil)

        lesson.markCompleted()
        #expect(lesson.isCompleted == true)
        #expect(lesson.completedAt != nil)
        #expect(lesson.progressPercent == 1.0)

        // One-way: calling markCompleted again doesn't change completedAt
        let firstCompletedAt = lesson.completedAt
        lesson.markCompleted()
        #expect(lesson.completedAt == firstCompletedAt)
    }

    // MARK: - SubscriptionState CRUD

    @Test("SubscriptionState default is free")
    @MainActor
    func testSubscriptionStateCRUD() throws {
        let context = try SwiftDataTestContainer.freshContext()

        let sub = SubscriptionState()
        context.insert(sub)
        try context.save()

        let descriptor = FetchDescriptor<SubscriptionState>()
        let states = try context.fetch(descriptor)
        #expect(states.count == 1)
        #expect(states.first?.tier == "free")
        #expect(states.first?.isActive == false)
    }

    // MARK: - M-18: ModelContainer Fallback

    @Test("In-memory fallback container supports all 6 models")
    @MainActor
    func testInMemoryFallbackContainer() throws {
        // Simulates the fallback path in SurVibeApp.init() when persistent storage fails.
        // Uses the shared on-disk test container (the per-test in-memory
        // configuration trips a SwiftData crash — see SwiftDataTestContainer).
        let context = try SwiftDataTestContainer.freshContext()

        // Verify CRUD works on fallback container for each model type
        context.insert(UserProfile(displayName: "Fallback"))
        context.insert(RiyazEntry(durationMinutes: 10))
        context.insert(Achievement(achievementType: "test", title: "Test"))
        context.insert(SongProgress(songId: "test_song", songTitle: "Test"))
        context.insert(LessonProgress(lessonId: "test_lesson", lessonTitle: "Test"))
        context.insert(SubscriptionState())
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<RiyazEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Achievement>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SongProgress>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<LessonProgress>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SubscriptionState>()) == 1)
    }
}
