import SwiftUI

/// Compact pill showing the active input source (mic or MIDI device).
///
/// Renders a pulsing green dot + label. Green-dot convention matches
/// Apple's privacy-indicator expectation — users should always know
/// when the mic is listening.
///
/// Per latency contract: theme colors arrive as `let` parameters.
struct MicSourcePill: View {
    nonisolated enum Source: Equatable, Sendable {
        case mic
        case midi(deviceName: String?)
    }

    let source: Source
    let backgroundColor: Color
    let foregroundColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .opacity(reduceMotion ? 1.0 : (pulse ? 1.0 : 0.4))
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(), value: pulse)
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor, in: Capsule())
        .foregroundStyle(foregroundColor)
        .onAppear {
            if !reduceMotion { pulse = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var label: String {
        switch source {
        case .mic: "Mic"
        case .midi(let name): "MIDI · \(name ?? "Connected")"
        }
    }

    private var accessibilityText: String {
        switch source {
        case .mic: "Microphone listening"
        case .midi(let name): "MIDI keyboard \(name ?? "connected")"
        }
    }
}

#Preview("Mic") {
    MicSourcePill(source: .mic, backgroundColor: .black.opacity(0.4), foregroundColor: .white).padding()
}

#Preview("MIDI") {
    MicSourcePill(source: .midi(deviceName: "Yamaha P-225"), backgroundColor: .black.opacity(0.4), foregroundColor: .white).padding()
}
