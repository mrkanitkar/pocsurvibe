import SVAudio
import SVCore
import SwiftUI

/// Compact status chip showing the active input source (MIDI device
/// name or mic) for the playalong session.
///
/// Renders an appropriate SF Symbol (pianokeys / mic.fill) with the
/// source label in a capsule-shaped background. Accessibility labels
/// describe the source for VoiceOver.
///
/// Updated reactively when `InputRouter` transitions between sources
/// (e.g., MIDI device plug/unplug).
struct SourceChip: View {
    let source: InputSource

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: sourceIcon)
                .font(.caption)
                .accessibilityHidden(true)
            Text(sourceLabel)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.regularMaterial))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityDescription))
    }

    private var sourceIcon: String {
        switch source {
        case .none: "questionmark.circle"
        case .midi: "pianokeys"
        case .mic: "mic.fill"
        }
    }

    private var sourceLabel: String {
        switch source {
        case .none: String(localized: "No input")
        case .midi(let name): name
        case .mic: String(localized: "Microphone")
        }
    }

    private var accessibilityDescription: String {
        switch source {
        case .none: String(localized: "No input source active")
        case .midi(let name): String(localized: "Receiving MIDI from \(name)")
        case .mic: String(localized: "Listening through iPad microphone")
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        SourceChip(source: .none)
        SourceChip(source: .mic)
        SourceChip(source: .midi(deviceName: "Yamaha PSR-400"))
    }
    .padding()
}
