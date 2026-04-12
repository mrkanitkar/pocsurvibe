import Foundation
import SVCore

/// Static definitions for all 10 achievements in the initial release.
///
/// Each definition specifies an ID, display title, description,
/// XP bonus on unlock, and a trigger condition evaluated against
/// `AchievementContext`. Achievements are append-only per CloudKit rules.
enum AchievementDefinitions {

    /// A single achievement definition.
    struct Definition: Sendable {
        /// Unique identifier stored in `Achievement.achievementType`.
        let id: String
        /// Display title shown in the achievement gallery.
        let title: String
        /// Description shown when the achievement is earned.
        let description: String
        /// Bonus XP awarded when unlocked (0 for meta-achievements).
        let xpBonus: Int
        /// Evaluates whether the trigger condition is met.
        let trigger: @Sendable (AchievementContext) -> Bool
    }

    /// All 10 achievement definitions for the initial release.
    static let all: [Definition] = [
        Definition(
            id: "first_note",
            title: "First Note",
            description: "Detected your first pitch in practice",
            xpBonus: 10,
            trigger: { $0.firstPitchDetected }
        ),
        Definition(
            id: "first_song",
            title: "First Song",
            description: "Completed a song play-along for the first time",
            xpBonus: 25,
            trigger: { $0.songsCompleted >= 1 }
        ),
        Definition(
            id: "first_lesson",
            title: "First Lesson",
            description: "Completed your first lesson",
            xpBonus: 25,
            trigger: { $0.lessonsCompleted >= 1 }
        ),
        Definition(
            id: "streak_3",
            title: "3-Day Streak",
            description: "Practiced for 3 consecutive days",
            xpBonus: 50,
            trigger: { $0.currentStreak >= 3 }
        ),
        Definition(
            id: "streak_7",
            title: "Weekly Warrior",
            description: "Practiced for 7 consecutive days",
            xpBonus: 100,
            trigger: { $0.currentStreak >= 7 }
        ),
        Definition(
            id: "xp_100",
            title: "Century",
            description: "Earned 100 XP",
            xpBonus: 0,
            trigger: { $0.totalXP >= 100 }
        ),
        Definition(
            id: "xp_1000",
            title: "Sahasra",
            description: "Earned 1000 XP",
            xpBonus: 0,
            trigger: { $0.totalXP >= 1000 }
        ),
        Definition(
            id: "song_mastery",
            title: "Song Master",
            description: "Fully mastered a song",
            xpBonus: 50,
            trigger: { $0.songsCompleted >= 1 && $0.hasMasteredSong }
        ),
        Definition(
            id: "perfect_quiz",
            title: "Quiz Guru",
            description: "Scored 100% on a quiz",
            xpBonus: 30,
            trigger: { $0.latestQuizScore == 1.0 }
        ),
        Definition(
            id: "rang_up",
            title: "Rang Up",
            description: "Advanced to a new rang level",
            xpBonus: 50,
            trigger: { $0.newRangLevel != nil }
        ),
    ]
}

/// Context passed to achievement trigger evaluations.
///
/// Contains a snapshot of the user's current state — XP, streaks,
/// completion counts, and recent events. Built fresh before each
/// `checkTriggers()` call.
struct AchievementContext: Sendable {
    /// User's total accumulated XP.
    let totalXP: Int
    /// Current consecutive practice streak in days.
    let currentStreak: Int
    /// Number of unique songs completed (SongProgress.isCompleted = true).
    let songsCompleted: Int
    /// Number of lessons completed (LessonProgress.isCompleted = true).
    let lessonsCompleted: Int
    /// Total number of practice sessions (RiyazEntry count).
    let totalPracticeSessions: Int
    /// Most recent quiz score (nil if no quiz taken this session).
    let latestQuizScore: Double?
    /// New rang level if a level-up just occurred (nil otherwise).
    let newRangLevel: RangLevel?
    /// Whether the user detected their first pitch in this session.
    let firstPitchDetected: Bool
    /// Whether any song has been mastered (isCompleted with high score).
    let hasMasteredSong: Bool

    /// Default context with all zeros/nils for testing.
    static let empty = AchievementContext(
        totalXP: 0,
        currentStreak: 0,
        songsCompleted: 0,
        lessonsCompleted: 0,
        totalPracticeSessions: 0,
        latestQuizScore: nil,
        newRangLevel: nil,
        firstPitchDetected: false,
        hasMasteredSong: false
    )
}
