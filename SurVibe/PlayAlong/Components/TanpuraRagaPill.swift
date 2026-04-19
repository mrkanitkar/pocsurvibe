import SwiftUI

/// Context-aware pill at top-left of PlayAlong chrome.
///
/// Three modes for the leading label:
/// - `.raga`: Hindustani — shows pulsing red dot + raga name.
/// - `.westernKey`: Western — shows "C major · ♩ = 72".
/// - `.popSong`: Pop Era — shows heart + "Artist · Song".
///
/// The trailing Sa label is shown in ALL modes because the tanpura
/// reference is globally relevant. Tapping the pill fires `onTap` if
/// provided — callers use this to present the tanpura settings sheet.
///
/// Per latency contract: theme colors arrive as `let` parameters.
struct TanpuraRagaPill: View {
    enum Mode {
        case raga(name: String)
        case westernKey(key: String, bpm: Int)
        case popSong(artist: String, song: String)
    }

    let mode: Mode
    /// Pre-formatted Sa label (e.g., "C♯4"). Derived upstream from
    /// `TanpuraController.saGridHz` so the pill stays a pure renderer.
    let saLabel: String
    let backgroundColor: Color
    let foregroundColor: Color
    /// Optional tap handler. When non-nil the pill renders as a Button;
    /// when nil it's a passive label (legacy behavior).
    var onTap: (() -> Void)? = nil

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    private var content: some View {
        HStack(spacing: 5) {
            leadingIcon
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(backgroundColor, in: Capsule())
        .foregroundStyle(foregroundColor)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch mode {
        case .raga:
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
        case .popSong:
            Image(systemName: "heart.fill")
                .font(.caption2)
                .foregroundStyle(.pink)
                .accessibilityHidden(true)
        case .westernKey:
            EmptyView()
        }
    }

    private var label: String {
        switch mode {
        case .raga(let name): "\(name) · Sa = \(saLabel)"
        case .westernKey(let key, let bpm): "\(key) · ♩ = \(bpm) · Sa = \(saLabel)"
        case .popSong(let artist, let song): "\(artist) · \(song) · Sa = \(saLabel)"
        }
    }

    private var accessibilityText: String {
        let hint = onTap == nil ? "" : ", double tap to adjust tanpura"
        return label + hint
    }
}

#Preview("Raga") {
    TanpuraRagaPill(
        mode: .raga(name: "Raga Yaman"),
        saLabel: "C4",
        backgroundColor: .black.opacity(0.35),
        foregroundColor: .white,
        onTap: {}
    ).padding()
}

#Preview("Western") {
    TanpuraRagaPill(
        mode: .westernKey(key: "C major", bpm: 72),
        saLabel: "C4",
        backgroundColor: .black.opacity(0.35),
        foregroundColor: .white
    ).padding()
}

#Preview("Pop") {
    TanpuraRagaPill(
        mode: .popSong(artist: "Taylor Swift", song: "Love Story"),
        saLabel: "G4",
        backgroundColor: .white.opacity(0.72),
        foregroundColor: .purple
    ).padding()
}
