import Foundation

/// Validates a normalised `ParsedNotation` and generates smart warnings.
///
/// Warnings are categorised by severity:
/// - `.info` — minor quality suggestions (e.g. no key signature)
/// - `.warning` — accuracy concerns (e.g. very short song, extreme tempo)
/// - `.error` — blocking issues (e.g. too few notes)
///
/// The import pipeline presents all warnings to the user via the smart
/// warnings UI. Only `.error` severity prevents saving; `.info` and
/// `.warning` can be accepted and bypassed.
public struct ImportValidator: ImportValidatorProtocol {

    /// Minimum note count considered a valid song.
    private static let minimumNoteCount = 3

    /// Maximum note count before a warning is issued.
    private static let maximumNoteCount = 500

    /// Minimum tempo considered musically sane.
    private static let minimumTempo = 20

    /// Maximum tempo considered musically sane.
    private static let maximumTempo = 300

    public init() {}

    // MARK: - ImportValidatorProtocol

    /// Validates the notation and returns an array of warnings.
    ///
    /// - Parameter notation: A normalised `ParsedNotation` from `NotationNormalizer`.
    /// - Returns: Array of `ParseWarning`. Empty means fully valid.
    public func validate(_ notation: ParsedNotation) -> [ParseWarning] {
        var warnings: [ParseWarning] = []

        warnings.append(contentsOf: validateNoteCount(notation))
        warnings.append(contentsOf: validateTempo(notation))
        warnings.append(contentsOf: validateOctaveRange(notation))
        warnings.append(contentsOf: validateDurations(notation))

        return warnings
    }

    // MARK: - Individual Validation Rules

    /// Warns if note count is too low (warning) or unusually high (info).
    private func validateNoteCount(_ notation: ParsedNotation) -> [ParseWarning] {
        let count = notation.notes.count
        if count < Self.minimumNoteCount {
            return [ParseWarning(
                message: "Song has only \(count) note(s). A minimum of \(Self.minimumNoteCount) notes is recommended.",
                severity: .warning
            )]
        }
        if count > Self.maximumNoteCount {
            return [ParseWarning(
                message: "Song has \(count) notes, which is unusually long. Check that the input is correct.",
                severity: .info
            )]
        }
        return []
    }

    /// Warns if tempo is outside the musically sane range.
    private func validateTempo(_ notation: ParsedNotation) -> [ParseWarning] {
        let tempo = notation.tempo
        if tempo < Self.minimumTempo {
            return [ParseWarning(
                message: "Tempo of \(tempo) BPM is very slow. Typical range is 60–200 BPM.",
                severity: .warning
            )]
        }
        if tempo > Self.maximumTempo {
            return [ParseWarning(
                message: "Tempo of \(tempo) BPM is very fast. Typical range is 60–200 BPM.",
                severity: .warning
            )]
        }
        return []
    }

    /// Warns if any notes have octaves outside the piano range (1–7).
    private func validateOctaveRange(_ notation: ParsedNotation) -> [ParseWarning] {
        var warnings: [ParseWarning] = []
        for note in notation.notes {
            if let octave = note.octave, octave < 1 || octave > 7 {
                warnings.append(ParseWarning(
                    message: "Note '\(note.name)' has octave \(octave), "
                        + "which is outside the standard piano range (1–7).",
                    severity: .warning,
                    noteIndex: note.index
                ))
            }
        }
        return warnings
    }

    /// Issues an info warning if no key signature was detected.
    private func validateKeySignature(_ notation: ParsedNotation) -> [ParseWarning] {
        if notation.keySignature.isEmpty {
            return [ParseWarning(
                message: "No key signature detected. The notation will default to C major.",
                severity: .info
            )]
        }
        return []
    }

    /// Warns if any notes have duration less than 0.125 beats (32nd note).
    private func validateDurations(_ notation: ParsedNotation) -> [ParseWarning] {
        var warnings: [ParseWarning] = []
        for note in notation.notes {
            if let duration = note.durationBeats, duration < 0.125 {
                warnings.append(ParseWarning(
                    message: "Note '\(note.name)' at position \(note.index + 1) "
                        + "has a very short duration (\(duration) beats).",
                    severity: .info,
                    noteIndex: note.index
                ))
            }
        }
        return warnings
    }
}
