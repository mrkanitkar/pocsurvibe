import SwiftUI
import Testing
@testable import SurVibe

struct LyricsStripTests {
    @Test func initializesWithWords() {
        let words = [
            LyricsStrip.LyricWord(text: "hello", startTime: 0, endTime: 1),
            LyricsStrip.LyricWord(text: "world", startTime: 1, endTime: 2),
        ]
        _ = LyricsStrip(words: words, devanagariLine: nil, currentTime: 0.5, backgroundColor: .black)
    }

    @Test func initializesWithDevanagariLine() {
        _ = LyricsStrip(
            words: [],
            devanagariLine: "जन गण मन",
            currentTime: 0,
            backgroundColor: .black
        )
    }

    @Test func lyricWordsAreIdentifiable() {
        let a = LyricsStrip.LyricWord(text: "a", startTime: 0, endTime: 1)
        let b = LyricsStrip.LyricWord(text: "a", startTime: 0, endTime: 1)
        #expect(a.id != b.id)  // distinct UUIDs
    }
}
