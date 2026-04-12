import SVCore
import SwiftUI

/// Circular badge displaying the user's current Rang (level).
///
/// Shows the rang name (Neel/Hara/Peela/Lal/Sona) on a colored circular
/// background with the proficiency label below. Colors follow the CLAUDE.md
/// design system — Peela and Sona use dark variants for body text.
///
/// ## Accessibility
/// - Announces rang name and proficiency as a single label.
/// - Supports Dynamic Type for the proficiency label.
/// - Animation respects `accessibilityReduceMotion`.
struct RangBadgeView: View {
    // MARK: - Properties

    /// The rang level to display.
    let rang: RangLevel

    /// Optional size multiplier for different contexts (default 1.0).
    var scale: Double = 1.0

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4 * scale) {
            circle
            proficiencyLabel
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("Rang level \(rang.displayName), \(rang.proficiencyLabel)")
        )
    }

    // MARK: - Subviews

    /// Circular badge with rang color and level name.
    private var circle: some View {
        ZStack {
            Circle()
                .fill(rang.color.gradient)
                .frame(width: 64 * scale, height: 64 * scale)
                .shadow(color: rang.color.opacity(0.3), radius: 4, y: 2)

            Text(verbatim: rang.displayName)
                .font(.system(size: 16 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .animation(
            reduceMotion ? .none : .easeInOut(duration: 0.3),
            value: rang
        )
    }

    /// Proficiency label below the badge.
    private var proficiencyLabel: some View {
        Text(rang.proficiencyLabel)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(rang.bodyTextColor)
    }
}

#Preview("All Rang Levels") {
    HStack(spacing: 20) {
        ForEach(RangLevel.allCases, id: \.rawValue) { level in
            RangBadgeView(rang: level)
        }
    }
    .padding()
}
