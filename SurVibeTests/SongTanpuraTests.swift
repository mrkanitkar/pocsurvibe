import Foundation
import Testing
@testable import SurVibe

/// T5' (2026-05-01): `Song.defaultSaFrequencyHz` is now a stored field
/// populated at import time. The pitch-class-to-Hz derivation moved to a
/// static helper `Song.saFrequencyHz(forKeySignatureRaw:)` so the import
/// pipeline (Wave 3) can compute the value once. These tests pin the
/// helper's behavior; T6a/T7 will exercise the import-time wiring.
struct SongTanpuraTests {
    @Test func cMajorMapsToC4() {
        let hz = Song.saFrequencyHz(forKeySignatureRaw: "C major")
        #expect(hz == 261.6255653005986)
    }

    @Test func dMinorMapsToD4() {
        let hz = Song.saFrequencyHz(forKeySignatureRaw: "D minor")
        #expect(abs(hz - 293.6648) < 0.001)
    }

    @Test func cSharpMajorParsed() {
        let hz = Song.saFrequencyHz(forKeySignatureRaw: "C# major")
        #expect(abs(hz - 277.1826) < 0.001)
    }

    @Test func flatSpellingMapsViaEnharmonic() {
        let hz = Song.saFrequencyHz(forKeySignatureRaw: "E♭ minor")
        #expect(abs(hz - 311.127) < 0.01)
    }

    @Test func emptyKeySignatureFallsBackToC4() {
        let hz = Song.saFrequencyHz(forKeySignatureRaw: "")
        #expect(hz == 261.6255653005986)
    }

    @Test func unrecognizedKeyFallsBackToC4() {
        let hz = Song.saFrequencyHz(forKeySignatureRaw: "Martian lydian")
        #expect(hz == 261.6255653005986)
    }

    @Test func storedFieldDefaultsToC4() {
        let song = Song(title: "t", difficulty: 1, tempo: 120)
        // Stored field default is C4. T6a/T7 will populate it at import time.
        #expect(abs(song.defaultSaFrequencyHz - 261.6255653005986) < 0.0001)
    }
}
