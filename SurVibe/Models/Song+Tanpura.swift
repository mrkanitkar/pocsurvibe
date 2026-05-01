import Foundation

/// Tanpura-related derived values for a `Song`.
///
/// T5' (2026-05-01): `defaultSaFrequencyHz` moved onto `Song` as a stored
/// field (populated at import time by the new MusicXML extractor in T6a).
/// The pitch-class-to-Hz helper is kept here as a static utility so the
/// import pipeline can derive the value from a key-signature raw string.
extension Song {
    /// Middle C (C4) in equal temperament with A4 = 440 Hz.
    static let referenceC4Hz: Double = 261.6255653005986

    /// Compute Sa frequency in Hz from a key-signature raw string.
    ///
    /// Parses the leading pitch-class token (e.g., `"C major"` → C,
    /// `"E♭ minor"` → E♭) and maps to octave-4 equal-temperament Hz.
    /// Unrecognized or empty values fall back to C4.
    ///
    /// - Parameter keySignatureRaw: Raw key-signature string from MusicXML.
    /// - Returns: Sa frequency in Hz at octave 4.
    static func saFrequencyHz(forKeySignatureRaw keySignatureRaw: String) -> Double {
        let token = keySignatureRaw
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        let semitones = semitonesFromC(pitchClassToken: token)
        return referenceC4Hz * pow(2.0, Double(semitones) / 12.0)
    }

    /// Maps a pitch-class token to semitones from C.
    ///
    /// Accepts both sharp (`#`, `♯`) and flat (`b`, `♭`) spellings.
    /// Returns 0 for unknown or empty tokens.
    private static func semitonesFromC(pitchClassToken: String) -> Int {
        let normalized = pitchClassToken
            .replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        guard let first = normalized.first else { return 0 }
        let letter = String(first).uppercased()
        let accidental = String(normalized.dropFirst())
        let base: [String: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
        ]
        guard let baseSemitone = base[letter] else { return 0 }
        let adjustment: Int
        switch accidental {
        case "#": adjustment = 1
        case "b": adjustment = -1
        case "": adjustment = 0
        default: return 0
        }
        return (baseSemitone + adjustment + 12) % 12
    }
}
