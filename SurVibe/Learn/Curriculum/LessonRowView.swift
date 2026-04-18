import SVCore
import SwiftUI

/// A row displaying a lesson within a curriculum list.
///
/// Shows:
/// - Status indicator: green checkmark (done), numbered circle (available), lock (locked)
/// - Lesson title
/// - Difficulty dots (1-5)
/// - Step count and estimated duration
/// - Premium indicator for non-free lessons
struct LessonRowView: View {
    // MARK: - Properties

    @Environment(AppThemeManager.self) private var themeManager

    /// The lesson to display.
    let lesson: Lesson

    /// 1-based index in the curriculum.
    let index: Int

    /// Whether the lesson is completed.
    let isCompleted: Bool

    /// Whether the lesson is locked (prerequisites not met).
    let isLocked: Bool

    /// Number of steps in the lesson.
    let stepCount: Int?

    /// Estimated duration string.
    let estimatedDuration: String?

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIndicator
                .frame(width: 36, height: 36)

            // Lesson info
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: lesson.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(isLocked ? .secondary : .primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    difficultyDots(lesson.difficulty)

                    if let count = stepCount {
                        Text("\(count) steps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let duration = estimatedDuration {
                        Text(verbatim: "\u{00B7}")
                            .foregroundStyle(.secondary)
                        Text(verbatim: duration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !lesson.isFree {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(themeManager.resolved.warningColor)
                            .accessibilityLabel(Text("Premium lesson"))
                    }
                }
            }

            Spacer()

            if !isLocked, !isCompleted {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .opacity(isLocked ? 0.6 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(
            isLocked
                ? Text("This lesson is locked. Tap to see prerequisites.")
                : isCompleted
                    ? Text("This lesson is completed. Tap to review.")
                    : Text("Double tap to view lesson details.")
        )
    }

    // MARK: - Subviews

    /// Status indicator showing completion state, index, or lock.
    @ViewBuilder
    private var statusIndicator: some View {
        if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(themeManager.resolved.successColor)
                .accessibilityHidden(true)
        } else if isLocked {
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } else {
            Text("\(index)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(themeManager.resolved.badgeTextColor)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
        }
    }

    /// Difficulty dots showing level 1-5 with filled/empty circles.
    ///
    /// - Parameter difficulty: The lesson difficulty (1-5).
    /// - Returns: A row of 5 small circles with filled dots up to the difficulty level.
    private func difficultyDots(_ difficulty: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { level in
                Circle()
                    .fill(
                        level <= difficulty
                            ? (RangLevel(rawValue: difficulty)?.bodyTextColor ?? .gray)
                            : themeManager.resolved.dividerColor
                    )
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityLabel(Text("Difficulty \(difficulty) of 5"))
    }

    // MARK: - Helpers

    /// Combined accessibility label describing the lesson row.
    private var accessibilityText: Text {
        var parts: [String] = []
        if isCompleted { parts.append("Completed") }
        if isLocked { parts.append("Locked") }
        parts.append("Lesson \(index): \(lesson.title)")
        parts.append("Difficulty \(lesson.difficulty)")
        if let count = stepCount { parts.append("\(count) steps") }
        if let dur = estimatedDuration { parts.append(dur) }
        return Text(parts.joined(separator: ", "))
    }
}
