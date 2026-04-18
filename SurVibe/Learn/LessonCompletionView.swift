import SwiftData
import SwiftUI

/// Celebration screen shown when a lesson is completed.
///
/// Displays:
/// - Confetti animation (respects reduce motion)
/// - Lesson title and completion heading
/// - Stats: time spent, quiz score (if applicable), step count
/// - Action button to dismiss back to the curriculum browser
///
/// ## Navigation
/// - "Back to Curricula" invokes the `onDismiss` callback to close the lesson player.
///
/// ## Accessibility
/// - Confetti hidden from VoiceOver; static checkmark shown when reduce motion is on.
/// - All stat items combine children for a single VoiceOver announcement.
/// - All interactive elements have `accessibilityLabel` and `accessibilityHint`.
struct LessonCompletionView: View {
    // MARK: - Properties

    /// The completed lesson.
    let lesson: Lesson

    /// The progress record for the completed lesson.
    let progress: LessonProgress

    /// Callback to dismiss the lesson player.
    let onDismiss: () -> Void

    @Environment(AppThemeManager.self) private var themeManager

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var showConfetti = false
    @State private var showContent = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Confetti overlay
            ConfettiView(
                isActive: $showConfetti,
                celebrationColors: themeManager.resolved.celebrationColors,
                successColor: themeManager.resolved.successColor
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Celebration section
                    celebrationSection

                    // Stats section
                    statsSection

                    // Actions section
                    actionsSection
                }
                .padding()
                .opacity(showContent ? 1.0 : 0.0)
            }
        }
        .onAppear {
            showConfetti = true
            if reduceMotion {
                showContent = true
            } else {
                withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                    showContent = true
                }
            }
        }
    }

    // MARK: - Sections

    /// Trophy icon, heading, and lesson title.
    private var celebrationSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            Text("Lesson Complete!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(verbatim: lesson.title)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Lesson complete: \(lesson.title)"))
    }

    /// Time spent, quiz score (if any), and step count displayed as stat cards.
    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                // Time spent
                statItem(
                    value: formattedTime,
                    label: "Time Spent",
                    icon: "clock.fill"
                )

                // Quiz score (if any)
                if progress.bestQuizScore > 0 {
                    statItem(
                        value: "\(Int(progress.bestQuizScore * 100))%",
                        label: "Quiz Score",
                        icon: "star.fill"
                    )
                }

                // Steps completed
                if let steps = lesson.decodedSteps {
                    statItem(
                        value: "\(steps.count)",
                        label: "Steps",
                        icon: "list.number"
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.resolved.cardBackgroundColor)
        )
    }

    /// Dismiss button to return to the curriculum browser.
    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                onDismiss()
            } label: {
                Label("Back to Curricula", systemImage: "books.vertical")
                    .font(.body)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(Text("Back to curricula"))
            .accessibilityHint(Text("Double tap to return to the curriculum browser"))
        }
    }

    // MARK: - Helpers

    /// Renders a single stat item with an icon, value, and label.
    ///
    /// The children are combined into a single accessibility element
    /// that announces the label followed by the value.
    ///
    /// - Parameters:
    ///   - value: The display value string (e.g., "3m 15s").
    ///   - label: The human-readable label (e.g., "Time Spent").
    ///   - icon: SF Symbol name for the icon.
    /// - Returns: A vertically stacked stat card.
    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label): \(value)"))
    }

    /// Formats `totalTimeSpent` into a human-readable duration string.
    ///
    /// Returns seconds for durations under 60s, minutes for exact minutes,
    /// and "Xm Ys" for mixed durations.
    private var formattedTime: String {
        let totalSeconds = Int(progress.totalTimeSpent)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if seconds == 0 {
            return "\(minutes) min"
        }
        return "\(minutes)m \(seconds)s"
    }
}
