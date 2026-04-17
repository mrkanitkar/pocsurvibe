import SwiftUI

/// One-time overlay explaining how to reveal the hidden toolbar.
///
/// Appears on the first PlayAlong launch. Auto-dismisses after ~5 s
/// and sets `AppStorage["playAlongCoachMarkShown"]` so subsequent
/// launches skip it. If `AppStorage` is already `true`, the view
/// returns `EmptyView()`.
///
/// Uses system `.ultraThinMaterial` background so it works in light
/// and dark mode without theme coupling.
struct FirstTimeCoachMark: View {
    @AppStorage("playAlongCoachMarkShown") private var shown: Bool = false
    @State private var visible = false

    var body: some View {
        if !shown {
            VStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.title3)
                Text("Tap anywhere to show controls")
                    .font(.caption.weight(.semibold))
                Text("Swipe down from top · Tap screen during play")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.4)) { visible = true }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation(.easeInOut(duration: 0.4)) { visible = false }
                    try? await Task.sleep(for: .seconds(1))
                    shown = true
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("First-time tip: tap anywhere to show controls. Swipe down from top. Tap screen during play.")
        }
    }
}

#Preview("Visible") {
    // Clear the AppStorage flag before the preview so it renders
    // (or set @AppStorage binding to false before previewing).
    FirstTimeCoachMark()
        .padding()
        .background(Color.black)
}
