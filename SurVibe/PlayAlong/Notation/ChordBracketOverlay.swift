import SwiftUI

/// Shared overlay: dashed rounded rectangle + optional "CHORD" label.
///
/// Used by every notation renderer (`BarsOnStaffView`,
/// `SargamDualRowView`, `SplitLaneView`) to frame simultaneous notes
/// as a chord group. Pop Era sets `preferHeart = true` to prefix the
/// label with a ♡.
///
/// Per latency contract: colors arrive as `let` parameters.
struct ChordBracketOverlay: View {
    let label: String
    let bracketColor: Color
    let preferHeart: Bool
    let showLabel: Bool
    let cornerRadius: CGFloat

    init(
        label: String = "CHORD",
        bracketColor: Color = Color(red: 0.61, green: 0.15, blue: 0.69),
        preferHeart: Bool = false,
        showLabel: Bool = true,
        cornerRadius: CGFloat = 6
    ) {
        self.label = label
        self.bracketColor = bracketColor
        self.preferHeart = preferHeart
        self.showLabel = showLabel
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        bracketColor,
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                    )
                if showLabel {
                    Text(displayLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(bracketColor)
                        .padding(.horizontal, 6)
                        .background(Color.clear)
                        .offset(y: -8)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement()
        .accessibilityLabel("Chord: \(label)")
    }

    private var displayLabel: String {
        preferHeart ? "♡ \(label)" : label
    }
}

#Preview("Default") {
    ChordBracketOverlay(label: "D CHORD")
        .frame(width: 120, height: 60)
        .padding()
        .background(Color.white)
}

#Preview("Pop Era with heart") {
    ChordBracketOverlay(
        label: "D CHORD",
        bracketColor: Color(red: 0.91, green: 0.47, blue: 0.98),
        preferHeart: true
    )
    .frame(width: 120, height: 60)
    .padding()
    .background(Color.white)
}
