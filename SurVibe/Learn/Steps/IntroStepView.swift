import SVCore
import SwiftUI

/// Displays introduction content for a lesson step.
///
/// Intro steps present lesson overview text in a readable format.
/// They are always unlocked — no completion action required.
/// This is the simplest step type: it shows instructional content
/// and an optional duration indicator with no gating logic.
struct IntroStepView: View {
    // MARK: - Properties

    /// The lesson step to display.
    let step: LessonStep

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Step type badge
            stepBadge

            // Content text
            Text(verbatim: step.content)
                .font(.body)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Duration indicator
            if let seconds = step.durationSeconds {
                durationIndicator(seconds)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Subviews

    /// Badge identifying this step as an introduction.
    private var stepBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.book.closed")
                .accessibilityHidden(true)
            Text("Introduction")
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .foregroundStyle(StepTypeColorSystem.color(for: .intro))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(StepTypeColorSystem.color(for: .intro).opacity(0.15)))
        .accessibilityLabel(Text("Step type: Introduction"))
    }

    /// Shows the estimated duration for this step.
    ///
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A label with a timer icon and formatted duration.
    private func durationIndicator(_ seconds: Int) -> some View {
        Label(formatDuration(seconds), systemImage: "timer")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Private Methods

    /// Formats seconds into a human-readable duration string.
    ///
    /// - Parameter seconds: Duration in seconds.
    /// - Returns: A formatted string like "30s", "2 min", or "1m 30s".
    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remaining = seconds % 60
        return remaining == 0 ? "\(minutes) min" : "\(minutes)m \(remaining)s"
    }
}
