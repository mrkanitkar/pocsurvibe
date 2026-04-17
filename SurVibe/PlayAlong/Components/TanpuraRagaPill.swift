import SwiftUI

/// Context-aware pill at top-left of PlayAlong chrome.
///
/// Three modes:
/// - `.raga`: Hindustani — shows pulsing red dot + "Raga X · Sa = Y"
/// - `.westernKey`: Western — shows "C major · ♩ = 72"
/// - `.popSong`: Pop Era — shows heart + "Artist · Song"
///
/// Per latency contract: theme colors arrive as `let` parameters.
struct TanpuraRagaPill: View {
    enum Mode {
        case raga(name: String, tonic: String)
        case westernKey(key: String, bpm: Int)
        case popSong(artist: String, song: String)
    }

    let mode: Mode
    let backgroundColor: Color
    let foregroundColor: Color

    var body: some View {
        HStack(spacing: 5) {
            leadingIcon
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(backgroundColor, in: Capsule())
        .foregroundStyle(foregroundColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
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
        case .westernKey:
            EmptyView()
        }
    }

    private var label: String {
        switch mode {
        case .raga(let name, let tonic): "\(name) · Sa = \(tonic)"
        case .westernKey(let key, let bpm): "\(key) · ♩ = \(bpm)"
        case .popSong(let artist, let song): "\(artist) · \(song)"
        }
    }
}

#Preview("Raga") {
    TanpuraRagaPill(
        mode: .raga(name: "Raga Yaman", tonic: "C4"),
        backgroundColor: .black.opacity(0.35),
        foregroundColor: .white
    ).padding()
}

#Preview("Western") {
    TanpuraRagaPill(
        mode: .westernKey(key: "C major", bpm: 72),
        backgroundColor: .black.opacity(0.35),
        foregroundColor: .white
    ).padding()
}

#Preview("Pop") {
    TanpuraRagaPill(
        mode: .popSong(artist: "Taylor Swift", song: "Love Story"),
        backgroundColor: .white.opacity(0.72),
        foregroundColor: .purple
    ).padding()
}
