import SVCore
import SwiftUI

/// A row-style card displaying a single lesson in the library list.
///
/// Shows the lesson title, difficulty badge, step count, estimated duration,
/// a brief description, and a completion state indicator (checkmark, progress
/// ring, lock icon, or empty circle).
struct LessonCardView: View {
    // MARK: - Properties

    /// The lesson paired with its progress state.
    let item: LessonWithProgress

    @Environment(AppThemeManager.self) private var themeManager

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Left: difficulty color bar
            RoundedRectangle(cornerRadius: 4)
                .fill(difficultyColor)
                .frame(width: 4)
                .accessibilityHidden(true)

            // Center: lesson info
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.lesson.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundStyle(isLocked ? .secondary : .primary)

                HStack(spacing: 8) {
                    DifficultyBadge(difficulty: item.lesson.difficulty)

                    if let stepCount {
                        Label("\(stepCount) steps", systemImage: "list.bullet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let duration = estimatedDuration {
                        Label(duration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !item.lesson.lessonDescription.isEmpty {
                    Text(verbatim: item.lesson.lessonDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Right: completion indicator
            completionIndicator
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.resolved.cardBackgroundColor)
        )
        .opacity(isLocked ? 0.6 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
    }

    // MARK: - Subviews

    /// Displays the appropriate indicator based on completion state.
    @ViewBuilder
    private var completionIndicator: some View {
        switch item.completionState {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(themeManager.resolved.successColor)
                .accessibilityLabel(Text("Completed"))

        case .inProgress(let percent):
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: percent)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 24, height: 24)
            .accessibilityLabel(Text("In progress, \(Int(percent * 100)) percent"))

        case .locked:
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Locked"))

        case .notStarted:
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Not started"))
        }
    }

    // MARK: - Computed Properties

    /// Whether the lesson is locked.
    private var isLocked: Bool {
        item.completionState == .locked
    }

    /// Number of steps in the lesson, if available.
    private var stepCount: Int? {
        item.lesson.decodedSteps?.count
    }

    /// Human-readable estimated duration from step durations.
    private var estimatedDuration: String? {
        guard let steps = item.lesson.decodedSteps else { return nil }
        let totalSeconds = steps.compactMap(\.durationSeconds).reduce(0, +)
        guard totalSeconds > 0 else { return nil }
        let minutes = max(1, totalSeconds / 60)
        return "\(minutes) min"
    }

    /// Difficulty color routed through SVCore's RangLevel.bodyTextColor —
    /// WCAG-safe variants (Peela/Sona use Dark forms for body-text contrast).
    private var difficultyColor: Color {
        RangLevel(rawValue: item.lesson.difficulty)?.bodyTextColor ?? .gray
    }

    /// Accessibility label combining all relevant information.
    private var accessibilityLabelText: Text {
        var parts = [item.lesson.title]
        parts.append("Difficulty: \(difficultyLabel)")

        if let count = stepCount {
            parts.append("\(count) steps")
        }

        switch item.completionState {
        case .completed:
            parts.append("Completed")
        case .inProgress(let percent):
            parts.append("\(Int(percent * 100)) percent complete")
        case .locked:
            parts.append("Locked")
        case .notStarted:
            parts.append("Not started")
        }

        return Text(parts.joined(separator: ", "))
    }

    /// Accessibility hint based on completion state.
    private var accessibilityHintText: Text {
        switch item.completionState {
        case .locked:
            Text("Complete prerequisite lessons to unlock.")
        default:
            Text("Double tap to open this lesson.")
        }
    }

    /// Human-readable difficulty label.
    private var difficultyLabel: String {
        switch item.lesson.difficulty {
        case 1: "Beginner"
        case 2: "Easy"
        case 3: "Medium"
        case 4: "Hard"
        case 5: "Expert"
        default: "Level \(item.lesson.difficulty)"
        }
    }
}
