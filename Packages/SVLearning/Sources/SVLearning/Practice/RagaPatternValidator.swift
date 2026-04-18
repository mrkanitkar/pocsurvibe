import Foundation

/// Validates note sequences against a raga's aarohan (ascending) and avarohan (descending) rules.
///
/// Indian classical ragas have strict ascending (aarohan) and descending (avarohan) phrase
/// patterns. A note that is valid in the raga's scale may still be a violation if it appears
/// in the wrong direction. For example, in Raga Yaman the aarohan skips "Sa" at the start,
/// beginning "Ni Re Ga" from the lower octave.
///
/// ## Usage
/// ```swift
/// let context = RagaScoringContext.from(ragaName: "Yaman")!
/// let violations = RagaPatternValidator.validatePattern(
///     notes: ["Sa", "Re", "Ga", "Ma"],
///     raga: context,
///     direction: .ascending
/// )
/// ```
public struct RagaPatternValidator: Sendable {

    // MARK: - Types

    /// Direction of a musical phrase for pattern validation.
    public enum PhraseDirection: Sendable {
        /// Ascending phrase (aarohan).
        case ascending
        /// Descending phrase (avarohan).
        case descending
        /// Direction unknown or mixed — only raga membership is checked.
        case unknown
    }

    /// A single note that violates the raga's directional pattern rules.
    public struct PatternViolation: Sendable, Equatable {
        /// Zero-based index of the violating note in the input array.
        public let noteIndex: Int
        /// The note name that caused the violation (e.g., "Tivra Ma").
        public let note: String
        /// Human-readable explanation of why this note violates the pattern.
        public let reason: String

        /// Create a pattern violation.
        ///
        /// - Parameters:
        ///   - noteIndex: Index of the note in the input array.
        ///   - note: The violating note name.
        ///   - reason: Explanation of the violation.
        public init(noteIndex: Int, note: String, reason: String) {
            self.noteIndex = noteIndex
            self.note = note
            self.reason = reason
        }
    }

    // MARK: - Public API

    /// Validate a sequence of notes against a raga's pattern rules.
    ///
    /// Checks two categories of violations:
    /// 1. **Raga membership** — notes not in the raga's allowed swar set.
    /// 2. **Directional pattern** — notes present in the raga but absent from the
    ///    aarohan (ascending) or avarohan (descending) pattern for the given direction.
    ///
    /// When `direction` is `.unknown`, only raga membership is checked (no directional
    /// validation is applied).
    ///
    /// - Parameters:
    ///   - notes: Array of Swar names (e.g., ["Sa", "Re", "Ga"]).
    ///   - raga: The raga scoring context with allowed swars and patterns.
    ///   - direction: The phrase direction to validate against.
    /// - Returns: Array of violations found, empty if the pattern is valid.
    public static func validatePattern(
        notes: [String],
        raga: RagaScoringContext,
        direction: PhraseDirection
    ) -> [PatternViolation] {
        var violations: [PatternViolation] = []

        let directionalPattern: [String]?
        switch direction {
        case .ascending:
            directionalPattern = raga.aarohan
        case .descending:
            directionalPattern = raga.avarohan
        case .unknown:
            directionalPattern = nil
        }

        let patternSet: Set<String>? = directionalPattern.map { Set($0) }

        for (index, note) in notes.enumerated() {
            // Check 1: Is the note in the raga at all?
            if !raga.isNoteInRaga(note) {
                violations.append(PatternViolation(
                    noteIndex: index,
                    note: note,
                    reason: "\(note) is not in raga \(raga.ragaName)"
                ))
                continue
            }

            // Check 2: Is the note allowed in this direction?
            if let allowedNotes = patternSet, !allowedNotes.contains(note) {
                let directionName = direction == .ascending ? "aarohan" : "avarohan"
                violations.append(PatternViolation(
                    noteIndex: index,
                    note: note,
                    reason: "\(note) is not in \(raga.ragaName) \(directionName)"
                ))
            }
        }

        return violations
    }
}
