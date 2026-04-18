import SwiftUI

/// Vertical meter showing how close the detected pitch is to the target note.
///
/// Displays cents deviation as a colored bar, with green at center (0 cents),
/// transitioning through blue and orange to red at the extremes.
///
/// Colors are injected as `let` parameters by the parent view rather than read
/// from `@Environment(AppThemeManager.self)`, preserving the audio latency
/// contract — this view is called at ~20–40 Hz from pitch detection updates.
struct PitchProximityMeter: View {
    /// Cents deviation from the target note (-50 to +50).
    let centsOffset: Double

    /// Maximum cents range to display (default: 50).
    let maxCents: Double

    /// Track background color (gray rail). Passed by parent — never read from
    /// @Environment to preserve audio latency contract (called at ~20-40 Hz
    /// from pitch detection updates).
    let trackColor: Color

    /// Center-line color (perfect-pitch marker). Default theme: success green.
    /// Passed by parent — never read from @Environment.
    let centerLineColor: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        centsOffset: Double,
        maxCents: Double = 50.0,
        trackColor: Color = Color.gray.opacity(0.15),
        centerLineColor: Color = .green
    ) {
        self.centsOffset = centsOffset
        self.maxCents = max(1.0, maxCents)
        self.trackColor = trackColor
        self.centerLineColor = centerLineColor
    }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let centerY = height / 2.0
            let clampedOffset = max(-maxCents, min(maxCents, centsOffset))
            let normalizedOffset = clampedOffset / maxCents
            let indicatorY = centerY - (normalizedOffset * centerY)

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(trackColor)
                    .frame(width: 8)

                // Center line (perfect pitch)
                Rectangle()
                    .fill(centerLineColor)
                    .frame(width: 12, height: 2)
                    .offset(y: 0)

                // Indicator
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 16, height: 16)
                    .offset(y: indicatorY - centerY)
            }
            .frame(width: 16, height: height)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 24, height: 120)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pitch deviation: \(Int(centsOffset)) cents")
        .accessibilityValue(proximityDescription)
    }

    // MARK: - Helpers

    private var indicatorColor: Color {
        let absCents = abs(centsOffset)
        if absCents <= 10 { return .green }
        if absCents <= 25 { return .blue }
        if absCents <= 50 { return .orange }
        return .red
    }

    private var proximityDescription: String {
        let absCents = abs(centsOffset)
        if absCents <= 10 { return "Excellent, very close" }
        if absCents <= 25 { return "Good, slightly off" }
        if absCents <= 50 { return "Fair, needs adjustment" }
        return "Far from target"
    }
}
