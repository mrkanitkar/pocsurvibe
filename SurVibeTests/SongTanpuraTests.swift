import Foundation
import Testing
@testable import SurVibe

struct SongTanpuraTests {
    private func song(key: String) -> Song {
        let s = Song(title: "t", difficulty: 1, tempo: 120)
        s.keySignatureRaw = key
        return s
    }

    @Test func cMajorMapsToC4() {
        #expect(song(key: "C major").defaultSaFrequencyHz == 261.6255653005986)
    }

    @Test func dMinorMapsToD4() {
        // D4 = 261.6256 * 2^(2/12) ≈ 293.6648
        let hz = song(key: "D minor").defaultSaFrequencyHz
        #expect(abs(hz - 293.6648) < 0.001)
    }

    @Test func cSharpMajorParsed() {
        let hz = song(key: "C# major").defaultSaFrequencyHz
        #expect(abs(hz - 277.1826) < 0.001)
    }

    @Test func flatSpellingMapsViaEnharmonic() {
        // E♭ minor → D#4 enharmonic = 311.127 Hz
        let hz = song(key: "E♭ minor").defaultSaFrequencyHz
        #expect(abs(hz - 311.127) < 0.01)
    }

    @Test func emptyKeySignatureFallsBackToC4() {
        #expect(song(key: "").defaultSaFrequencyHz == 261.6255653005986)
    }

    @Test func unrecognizedKeyFallsBackToC4() {
        #expect(song(key: "Martian lydian").defaultSaFrequencyHz == 261.6255653005986)
    }
}
