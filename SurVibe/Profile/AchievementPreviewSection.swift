import SwiftData
import SwiftUI

/// Preview of the user's most recent achievements with a "See All" link.
///
/// Shows up to 3 earned achievements as small horizontal cards. If no
/// achievements are earned yet, displays an encouraging placeholder message.
/// The "See All" NavigationLink routes to the full `AchievementGalleryView`.
struct AchievementPreviewSection: View {
    // MARK: - Properties

    /// The most recent earned achievements (max 3, pre-sliced by caller).
    let recentAchievements: [Achievement]

    /// The achievement manager passed through to the gallery view.
    let achievementManager: AchievementManager

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recentAchievements.isEmpty {
                emptyState
            } else {
                achievementRow
            }

            seeAllLink
        }
    }

    // MARK: - Subviews

    /// Horizontal row of small achievement cards.
    private var achievementRow: some View {
        HStack(spacing: 12) {
            ForEach(recentAchievements, id: \.id) { achievement in
                achievementMiniCard(achievement)
            }
        }
    }

    /// A compact achievement card showing icon, title, and earned date.
    ///
    /// - Parameter achievement: The earned achievement to display.
    private func achievementMiniCard(_ achievement: Achievement) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "star.circle.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            Text(verbatim: achievement.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(verbatim: achievement.earnedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("\(achievement.title), earned \(achievement.earnedAt.formatted(date: .abbreviated, time: .omitted))")
        )
    }

    /// Placeholder shown when no achievements have been earned yet.
    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Complete lessons and practice to earn achievements")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// NavigationLink to the full achievement gallery.
    private var seeAllLink: some View {
        NavigationLink(value: "achievements") {
            HStack {
                Text("See All Achievements")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(Text("See All Achievements"))
        .accessibilityHint(Text("Double tap to view all achievements"))
    }
}

// Preview requires full ModelContainer setup — use Xcode Previews via ProfileTab instead.
