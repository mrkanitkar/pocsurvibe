import SwiftUI

/// Always-visible, compact pause/play button.
///
/// Never auto-hides — addresses the accessibility concern that users
/// need to locate pause instantly during play. Receives the current
/// playback state, foreground color, and a toggle callback as `let`
/// parameters. The surface uses `.ultraThinMaterial` so the button
/// remains legible when floating over light piano keys, highlighted
/// keys, or dark theme backgrounds alike.
///
/// Per latency contract: does NOT read @Environment(AppThemeManager.self);
/// theme colors arrive as `let` parameters.
struct PersistentPauseDot: View {
    let isPlaying: Bool
    let foregroundColor: Color
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .accessibilityHidden(true)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(foregroundColor)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle().strokeBorder(foregroundColor.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        }
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityHint("Toggle playback")
    }
}

#Preview("Playing") {
    PersistentPauseDot(
        isPlaying: true,
        foregroundColor: .white,
        onToggle: {}
    )
    .padding()
    .background(Color.white)
}
