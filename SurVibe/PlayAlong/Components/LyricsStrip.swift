import SwiftUI

/// Big centered lyrics band with word-level karaoke highlight.
///
/// Below the optional Devanagari line, renders each `LyricWord` with
/// per-word timing. At the current playback time, the active word
/// glows; past words fade to 55% opacity; future words stay at 35%.
///
/// Per latency contract: theme colors arrive as `let` parameters.
struct LyricsStrip: View {
    struct LyricWord: Identifiable, Sendable {
        let id = UUID()
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval

        init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
            self.text = text
            self.startTime = startTime
            self.endTime = endTime
        }
    }

    let words: [LyricWord]
    let devanagariLine: String?
    let currentTime: TimeInterval
    let backgroundColor: Color

    var body: some View {
        VStack(spacing: 4) {
            if let devanagariLine {
                Text(devanagariLine)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
            HStack(spacing: 4) {
                ForEach(words) { word in
                    Text(word.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(foregroundStyle(for: word))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private func foregroundStyle(for word: LyricWord) -> Color {
        if currentTime >= word.startTime && currentTime <= word.endTime {
            return Color(red: 1.00, green: 0.84, blue: 1.00)  // #FFD6FF highlight
        } else if currentTime > word.endTime {
            return .white.opacity(0.55)
        } else {
            return .white.opacity(0.35)
        }
    }

    private var accessibilityText: String {
        (devanagariLine.map { $0 + " — " } ?? "") + words.map { $0.text }.joined(separator: " ")
    }
}

#Preview("Karaoke mid-line") {
    LyricsStrip(
        words: [
            .init(text: "Romeo", startTime: 0.0, endTime: 0.5),
            .init(text: "save", startTime: 0.5, endTime: 0.9),
            .init(text: "me,", startTime: 0.9, endTime: 1.2),
            .init(text: "they're", startTime: 1.2, endTime: 1.6),
            .init(text: "trying", startTime: 1.6, endTime: 2.0),
            .init(text: "to", startTime: 2.0, endTime: 2.2),
            .init(text: "tell", startTime: 2.2, endTime: 2.5),
            .init(text: "me", startTime: 2.5, endTime: 2.8),
        ],
        devanagariLine: nil,
        currentTime: 2.3,
        backgroundColor: Color(red: 0.35, green: 0.09, blue: 0.44).opacity(0.82)
    )
    .padding()
}

#Preview("Sargam Devanagari") {
    LyricsStrip(
        words: [
            .init(text: "jana", startTime: 0.0, endTime: 0.5),
            .init(text: "gana", startTime: 0.5, endTime: 1.0),
            .init(text: "mana", startTime: 1.0, endTime: 1.5),
        ],
        devanagariLine: "जन गण मन अधिनायक",
        currentTime: 0.7,
        backgroundColor: Color.black.opacity(0.55)
    )
    .padding()
}
