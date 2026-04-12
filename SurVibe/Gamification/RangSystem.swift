import Foundation
import os.log
import SVCore
import SwiftData

/// Manages Rang (level) progression based on accumulated XP.
///
/// Uses the existing `RangLevel` enum from SVCore which defines 5 levels
/// (Neel/Hara/Peela/Lal/Sona) with XP thresholds (0/500/2000/5000/10000).
/// After each XP award, call `recalculate()` to check if the user has
/// crossed a threshold and leveled up.
///
/// ## CloudKit Conflict Resolution
/// `UserProfile.currentRang` uses max-wins — if a sync conflict delivers a
/// lower rang value, the higher value is kept (rang only increases).
@Observable @MainActor
final class RangSystem {
    // MARK: - Properties

    /// The SwiftData model context for UserProfile access.
    private let modelContext: ModelContext

    /// Logger for rang progression events.
    private static let logger = Logger(subsystem: "com.survibe", category: "RangSystem")

    // MARK: - Initialization

    /// Creates a RangSystem backed by the given model context.
    ///
    /// - Parameter modelContext: The SwiftData context used to read/write UserProfile.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Computed Properties

    /// Current rang level derived from the user's total XP.
    ///
    /// Reads `UserProfile.totalXP` and maps it to a `RangLevel` via
    /// `RangLevel.level(for:)`. Returns `.neel` if no profile exists.
    var currentRang: RangLevel {
        RangLevel.level(for: fetchTotalXP())
    }

    /// XP required to reach the next rang level.
    ///
    /// Returns 0 if the user is already at the maximum level (Sona).
    var xpToNextRang: Int {
        let xp = fetchTotalXP()
        let current = RangLevel.level(for: xp)
        guard let nextLevel = RangLevel(rawValue: current.rawValue + 1) else {
            return 0  // Already at max level (Sona)
        }
        return nextLevel.xpThreshold - xp
    }

    /// Fraction of progress toward the next rang level (0.0–1.0).
    ///
    /// Returns 1.0 if the user is at the maximum level (Sona).
    var progressToNextRang: Double {
        let xp = fetchTotalXP()
        let current = RangLevel.level(for: xp)
        guard let nextLevel = RangLevel(rawValue: current.rawValue + 1) else {
            return 1.0  // Max level
        }
        let rangeStart = current.xpThreshold
        let rangeEnd = nextLevel.xpThreshold
        let range = rangeEnd - rangeStart
        guard range > 0 else { return 1.0 }
        return Double(xp - rangeStart) / Double(range)
    }

    // MARK: - Public Methods

    /// Recalculate rang level after XP changes.
    ///
    /// Compares the computed rang (from XP) against the stored `UserProfile.currentRang`.
    /// If a level-up occurred, updates the profile and returns the new level.
    /// Uses max-wins: the stored rang only increases, never decreases.
    ///
    /// - Returns: The new `RangLevel` if a level-up occurred, `nil` otherwise.
    @discardableResult
    func recalculate() -> RangLevel? {
        let xp = fetchTotalXP()
        let computedLevel = RangLevel.level(for: xp)
        let storedRang = fetchStoredRang()

        guard computedLevel.rawValue > storedRang else {
            return nil  // No level-up
        }

        // Level-up: update profile (max-wins ensures rang only increases)
        updateStoredRang(computedLevel.rawValue)
        Self.logger.info(
            "Rang up: \(storedRang) → \(computedLevel.rawValue) (\(computedLevel.displayName)) at \(xp) XP"
        )
        return computedLevel
    }

    // MARK: - Private Methods

    /// Fetch total XP from the first UserProfile.
    ///
    /// Returns 0 if no profile exists.
    private func fetchTotalXP() -> Int {
        let descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\UserProfile.createdAt)]
        )
        do {
            return try modelContext.fetch(descriptor).first?.totalXP ?? 0
        } catch {
            Self.logger.error("Failed to fetch UserProfile for XP: \(error.localizedDescription)")
            return 0
        }
    }

    /// Fetch the stored rang integer from UserProfile.
    ///
    /// Returns 1 (Neel) if no profile exists.
    private func fetchStoredRang() -> Int {
        let descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\UserProfile.createdAt)]
        )
        do {
            return try modelContext.fetch(descriptor).first?.currentRang ?? 1
        } catch {
            Self.logger.error("Failed to fetch UserProfile for rang: \(error.localizedDescription)")
            return 1
        }
    }

    /// Update the stored rang on UserProfile.
    ///
    /// Applies max-wins: only sets if newRang is higher than current.
    /// Calls explicit save for this critical write.
    ///
    /// - Parameter newRang: The new rang integer value.
    private func updateStoredRang(_ newRang: Int) {
        let descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\UserProfile.createdAt)]
        )
        do {
            guard let profile = try modelContext.fetch(descriptor).first else { return }
            profile.currentRang = max(profile.currentRang, newRang)
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to update rang: \(error.localizedDescription)")
        }
    }
}
