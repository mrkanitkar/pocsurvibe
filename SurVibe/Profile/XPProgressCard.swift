import SVCore
import SwiftUI

/// Card displaying XP progress toward the next rang level.
///
/// Shows the user's total XP prominently, a progress bar indicating
/// how close they are to the next rang, XP remaining to level up,
/// and XP earned today. Uses Liquid Glass (`.glassEffect`) per iOS 26 guidelines.
struct XPProgressCard: View {
    // MARK: - Properties

    /// Lifetime accumulated XP.
    let totalXP: Int

    /// XP earned since midnight today.
    let xpToday: Int

    /// Fraction of progress toward the next rang (0.0--1.0).
    let progressToNextRang: Double

    /// XP remaining to reach the next rang level.
    let xpToNextRang: Int

    /// The user's current rang level (used for color theming).
    let currentRang: RangLevel

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            progressBar
            detailRow
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .glassEffect(.regular)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(totalXP) total XP. \(xpToNextRang) XP to next rang. \(xpToday) XP earned today.")
        )
    }

    // MARK: - Subviews

    /// Title and large XP number.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total XP")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(verbatim: "\(totalXP)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(currentRang.bodyTextColor)
                .contentTransition(.numericText())
                .animation(
                    reduceMotion ? .none : .easeInOut(duration: 0.3),
                    value: totalXP
                )
        }
    }

    /// Horizontal progress bar toward the next rang.
    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: progressToNextRang)
                .tint(currentRang.color)
                .accessibilityLabel(
                    Text("Progress to next rang: \(Int(progressToNextRang * 100)) percent")
                )

            if xpToNextRang > 0 {
                Text("\(xpToNextRang) XP to next rang")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Maximum rang reached")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Today's XP earned label.
    private var detailRow: some View {
        HStack {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            Text("Today: +\(xpToday) XP")
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    List {
        Section {
            XPProgressCard(
                totalXP: 1250,
                xpToday: 45,
                progressToNextRang: 0.625,
                xpToNextRang: 750,
                currentRang: .hara
            )
        }
    }
}
