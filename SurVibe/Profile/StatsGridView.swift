import SwiftUI

/// 2x2 grid of aggregate practice statistics.
///
/// Displays four key metrics in a compact grid layout:
/// total practice time, songs played, lessons completed, and best streak.
/// Each cell has an SF Symbol icon, the numeric value, and a descriptive label.
struct StatsGridView: View {
    // MARK: - Properties

    /// Cumulative practice time from all RiyazEntry records, in minutes.
    let totalPracticeMinutes: Int

    /// Number of songs the user has played at least once.
    let songsPlayed: Int

    /// Number of lessons the user has completed.
    let lessonsComplete: Int

    /// Longest consecutive-day practice streak ever recorded.
    let bestStreak: Int

    /// Grid layout: 2 flexible columns with consistent spacing.
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    // MARK: - Body

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            statCell(
                icon: "clock.fill",
                value: formattedPracticeTime,
                label: "Practice Time",
                accessibilityValue: "\(totalPracticeMinutes) minutes of practice"
            )

            statCell(
                icon: "music.note",
                value: "\(songsPlayed)",
                label: "Songs Played",
                accessibilityValue: "\(songsPlayed) songs played"
            )

            statCell(
                icon: "checkmark.circle.fill",
                value: "\(lessonsComplete)",
                label: "Lessons Done",
                accessibilityValue: "\(lessonsComplete) lessons completed"
            )

            statCell(
                icon: "flame.fill",
                value: "\(bestStreak)",
                label: "Best Streak",
                accessibilityValue: "\(bestStreak) day best streak"
            )
        }
    }

    // MARK: - Subviews

    /// A single stat cell with icon, value, and label.
    ///
    /// - Parameters:
    ///   - icon: SF Symbol name for the icon.
    ///   - value: The formatted numeric value to display.
    ///   - label: A short label describing the stat.
    ///   - accessibilityValue: VoiceOver-friendly description of the stat.
    private func statCell(
        icon: String,
        value: String,
        label: String,
        accessibilityValue: String
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(verbatim: value)
                .font(.title2)
                .fontWeight(.bold)
                .fontDesign(.rounded)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemBackground))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityValue))
    }

    // MARK: - Private Methods

    /// Formats practice minutes into a human-readable string.
    ///
    /// Shows hours and minutes for values >= 60 min, otherwise just minutes.
    private var formattedPracticeTime: String {
        if totalPracticeMinutes >= 60 {
            let hours = totalPracticeMinutes / 60
            let mins = totalPracticeMinutes % 60
            if mins > 0 {
                return "\(hours)h \(mins)m"
            }
            return "\(hours)h"
        }
        return "\(totalPracticeMinutes)m"
    }
}

#Preview {
    List {
        Section {
            StatsGridView(
                totalPracticeMinutes: 142,
                songsPlayed: 8,
                lessonsComplete: 12,
                bestStreak: 7
            )
        }
    }
}
