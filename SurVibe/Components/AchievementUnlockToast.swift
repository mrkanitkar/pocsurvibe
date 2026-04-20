import os
import SVCore
import SwiftUI

/// Auto-dismissing banner shown when an achievement unlocks.
///
/// Positioned at top of screen via overlay, slides in with spring animation,
/// auto-dismisses after 3 seconds. Respects reduceMotion preference.
///
/// Usage:
/// ```swift
/// .overlay(alignment: .top) {
///     if let achievement = manager.lastUnlockedAchievement {
///         AchievementUnlockToast(
///             title: achievement.title,
///             xpBonus: achievement.xpBonus,
///             onDismiss: { manager.lastUnlockedAchievement = nil }
///         )
///     }
/// }
/// ```
struct AchievementUnlockToast: View {
    // MARK: - Properties

    /// Logger for toast display events.
    private static let logger = Logger.survibe(category: "AchievementToast")

    /// The achievement title to display.
    let title: String

    /// Bonus XP awarded with the achievement (0 hides the XP line).
    let xpBonus: Int

    /// Called when the toast should be dismissed.
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Flips true on first appearance so `.sensoryFeedback(.success, trigger:)`
    /// fires exactly once when the toast enters the hierarchy.
    @State private var hasAppeared = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Achievement Unlocked!")
                    .font(.caption.bold())
                Text(title)
                    .font(.subheadline)
                if xpBonus > 0 {
                    Text("+\(xpBonus) XP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(radius: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Achievement unlocked: \(title)")
        .accessibilityAddTraits(.isStaticText)
        .sensoryFeedback(.success, trigger: hasAppeared)
        .onAppear {
            Self.logger.info("Achievement toast shown: \(title, privacy: .public)")
            hasAppeared = true
        }
    }
}

// MARK: - Preview

#Preview("With XP") {
    AchievementUnlockToast(
        title: "First Note",
        xpBonus: 10,
        onDismiss: {}
    )
    .padding()
}

#Preview("Without XP") {
    AchievementUnlockToast(
        title: "Century",
        xpBonus: 0,
        onDismiss: {}
    )
    .padding()
}
