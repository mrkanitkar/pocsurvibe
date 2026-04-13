import Foundation

/// Scores chord completeness by comparing expected and detected pitch sets.
///
/// Uses the intersection-over-expected formula: `score = |intersection| / |expected|`.
/// Missing notes reduce the score. Extra notes (embellishments) are not penalized.
///
/// ## Usage
///
/// ```swift
/// let score = ChordScoreCalculator.score(
///     expectedNotes: [60, 64, 67],  // C major chord
///     detectedNotes: [60, 64],       // missed the G
///     timingWindowSeconds: 0.050
/// )
/// // score.completeness == 0.667 (2 of 3 notes)
/// ```
public enum ChordScoreCalculator {

    /// Result of chord completeness scoring.
    public struct ChordScore: Sendable {
        /// Fraction of expected notes that were detected (0.0–1.0).
        public let completeness: Double

        /// Number of expected notes in the chord.
        public let expectedCount: Int

        /// Number of expected notes that were actually played.
        public let matchedCount: Int

        /// Notes that were expected but not detected.
        public let missingNotes: Set<Int>
    }

    /// Score chord completeness by comparing expected and detected MIDI note sets.
    ///
    /// - Parameters:
    ///   - expectedNotes: MIDI note numbers that should be played simultaneously.
    ///   - detectedNotes: MIDI note numbers actually detected (from MIDI or ChromagramDSP).
    /// - Returns: A ``ChordScore`` with completeness fraction and details.
    public static func score(
        expectedNotes: Set<Int>,
        detectedNotes: Set<Int>
    ) -> ChordScore {
        guard !expectedNotes.isEmpty else {
            return ChordScore(completeness: 1.0, expectedCount: .zero, matchedCount: .zero, missingNotes: [])
        }

        let matched = expectedNotes.intersection(detectedNotes)
        let missing = expectedNotes.subtracting(detectedNotes)
        let completeness = Double(matched.count) / Double(expectedNotes.count)

        return ChordScore(
            completeness: completeness,
            expectedCount: expectedNotes.count,
            matchedCount: matched.count,
            missingNotes: missing
        )
    }
}
