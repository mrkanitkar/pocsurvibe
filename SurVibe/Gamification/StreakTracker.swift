import Foundation
import os.log
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
    private static let logger = Logger(subsystem: "com.survibe", category: "StreakTracker")

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
    /// If the fetch fails, all streak values are reset to zero and the error
    /// is logged.
    func recompute() {
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

            // Walk backward from most recent, counting consecutive days
            var streak = 1
            for i in 0..<(uniqueDays.count - 1) {
                let currentDay = uniqueDays[i]
                let previousDay = uniqueDays[i + 1]

                // Check if previousDay is exactly one calendar day before currentDay
                guard let expectedPrevious = calendar.date(byAdding: .day, value: -1, to: currentDay),
                      calendar.isDate(previousDay, inSameDayAs: expectedPrevious) else {
                    break
                }
                streak += 1
            }

            // For longestStreak, walk all unique days to find the longest run
            var longest = 1
            var run = 1
            for i in 0..<(uniqueDays.count - 1) {
                let currentDay = uniqueDays[i]
                let previousDay = uniqueDays[i + 1]

                if let expectedPrevious = calendar.date(byAdding: .day, value: -1, to: currentDay),
                   calendar.isDate(previousDay, inSameDayAs: expectedPrevious) {
                    run += 1
                    longest = max(longest, run)
                } else {
                    run = 1
                }
            }

            currentStreak = streak
            longestStreak = longest
            lastPracticeDate = mostRecentDate

            Self.logger.debug(
                "Recompute: current=\(streak), longest=\(longest), uniqueDays=\(uniqueDays.count)"
            )
        } catch {
            Self.logger.error("Failed to fetch RiyazEntry for streak: \(error.localizedDescription)")
            currentStreak = 0
            longestStreak = 0
            lastPracticeDate = nil
        }
    }
}
