import SVCore
import SwiftUI

/// Full gallery of all achievements, showing earned and locked states.
///
/// Earned achievements appear with color and the earned date.
/// Locked achievements appear grayed out with a "???" description.
/// Navigated to from ProfileTab's "See All" button.
struct AchievementGalleryView: View {
    // MARK: - Properties

    /// The achievement manager providing earned state.
    let achievementManager: AchievementManager

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 16)],
                spacing: 16
            ) {
                ForEach(AchievementDefinitions.all, id: \.id) { definition in
                    achievementCard(definition)
                }
            }
            .padding()
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Subviews

    /// A single achievement card showing earned or locked state.
    ///
    /// - Parameter definition: The achievement definition to render.
    /// - Returns: A styled card view.
    private func achievementCard(
        _ definition: AchievementDefinitions.Definition
    ) -> some View {
        let isEarned = achievementManager.isEarned(definition.id)
        let earned = isEarned
            ? achievementManager.earnedAchievements.first(where: {
                $0.achievementType == definition.id
            })
            : nil

        return cardContent(definition: definition, isEarned: isEarned, earned: earned)
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemBackground))
                    .opacity(isEarned ? 1.0 : 0.6)
            )
            .animation(
                reduceMotion ? .none : .easeInOut(duration: 0.2),
                value: isEarned
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(
                    isEarned
                        ? "\(definition.title): \(definition.description). Earned."
                        : "\(definition.title): Locked"
                )
            )
    }

    /// The inner content of an achievement card (icon, title, description, metadata).
    ///
    /// - Parameters:
    ///   - definition: The achievement definition to display.
    ///   - isEarned: Whether the achievement has been earned.
    ///   - earned: The earned `Achievement` record, if available.
    /// - Returns: A `VStack` with the card's text and icon content.
    private func cardContent(
        definition: AchievementDefinitions.Definition,
        isEarned: Bool,
        earned: Achievement?
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: isEarned ? "star.circle.fill" : "lock.circle")
                .font(.system(size: 36))
                .foregroundStyle(isEarned ? .yellow : .gray)
                .accessibilityHidden(true)

            Text(verbatim: definition.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(isEarned ? .primary : .secondary)
                .multilineTextAlignment(.center)

            Text(isEarned ? definition.description : "???")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let earned {
                Text(verbatim: formatDate(earned.earnedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if definition.xpBonus > 0 {
                Text(verbatim: "+\(definition.xpBonus) XP")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(isEarned ? .green : .gray)
            }
        }
    }

    // MARK: - Private Methods

    /// Formats a date for display in the achievement card.
    ///
    /// - Parameter date: The date to format.
    /// - Returns: A medium-style date string.
    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
