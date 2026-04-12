import Foundation
import os.log
import SVCore
import SwiftData

/// XP award source types. Stored as String rawValue in `XPEntry.source`.
///
/// Each case maps to a specific gameplay action that earns XP.
/// Raw values use `snake_case` to match analytics event naming conventions.
enum XPSource: String, Sendable {
    /// XP earned from completing a lesson step.
    case lessonStep = "lesson_step"
    /// XP earned from a riyaz (practice) session.
    case practice = "practice"
    /// XP earned from achieving proficiency in a song (high score threshold).
    case songProficiency = "song_mastery"
    /// XP earned from unlocking an achievement.
    case achievement = "achievement"
    /// Bonus XP earned from maintaining a daily practice streak.
    case streak = "streak_bonus"
}

/// Manages XP awards, history, and aggregation for the gamification system.
///
/// XPManager is the single entry point for all XP operations. It creates
/// append-only `XPEntry` records and updates the `UserProfile.totalXP`
/// using the `addXP(_:)` high-water-mark method.
///
/// All SwiftData operations use `do/catch` with explicit `modelContext.save()`
/// for critical writes (XP awards) per CloudKit sync safety rules.
///
/// ## Usage
/// ```swift
/// let manager = XPManager(modelContext: context)
/// manager.awardXP(amount: 10, source: .lessonStep, sourceId: "lesson-01")
/// ```
@Observable @MainActor
final class XPManager {
    // MARK: - Properties

    /// The SwiftData model context used for all persistence operations.
    private let modelContext: ModelContext

    /// Logger for XP operations (subsystem: "com.survibe", category: "XPManager").
    private static let logger = Logger.survibe(category: "XPManager")

    // MARK: - Initialization

    /// Creates an XPManager bound to the given model context.
    ///
    /// - Parameter modelContext: The SwiftData context for reading and writing XP data.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    /// Award XP to the current user.
    ///
    /// Creates an append-only `XPEntry` record and increments `UserProfile.totalXP`.
    /// The operation is a no-op if `amount` is zero or negative.
    /// Uses explicit `modelContext.save()` as this is a critical write (XP award).
    ///
    /// - Parameters:
    ///   - amount: XP to award. Must be greater than 0 or the call is a no-op.
    ///   - source: The gameplay action that triggered this award.
    ///   - sourceId: ID of the associated entity (lesson, song, etc.). Defaults to empty.
    func awardXP(amount: Int, source: XPSource, sourceId: String = "") {
        guard amount > 0 else {
            Self.logger.debug("awardXP called with non-positive amount (\(amount)), ignoring")
            return
        }

        let entry = XPEntry(amount: amount, source: source.rawValue, sourceId: sourceId)
        modelContext.insert(entry)

        // Update UserProfile.totalXP (fetch or create)
        let profile = fetchOrCreateProfile()
        profile.addXP(amount)

        do {
            try modelContext.save()
            Self.logger.info("Awarded \(amount) XP from \(source.rawValue, privacy: .public) (sourceId: \(sourceId, privacy: .public))")
        } catch {
            Self.logger.error("Failed to save XP award: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Computed Properties

    /// Total XP from the current user's profile.
    ///
    /// Fetches the first `UserProfile` and returns its `totalXP`.
    /// Returns 0 if no profile exists or the fetch fails.
    var totalXP: Int {
        let descriptor = FetchDescriptor<UserProfile>()
        do {
            let profiles = try modelContext.fetch(descriptor)
            return profiles.first?.totalXP ?? 0
        } catch {
            Self.logger.error(
                "Failed to fetch UserProfile for totalXP: \(error.localizedDescription, privacy: .public)"
            )
            return 0
        }
    }

    /// XP earned today (since midnight local time).
    ///
    /// Sums all `XPEntry.amount` values where `earnedAt` is on or after
    /// the start of the current calendar day.
    /// Returns 0 if no entries exist today or the fetch fails.
    var xpToday: Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        var descriptor = FetchDescriptor<XPEntry>(
            predicate: #Predicate<XPEntry> { $0.earnedAt >= startOfDay }
        )
        descriptor.fetchLimit = 1000
        do {
            let entries = try modelContext.fetch(descriptor)
            return entries.reduce(0) { $0 + $1.amount }
        } catch {
            Self.logger.error("Failed to fetch today's XP entries: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    /// Most recent 20 XP entries sorted by `earnedAt` descending.
    ///
    /// Returns an empty array if no entries exist or the fetch fails.
    var recentEntries: [XPEntry] {
        var descriptor = FetchDescriptor<XPEntry>(
            sortBy: [SortDescriptor(\.earnedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Self.logger.error("Failed to fetch recent XP entries: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Private Methods

    /// Fetches the existing UserProfile or creates a new one if none exists.
    ///
    /// Ensures a single profile record is always available for XP operations.
    /// - Returns: The current `UserProfile` instance.
    private func fetchOrCreateProfile() -> UserProfile {
        let descriptor = FetchDescriptor<UserProfile>()
        do {
            let profiles = try modelContext.fetch(descriptor)
            if let existing = profiles.first {
                return existing
            }
        } catch {
            Self.logger.error("Failed to fetch UserProfile: \(error.localizedDescription, privacy: .public)")
        }

        let newProfile = UserProfile()
        modelContext.insert(newProfile)
        Self.logger.info("Created new UserProfile for XP tracking")
        return newProfile
    }
}
