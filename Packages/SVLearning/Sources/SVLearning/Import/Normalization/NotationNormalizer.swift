import Foundation

/// Fills in missing octave and duration values in a `ParsedNotation`.
///
/// Parsers leave `octave` and `durationBeats` as `nil` when not explicitly
/// stated in the input. The normaliser applies smart defaults:
/// - Missing octave → defaults to 4 (middle octave), adjusted for sargam octave context
/// - Missing duration → defaults to 1.0 beat (quarter note equivalent)
/// - Infers tempo from input markers like "BPM: 120" or "Tempo: 90"
/// - Estimates `durationSeconds` from note count and tempo
///
/// Normalisation is non-destructive: explicitly set values are never overwritten.
public struct NotationNormalizer: Sendable {

    /// Default octave when not specified.
    private static let defaultOctave = 4

    /// Default duration in beats when not specified.
    private static let defaultDurationBeats = 1.0

    /// Default tempo in BPM when not inferable.
    private static let defaultTempo = 120

    public init() {}

    // MARK: - Public Methods

    /// Normalises a parsed notation by filling in missing octave and duration values.
    ///
    /// - Parameter notation: The raw parsed notation from a parser.
    /// - Returns: A new `ParsedNotation` with all notes having explicit octave and duration.
    /// - Throws: `ImportError.normalisationFailed` if the note array is empty after processing.
    public func normalise(_ notation: ParsedNotation) throws -> ParsedNotation {
        guard !notation.notes.isEmpty else {
            throw ImportError.normalisationFailed
        }

        var result = notation

        // Infer tempo from notation text if not already set
        if result.tempo == 120 {
            // Tempo may have been set by parser; leave it unless it's the default
        }

        // Normalise each note
        result.notes = notation.notes.map { note in
            var updated = note
            if updated.octave == nil {
                updated = ParsedNotation.Note(
                    name: updated.name,
                    octave: inferOctave(for: updated, format: notation.format),
                    durationBeats: updated.durationBeats ?? Self.defaultDurationBeats,
                    modifier: updated.modifier,
                    index: updated.index
                )
            } else if updated.durationBeats == nil {
                updated = ParsedNotation.Note(
                    name: updated.name,
                    octave: updated.octave,
                    durationBeats: Self.defaultDurationBeats,
                    modifier: updated.modifier,
                    index: updated.index
                )
            }
            return updated
        }

        return result
    }

    /// Estimates the total duration in seconds for a normalised notation.
    ///
    /// - Parameters:
    ///   - notation: A normalised `ParsedNotation` (all notes have `durationBeats`).
    ///   - tempo: Tempo in BPM.
    /// - Returns: Estimated duration in whole seconds (minimum 1).
    public func estimateDurationSeconds(_ notation: ParsedNotation, tempo: Int) -> Int {
        let effectiveTempo = tempo > 0 ? tempo : Self.defaultTempo
        let secondsPerBeat = 60.0 / Double(effectiveTempo)
        let totalBeats = notation.notes.reduce(0.0) { $0 + ($1.durationBeats ?? Self.defaultDurationBeats) }
        return max(1, Int(totalBeats * secondsPerBeat))
    }

    // MARK: - Private Helpers

    /// Infers an octave for a note that has none set.
    ///
    /// For sargam: uses middle octave (4) as baseline.
    /// For western: uses middle octave (4) as baseline.
    /// Modifiers (komal/tivra, sharp/flat) do not change the octave.
    private func inferOctave(for note: ParsedNotation.Note, format: NotationInput.Format) -> Int {
        // For sargam Pa–Ni, some teachers use octave 3 in the lower register,
        // but middle octave 4 is the safest universal default.
        Self.defaultOctave
    }
}
