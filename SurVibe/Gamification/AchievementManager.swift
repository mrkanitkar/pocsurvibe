import Foundation
import os.log
import SVCore
import SwiftData

/// Manages achievement unlocking, persistence, and XP bonus awards.
///
/// Evaluates 10 achievement trigger conditions against an `AchievementContext`
/// snapshot. When a trigger fires for an achievement that hasn't been earned yet,
/// the manager creates an `Achievement` record (append-only per CloudKit rules)
/// and optionally awards bonus XP via `XPManager`.
///
/// ## Usage
/// ```swift
/// let context = AchievementContext(totalXP: 150, currentStreak: 3, ...)
/// achievementManager.checkTriggers(context: context)
/// ```
///
/// ## CloudKit Compliance
/// - Achievements are append-only (never deleted).
/// - Unlocking is one-way (once earned, stays earned).
/// - `try modelContext.save()` called after each unlock (critical write).
@Observable @MainActor
final class AchievementManager {
    // MARK: - Properties

    /// The SwiftData model context for Achievement records.
    private let modelContext: ModelContext

    /// XP manager for awarding bonus XP on achievement unlock.
    private let xpManager: XPManager

    /// Logger for achievement events.
    private static let logger = Logger.survibe(category: "AchievementManager")

    /// Cache of earned achievement type IDs to avoid repeated fetches.
    private var earnedCache: Set<String> = []

    /// The most recently unlocked achievement, used to trigger the toast UI.
    /// Set by `unlock()`, cleared by the view after displaying.
    var lastUnlockedAchievement: AchievementDefinitions.Definition?

    // MARK: - Initialization

    /// Creates an AchievementManager.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData context for persistence.
    ///   - xpManager: The XP manager for bonus XP awards.
    init(modelContext: ModelContext, xpManager: XPManager) {
        self.modelContext = modelContext
        self.xpManager = xpManager
        loadEarnedCache()
    }

    // MARK: - Computed Properties

    /// All earned achievements, sorted by earned date (newest first).
    var earnedAchievements: [Achievement] {
        let descriptor = FetchDescriptor<Achievement>(
            sortBy: [SortDescriptor(\Achievement.earnedAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Self.logger.error(
                "Failed to fetch achievements: \(error.localizedDescription)"
            )
            return []
        }
    }

    /// Number of achievements earned.
    var earnedCount: Int {
        earnedCache.count
    }

    // MARK: - Public Methods

    /// Check all trigger conditions and unlock newly earned achievements.
    ///
    /// Evaluates each of the 10 achievement definitions against the provided
    /// context. For any trigger that fires on an unearned achievement, creates
    /// an `Achievement` record and awards bonus XP.
    ///
    /// - Parameter context: A snapshot of the user's current state.
    func checkTriggers(context: AchievementContext) {
        for definition in AchievementDefinitions.all {
            guard !earnedCache.contains(definition.id) else { continue }

            if definition.trigger(context) {
                unlock(definition: definition)
            }
        }
    }

    /// Whether a specific achievement has been earned.
    ///
    /// Uses the in-memory cache for fast lookups without a SwiftData fetch.
    ///
    /// - Parameter achievementId: The achievement type ID.
    /// - Returns: `true` if the achievement has been earned.
    func isEarned(_ achievementId: String) -> Bool {
        earnedCache.contains(achievementId)
    }

    // MARK: - Private Methods

    /// Load earned achievement IDs from SwiftData into the cache.
    private func loadEarnedCache() {
        let descriptor = FetchDescriptor<Achievement>()
        do {
            let achievements = try modelContext.fetch(descriptor)
            earnedCache = Set(achievements.map(\.achievementType))
        } catch {
            Self.logger.error(
                "Failed to load earned cache: \(error.localizedDescription)"
            )
            earnedCache = []
        }
    }

    /// Unlock a single achievement: create the record and award bonus XP.
    ///
    /// - Parameter definition: The achievement definition to unlock.
    private func unlock(definition: AchievementDefinitions.Definition) {
        let achievement = Achievement(
            achievementType: definition.id,
            title: definition.title,
            achievementDescription: definition.description,
            xpReward: definition.xpBonus
        )
        modelContext.insert(achievement)

        // Critical write: persist immediately
        do {
            try modelContext.save()
        } catch {
            Self.logger.error(
                "Failed to save achievement '\(definition.id)': \(error.localizedDescription)"
            )
        }

        // Award bonus XP (if any)
        if definition.xpBonus > 0 {
            xpManager.awardXP(
                amount: definition.xpBonus,
                source: .achievement,
                sourceId: definition.id
            )
        }

        // Update cache
        earnedCache.insert(definition.id)

        // Trigger toast notification in the UI
        lastUnlockedAchievement = definition

        Self.logger.info(
            "Achievement unlocked: '\(definition.title)' (+\(definition.xpBonus) XP)"
        )
    }
}
