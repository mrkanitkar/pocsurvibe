import SVCore
import SwiftUI

/// A card displaying a curriculum summary with progress tracking.
///
/// Shows:
/// - Curriculum title
/// - Difficulty range badge (e.g., "Beginner" or "Beginner -> Intermediate")
/// - Lesson count and estimated total duration
/// - Progress bar with completed/total count
///
/// Used inside `CurriculumBrowserView` as the primary list item.
struct CurriculumCardView: View {
    // MARK: - Properties

    @Environment(AppThemeManager.self) private var themeManager

    /// The curriculum to display.
    let curriculum: Curriculum

    /// Ordered lessons in this curriculum.
    let lessons: [Lesson]

    /// Completion progress (0.0 to 1.0).
    let progress: Double

    /// Number of completed lessons.
    let completedCount: Int

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(verbatim: curriculum.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Metadata row
            HStack(spacing: 8) {
                difficultyRangeBadge

                Text(verbatim: "\u{00B7}")
                    .foregroundStyle(.secondary)

                Text("\(lessons.count) lessons")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let duration = estimatedDuration {
                    Text(verbatim: "\u{00B7}")
                        .foregroundStyle(.secondary)
                    Text(verbatim: duration)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Description
            if !curriculum.curriculumDescription.isEmpty {
                Text(verbatim: curriculum.curriculumDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .tint(progressColor)
                    .accessibilityHidden(true)

                Text("\(completedCount)/\(lessons.count) complete")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.resolved.cardBackgroundColor)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(
                "\(curriculum.title), \(completedCount) of \(lessons.count) lessons complete"
            )
        )
    }

    // MARK: - Subviews

    /// Badge showing the curriculum's difficulty range.
    private var difficultyRangeBadge: some View {
        let minLabel = difficultyLabel(curriculum.minDifficulty)
        let maxLabel = difficultyLabel(curriculum.maxDifficulty)
        let text = curriculum.minDifficulty == curriculum.maxDifficulty
            ? minLabel
            : "\(minLabel) \u{2192} \(maxLabel)"

        return Text(verbatim: text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(RangLevel(rawValue: curriculum.minDifficulty)?.bodyTextColor ?? .gray)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        (RangLevel(rawValue: curriculum.minDifficulty)?.bodyTextColor ?? .gray).opacity(0.15)
                    )
            )
    }

    // MARK: - Helpers

    /// Calculates estimated total duration from all lesson steps.
    private var estimatedDuration: String? {
        let totalSeconds = lessons.compactMap { lesson -> Int? in
            lesson.decodedSteps?.compactMap(\.durationSeconds).reduce(0, +)
        }.reduce(0, +)
        guard totalSeconds > 0 else { return nil }
        let minutes = totalSeconds / 60
        return minutes > 0 ? "~\(minutes) min" : "~\(totalSeconds)s"
    }

    /// Color for the progress bar based on completion state.
    private var progressColor: Color {
        if progress >= 1.0 { return .green }
        if progress > 0 { return .accentColor }
        return .secondary
    }

    /// Human-readable label for a difficulty level.
    ///
    /// - Parameter difficulty: Integer difficulty (1-5).
    /// - Returns: A string label such as "Beginner" or "Expert".
    private func difficultyLabel(_ difficulty: Int) -> String {
        switch difficulty {
        case 1: "Beginner"
        case 2: "Elementary"
        case 3: "Intermediate"
        case 4: "Advanced"
        case 5: "Expert"
        default: "Level \(difficulty)"
        }
    }

}
