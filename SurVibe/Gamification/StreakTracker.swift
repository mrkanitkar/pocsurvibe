import Foundation
import os.log
import SVCore
import SVLearning
import SwiftData

/// Tracks practice streak by reading RiyazEntry dates from SwiftData.
///
/// Fetches all `RiyazEntry` records, groups them by calendar day, and walks
/// backward from the most recent day to compute the current consecutive-day
/// streak. Uses `RiyazStreak` from SVLearning for the underlying day-logic.
///
/// Usage:
/// ```swift
/// let tracker = StreakTracker(modelContext: context)
/// tracker.recompute()
/// print(tracker.currentStreak) // e.g. 5
/// ```
@Observable @MainActor
final class StreakTracker {
    // MARK: - Properties

    /// The SwiftData model context used to fetch RiyazEntry records.
    private let modelContext: ModelContext

    /// Logger for streak computation diagnostics.
    private static let logger = Logger.survibe(category: "StreakTracker")

    /// Current consecutive-day practice streak.
    private(set) var currentStreak: Int = 0

    /// Longest streak ever computed from stored entries.
    private(set) var longestStreak: Int = 0

    /// Date of the most recent practice entry, or nil if no entries exist.
    private(set) var lastPracticeDate: Date?

    /// Whether the user has a practice entry recorded for today.
    ///
    /// Returns `true` if `lastPracticeDate` falls within the current calendar day,
    /// `false` otherwise (including when no entries exist).
    var practicedToday: Bool {
        guard let last = lastPracticeDate else { return false }
        return Calendar.current.isDateInToday(last)
    }

    // MARK: - Initialization

    /// Creates a streak tracker backed by the given model context.
    ///
    /// - Parameter modelContext: The SwiftData context to query for RiyazEntry records.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    /// Recompute the streak from all stored RiyazEntry dates.
    ///
    /// Fetches every `RiyazEntry` sorted by date descending, extracts unique
    /// calendar days, then walks backward from the most recent day counting
    /// consecutive days. Sets `currentStreak`, `longestStreak`, and
    /// `lastPracticeDate` from the result.
    ///
    /// When `profile` is supplied, also:
    /// - Burns 1 freeze token to preserve a streak at risk of a 1-day gap.
    /// - Grants 2 weekly freeze tokens if the user practiced this ISO week.
    ///
    /// If the fetch fails, all streak values are reset to zero and the error
    /// is logged.
    ///
    /// - Parameter profile: The user's `UserProfile` for freeze-token management.
    ///   Pass `nil` to skip freeze logic (e.g., tests that don't need it).
    func recompute(profile: UserProfile? = nil) {
        let calendar = Calendar.current

        do {
            var descriptor = FetchDescriptor<RiyazEntry>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.propertiesToFetch = [\.date]
            let entries = try modelContext.fetch(descriptor)

            guard let mostRecentDate = entries.first?.date else {
                // No entries at all
                currentStreak = 0
                longestStreak = 0
                lastPracticeDate = nil
                Self.logger.debug("Recompute: no entries found")
                return
            }

            // Deduplicate to unique calendar days, already sorted descending
            var uniqueDays: [Date] = []
            for entry in entries {
                let entryDate = entry.date
                if let lastUnique = uniqueDays.last {
                    if !calendar.isDate(entryDate, inSameDayAs: lastUnique) {
                        uniqueDays.append(entryDate)
                    }
                } else {
                    uniqueDays.append(entryDate)
                }
            }

            let (streak, longest) = computeStreaks(
                uniqueDays: uniqueDays, calendar: calendar
            )

            currentStreak = streak
            longestStreak = longest
            lastPracticeDate = mostRecentDate

            Self.logger.debug(
                "Recompute: current=\(streak), longest=\(longest), uniqueDays=\(uniqueDays.count)"
            )
        } catch {
            Self.logger.error(
                "Failed to fetch RiyazEntry for streak: \(error.localizedDescription, privacy: .public)"
            )
            currentStreak = 0
            longestStreak = 0
            lastPracticeDate = nil
        }

        if let profile {
            burnFreezeIfStreakAtRisk(profile: profile)
            grantWeeklyFreezeTokensIfEligible(profile: profile)
        }
    }

    /// Grant freeze tokens if the user practiced this week and hasn't been granted yet.
    ///
    /// "Week" = ISO 8601 week (Monday start). Grants 2 tokens per qualifying week,
    /// capped at `maxTokens` (4 by default). Persists `lastFreezeGrantWeekISO` to
    /// `UserProfile` so re-running on the same week is idempotent.
    ///
    /// Call this from `recompute(profile:)` after streak math has run.
    ///
    /// - Parameters:
    ///   - profile: The user's profile where token counts are stored.
    ///   - maxTokens: Maximum tokens the user can hold. Default 4 (2 weeks' worth).
    /// - Returns: Number of tokens actually granted (0 if ineligible or cap reached).
    @discardableResult
    func grantWeeklyFreezeTokensIfEligible(profile: UserProfile, maxTokens: Int = 4) -> Int {
        let now = Date()
        var calendar = Calendar(identifier: .iso8601)
        calendar.minimumDaysInFirstWeek = 4
        let week = calendar.component(.weekOfYear, from: now)
        let year = calendar.component(.yearForWeekOfYear, from: now)
        let currentWeekISO = String(format: "%04d-W%02d", year, week)

        guard profile.lastFreezeGrantWeekISO != currentWeekISO else {
            return 0 // already granted this week
        }

        // Only grant if user practiced today (ensures grant fires alongside a real session,
        // not on a stale yesterday entry — which is the streak-at-risk / burn scenario).
        guard let lastDate = lastPracticeDate,
              Calendar.current.isDateInToday(lastDate),
              calendar.component(.weekOfYear, from: lastDate) == week,
              calendar.component(.yearForWeekOfYear, from: lastDate) == year else {
            return 0
        }

        let granted = min(2, maxTokens - profile.streakFreezeTokens)
        if granted > 0 {
            profile.streakFreezeTokens += granted
            profile.lastFreezeGrantWeekISO = currentWeekISO
            do {
                try modelContext.save()
            } catch {
                Self.logger.error(
                    "Failed to save freeze grant: \(error.localizedDescription, privacy: .public)"
                )
            }
            Self.logger.info(
                "Granted \(granted) freeze tokens for week \(currentWeekISO, privacy: .public)"
            )
        } else {
            // Cap reached — still mark this week to avoid re-checking
            profile.lastFreezeGrantWeekISO = currentWeekISO
            do {
                try modelContext.save()
            } catch {
                Self.logger.error(
                    "Failed to save freeze grant week: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return granted
    }

    /// Burn 1 freeze token to preserve a streak at risk of breaking.
    ///
    /// Detection: if `lastPracticeDate` was exactly yesterday (no entry today yet),
    /// the streak would break when tomorrow's recompute runs. Burns 1 token to
    /// preserve it. Only acts on a 1-day gap; longer gaps still break the streak.
    ///
    /// Returns `true` if a token was burned.
    ///
    /// - Parameter profile: The user's profile where token counts are stored.
    /// - Returns: `true` if a freeze token was consumed, `false` otherwise.
    @discardableResult
    func burnFreezeIfStreakAtRisk(profile: UserProfile) -> Bool {
        guard profile.streakFreezeTokens > 0 else { return false }
        let calendar = Calendar.current
        let now = Date()
        guard let last = lastPracticeDate else { return false }
        // Must NOT have practiced today
        guard !calendar.isDateInToday(last) else { return false }
        // Must have practiced exactly yesterday
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
              calendar.isDate(last, inSameDayAs: yesterday) else {
            return false
        }
        // Yesterday practiced, today didn't yet — preserve by burning a token.
        profile.streakFreezeTokens -= 1
        do {
            try modelContext.save()
        } catch {
            Self.logger.error(
                "Failed to save freeze burn: \(error.localizedDescription, privacy: .public)"
            )
        }
        Self.logger.info(
            "Burned 1 freeze token to preserve streak; \(profile.streakFreezeTokens) remaining"
        )
        return true
    }

    // MARK: - Private Methods

    /// Compute current and longest consecutive-day streaks from unique days.
    ///
    /// Walks the sorted (descending) unique days array twice: once from
    /// the front to find the current streak, once across all days to find
    /// the longest historical streak.
    ///
    /// - Parameters:
    ///   - uniqueDays: Calendar days with at least one entry, sorted descending.
    ///   - calendar: Calendar used for day arithmetic.
    /// - Returns: Tuple of (currentStreak, longestStreak).
    private func computeStreaks(
        uniqueDays: [Date], calendar: Calendar
    ) -> (current: Int, longest: Int) {
        guard uniqueDays.count > 1 else { return (1, 1) }

        // Walk backward from most recent, counting consecutive days
        var streak = 1
        for i in 0..<(uniqueDays.count - 1) {
            let currentDay = uniqueDays[i]
            let previousDay = uniqueDays[i + 1]

            guard let expected = calendar.date(byAdding: .day, value: -1, to: currentDay),
                  calendar.isDate(previousDay, inSameDayAs: expected) else {
                break
            }
            streak += 1
        }

        // Walk all unique days to find the longest run
        var longest = 1
        var run = 1
        for i in 0..<(uniqueDays.count - 1) {
            let currentDay = uniqueDays[i]
            let previousDay = uniqueDays[i + 1]

            if let expected = calendar.date(byAdding: .day, value: -1, to: currentDay),
               calendar.isDate(previousDay, inSameDayAs: expected) {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }

        return (streak, longest)
    }
}
