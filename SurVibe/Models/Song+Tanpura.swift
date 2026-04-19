import Foundation

/// Tanpura-related derived values for a `Song`.
///
/// Keeps the SwiftData `@Model` lean by putting pure helpers in an extension.
/// No stored properties — all values derive from existing `Song` fields.
extension Song {
    /// Middle C (C4) in equal temperament with A4 = 440 Hz.
    static let referenceC4Hz: Double = 261.6255653005986

    /// Sa frequency derived from `keySignatureRaw`.
    ///
    /// Parses the leading pitch-class token (e.g., `"C major"` → C, `"E♭ minor"` → E♭)
    /// and maps to octave-4 equal-temperament Hz. Unrecognized or empty values
    /// fall back to C4 = 261.6256 Hz.
    ///
    /// - Returns: Sa frequency in Hz at octave 4.
    var defaultSaFrequencyHz: Double {
        let token = keySignatureRaw
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        let semitones = Self.semitonesFromC(pitchClassToken: token)
        return Self.referenceC4Hz * pow(2.0, Double(semitones) / 12.0)
    }

    /// Maps a pitch-class token to semitones from C.
    ///
    /// Accepts both sharp (`#`, `♯`) and flat (`b`, `♭`) spellings.
    /// Returns 0 for unknown or empty tokens.
    ///
    /// - Parameter pitchClassToken: A single pitch-class string such as `"C"`, `"D#"`, or `"E♭"`.
    /// - Returns: Semitone offset from C (0–11), or 0 on parse failure.
    private static func semitonesFromC(pitchClassToken: String) -> Int {
        // Normalize ♯/♭ to #/b and uppercase the letter.
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
        default: return 0 // unknown accidental → fall back to C
        }
        return (baseSemitone + adjustment + 12) % 12
    }
}
