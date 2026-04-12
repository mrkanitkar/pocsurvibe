import SwiftUI

/// Displays the user's current practice streak and today's practice status.
///
/// Shows a flame icon with the streak count and a badge indicating whether
/// the user has practiced today. The flame icon uses a warm color gradient
/// to reinforce the streak visual metaphor.
struct StreakSectionView: View {
    // MARK: - Properties

    /// Current consecutive-day practice streak.
    let currentStreak: Int

    /// Whether the user has recorded a practice entry today.
    let practicedToday: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            flameIcon
            streakInfo
            Spacer()
            practicedBadge
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                practicedToday
                    ? "\(currentStreak) day streak. Practiced today."
                    : "\(currentStreak) day streak. Not practiced today."
            )
        )
    }

    // MARK: - Subviews

    /// Flame icon with warm gradient.
    private var flameIcon: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 32))
            .foregroundStyle(
                currentStreak > 0
                    ? LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    : LinearGradient(
                        colors: [.gray, .gray],
                        startPoint: .bottom,
                        endPoint: .top
                    )
            )
            .accessibilityHidden(true)
    }

    /// Streak count and label.
    private var streakInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(currentStreak)")
                .font(.title2)
                .fontWeight(.bold)
                .fontDesign(.rounded)

            Text("day streak")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Badge showing whether the user has practiced today.
    private var practicedBadge: some View {
        Group {
            if practicedToday {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            } else {
                Label("Not yet", systemImage: "circle")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    List {
        Section {
            StreakSectionView(currentStreak: 5, practicedToday: true)
        }
        Section {
            StreakSectionView(currentStreak: 0, practicedToday: false)
        }
    }
}
