import SwiftUI

/// Always-visible, compact pause/play button.
///
/// Never auto-hides — addresses the accessibility concern that users
/// need to locate pause instantly during play. Receives the current
/// playback state and a toggle callback as `let` parameters.
///
/// Per latency contract: does NOT read @Environment(AppThemeManager.self);
/// theme colors arrive as `let` parameters.
struct PersistentPauseDot: View {
    let isPlaying: Bool
    let backgroundColor: Color
    let foregroundColor: Color
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(foregroundColor)
                .frame(width: 28, height: 28)
                .background(backgroundColor, in: Circle())
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
        }
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityHint("Toggle playback")
    }
}

#Preview("Playing") {
    PersistentPauseDot(
        isPlaying: true,
        backgroundColor: .black.opacity(0.55),
        foregroundColor: .white,
        onToggle: {}
    )
    .padding()
}
