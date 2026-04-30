import SwiftUI

// MARK: - D4 Split Score Section

extension PlayAlongResultsOverlay {

    /// Two-column row showing "Notes correct" and "Timing" as the primary
    /// result headline numbers, per spec §5.1 results-overlay design.
    ///
    /// Both metrics are rendered in `.title2.bold` so they immediately draw
    /// the user's eye. The composite `NoteScore` appears smaller in the
    /// secondary `statsSection` below.
    ///
    /// Accessibility: each column is combined into a single accessibility
    /// element labelled with both the numeric value and its meaning.
    var splitScoreSection: some View {
        HStack(spacing: 32) {
            metric(
                label: "Notes correct",
                value: CompactScoringHUD.formatAccuracy(notesCorrectPercent)
            )
            Divider()
                .frame(height: 40)
                .accessibilityHidden(true)
            metric(
                label: "Timing",
                value: CompactScoringHUD.formatAccuracy(timingAccuracyPercent)
            )
        }
        .padding(.vertical, 4)
    }

    /// A single labelled metric card used in `splitScoreSection`.
    ///
    /// Wraps a large bold value above a secondary caption label.
    /// The combined accessibility element announces both meaning and value.
    ///
    /// - Parameters:
    ///   - label: Short descriptive label shown beneath the value (e.g. "Notes correct").
    ///   - value: Pre-formatted percentage string (e.g. "80%").
    private func metric(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
