import Foundation
import os.log
import SVCore
import SwiftData

/// Centralizes all gamification side-effects (XP, Rang, Achievements) behind a single facade.
///
/// Created once at app launch and injected via `.environment()`. Gameplay surfaces
/// (lesson completion, practice session, quiz) call the `handle*` methods; this
/// service delegates to XPManager, RangSystem, AchievementManager, and StreakTracker.
///
/// ## Why a single service?
/// XP awards, rang recalculation, and achievement evaluation must happen atomically
/// after each gameplay event. Spreading this across individual views leads to the
/// integration gaps identified in the Phase 3 audit.
///
/// ## ModelContext
/// Uses its own `ModelContext` from the same `ModelContainer`. All critical writes
/// call `modelContext.save()`, so changes are visible to the view hierarchy's context.
@Observable @MainActor
final class GamificationService {
    // MARK: - Properties

    /// XP award manager.
    let xpManager: XPManager

    /// Rang (level) progression system.
    let rangSystem: RangSystem

    /// Achievement unlock manager.
    let achievementManager: AchievementManager

    /// Practice streak tracker.
    let streakTracker: StreakTracker

    /// The model context used for achievement context queries.
    private let modelContext: ModelContext

    /// Logger for gamification events.
    private static let logger = Logger.survibe(category: "GamificationService")

    // MARK: - Initialization

    /// Creates the gamification service with a dedicated model context.
    ///
    /// All sub-managers share this context. The context comes from the same
    /// `ModelContainer` as the view hierarchy, so explicit `save()` calls
    /// keep both in sync.
    ///
    /// - Parameter modelContext: A `ModelContext` from the app's `ModelContainer`.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        let xp = XPManager(modelContext: modelContext)
        self.xpManager = xp
        self.rangSystem = RangSystem(modelContext: modelContext)
        self.streakTracker = StreakTracker(modelContext: modelContext)
        self.achievementManager = AchievementManager(modelContext: modelContext, xpManager: xp)

        streakTracker.recompute(profile: fetchUserProfile())
    }

    // MARK: - Gameplay Event Handlers

    /// Called when a lesson step is completed (listen, sing, exercise, quiz).
    ///
    /// Awards 10 XP per step, then evaluates achievements and rang progression.
    ///
    /// - Parameters:
    ///   - lessonId: The lesson's unique identifier.
    ///   - stepType: The step type string (e.g. "listen", "sing", "quiz").
    ///   - quizScore: The quiz score if this was a quiz step (0.0–1.0), nil otherwise.
    func handleStepCompleted(lessonId: String, stepType: String, quizScore: Double? = nil) {
        xpManager.awardXP(amount: 10, source: .lessonStep, sourceId: lessonId)

        let newRang = rangSystem.recalculate()
        evaluateAchievements(latestQuizScore: quizScore, newRangLevel: newRang)

        Self.logger.info("Step completed: \(stepType, privacy: .public) in lesson \(lessonId, privacy: .public)")
    }

    /// Called when all steps in a lesson are finished.
    ///
    /// Awards 25 bonus XP for lesson completion on top of per-step XP.
    /// Recalculates rang and checks all achievement triggers.
    ///
    /// - Parameters:
    ///   - lessonId: The completed lesson's identifier.
    ///   - quizScore: The best quiz score from this lesson (0.0–1.0), nil if no quiz.
    func handleLessonCompleted(lessonId: String, quizScore: Double? = nil) {
        xpManager.awardXP(amount: 25, source: .lessonStep, sourceId: "\(lessonId)_complete")

        let newRang = rangSystem.recalculate()
        evaluateAchievements(latestQuizScore: quizScore, newRangLevel: newRang)

        Self.logger.info("Lesson completed: \(lessonId, privacy: .public)")
    }

    /// Called when a practice session finishes.
    ///
    /// Awards practice XP (pre-computed by `PracticeScoring`), optionally awards
    /// song proficiency XP, recomputes streak, and evaluates achievements.
    ///
    /// - Parameters:
    ///   - xp: XP earned from practice (from `PracticeScoring.xpEarned`).
    ///   - songId: The practiced song's identifier.
    ///   - songProficient: Whether the song reached proficiency (>= 3 stars) in this session.
    func handlePracticeCompleted(xp: Int, songId: String, songProficient: Bool) {
        xpManager.awardXP(amount: xp, source: .practice, sourceId: songId)

        if songProficient {
            xpManager.awardXP(amount: 50, source: .songProficiency, sourceId: songId)
        }

        streakTracker.recompute(profile: fetchUserProfile())

        let newRang = rangSystem.recalculate()
        evaluateAchievements(newRangLevel: newRang, hasProficientSong: songProficient)

        Self.logger.info(
            "Practice completed: song=\(songId, privacy: .public) xp=\(xp) mastered=\(songProficient)"
        )
    }

    /// Called when the user detects their first pitch in a practice session.
    ///
    /// Checks the `first_note` achievement trigger.
    func handleFirstPitchDetected() {
        evaluateAchievements(firstPitchDetected: true)
    }

    /// Refresh streak data (call when ProfileTab appears or after practice).
    func refreshStreak() {
        streakTracker.recompute(profile: fetchUserProfile())
    }

    // MARK: - Private Methods

    /// Fetch the singleton UserProfile from the model context, or nil on error.
    ///
    /// Used to pass the profile into streak-freeze logic without creating a new profile.
    private func fetchUserProfile() -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>()
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            Self.logger.error(
                "Failed to fetch UserProfile for streak freeze: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Build an `AchievementContext` from current SwiftData state and check triggers.
    ///
    /// Queries the model context for completion counts, streak, XP totals, and
    /// passes the provided event-specific flags to the achievement evaluator.
    ///
    /// - Parameters:
    ///   - latestQuizScore: Quiz score from the just-completed step, if any.
    ///   - newRangLevel: New rang if a level-up just occurred.
    ///   - firstPitchDetected: Whether this is the user's first pitch detection.
    ///   - hasProficientSong: Whether a song reached proficiency in this session.
    private func evaluateAchievements(
        latestQuizScore: Double? = nil,
        newRangLevel: RangLevel? = nil,
        firstPitchDetected: Bool = false,
        hasProficientSong: Bool = false
    ) {
        let context = buildAchievementContext(
            latestQuizScore: latestQuizScore,
            newRangLevel: newRangLevel,
            firstPitchDetected: firstPitchDetected,
            hasProficientSong: hasProficientSong
        )
        achievementManager.checkTriggers(context: context)
    }

    /// Builds an `AchievementContext` by querying current state from SwiftData.
    ///
    /// - Parameters:
    ///   - latestQuizScore: Quiz score from the current event.
    ///   - newRangLevel: Rang level if a level-up occurred.
    ///   - firstPitchDetected: First pitch flag.
    ///   - hasProficientSong: Song proficiency flag.
    /// - Returns: A populated `AchievementContext`.
    private func buildAchievementContext(
        latestQuizScore: Double?,
        newRangLevel: RangLevel?,
        firstPitchDetected: Bool,
        hasProficientSong: Bool
    ) -> AchievementContext {
        let songsCompleted = fetchCount(
            FetchDescriptor<SongProgress>(
                predicate: #Predicate { $0.isCompleted == true }
            )
        )
        let lessonsCompleted = fetchCount(
            FetchDescriptor<LessonProgress>(
                predicate: #Predicate { $0.isCompleted == true }
            )
        )
        let totalPracticeSessions = fetchCount(FetchDescriptor<RiyazEntry>())

        // Check if any song has been mastered (best score >= 90)
        let proficientSongCheck: Bool
        if hasProficientSong {
            proficientSongCheck = true
        } else {
            let proficientDescriptor = FetchDescriptor<SongProgress>(
                predicate: #Predicate { $0.isCompleted == true && $0.bestScore >= 90.0 }
            )
            proficientSongCheck = fetchCount(proficientDescriptor) > 0
        }

        return AchievementContext(
            totalXP: xpManager.totalXP,
            currentStreak: streakTracker.currentStreak,
            songsCompleted: songsCompleted,
            lessonsCompleted: lessonsCompleted,
            totalPracticeSessions: totalPracticeSessions,
            latestQuizScore: latestQuizScore,
            newRangLevel: newRangLevel,
            firstPitchDetected: firstPitchDetected,
            hasProficientSong: proficientSongCheck
        )
    }

    /// Safe fetch count that returns 0 on error.
    private func fetchCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> Int {
        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            let typeName = String(describing: T.self)
            let message = error.localizedDescription
            Self.logger.error(
                "Failed to fetch count for \(typeName, privacy: .public): \(message, privacy: .public)"
            )
            return 0
        }
    }
}
