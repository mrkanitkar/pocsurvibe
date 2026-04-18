import Foundation
import SVAudio

/// Lightweight scoring context that holds raga metadata for note scoring.
///
/// Created from `RagaTuningProvider.context(for:)` when a song has a raga name.
/// Passed to `NoteScoreCalculator.score()` to enable raga-aware scoring:
/// - Uses JI cents deviation instead of 12ET cents for pitch accuracy
/// - Penalizes out-of-raga notes by capping their pitch accuracy
/// - Provides aarohan/avarohan patterns for directional validation
public struct RagaScoringContext: Sendable, Equatable {
    /// Set of allowed Swar raw values for the raga (e.g., "Sa", "Re", "Tivra Ma").
    public let allowedSwars: Set<String>

    /// Raga name for display purposes.
    public let ragaName: String

    /// Ascending note pattern for the raga (aarohan), if known.
    ///
    /// Contains Swar names in ascending order. Some ragas have vakra (zigzag)
    /// aarohan where certain notes are skipped (e.g., Yaman skips Ma in ascent).
    /// `nil` if the aarohan pattern is not defined for this raga.
    public let aarohan: [String]?

    /// Descending note pattern for the raga (avarohan), if known.
    ///
    /// Contains Swar names in descending order. Some ragas include notes in
    /// descent that are absent from the ascent (e.g., Kafi uses Komal Ni in descent).
    /// `nil` if the avarohan pattern is not defined for this raga.
    public let avarohan: [String]?

    /// Create a raga scoring context from a `RagaContext`.
    ///
    /// Uses the static raga pattern registry to populate aarohan and avarohan.
    ///
    /// - Parameter ragaContext: The raga context from `RagaTuningProvider`.
    public init(ragaContext: RagaContext) {
        self.allowedSwars = ragaContext.allowedSwarNames
        self.ragaName = ragaContext.ragaName
        let patterns = Self.knownPatterns[ragaContext.ragaName]
        self.aarohan = patterns?.aarohan
        self.avarohan = patterns?.avarohan
    }

    /// Create a raga scoring context with explicit values.
    ///
    /// Primarily for testing or when constructing a context without `RagaTuningProvider`.
    ///
    /// - Parameters:
    ///   - ragaName: Name of the raga.
    ///   - allowedSwars: Set of allowed Swar raw values.
    ///   - aarohan: Optional ascending pattern.
    ///   - avarohan: Optional descending pattern.
    public init(
        ragaName: String,
        allowedSwars: Set<String>,
        aarohan: [String]? = nil,
        avarohan: [String]? = nil
    ) {
        self.ragaName = ragaName
        self.allowedSwars = allowedSwars
        self.aarohan = aarohan
        self.avarohan = avarohan
    }

    /// Create a raga scoring context from a raga name.
    ///
    /// Returns `nil` if the raga is not recognized by `RagaTuningProvider`.
    ///
    /// - Parameter ragaName: Name of the raga (e.g., "Yaman").
    /// - Returns: A scoring context, or `nil` if the raga is unknown.
    public static func from(ragaName: String) -> RagaScoringContext? {
        guard let context = RagaTuningProvider.context(for: ragaName) else {
            return nil
        }
        return RagaScoringContext(ragaContext: context)
    }

    /// Check whether a note is in the raga's scale.
    ///
    /// - Parameter noteName: Swar name (e.g., "Ma", "Tivra Ma").
    /// - Returns: `true` if the note is in the raga.
    public func isNoteInRaga(_ noteName: String) -> Bool {
        allowedSwars.contains(noteName)
    }

    // MARK: - Known Raga Patterns

    /// Aarohan/avarohan pattern pair for a raga.
    private struct RagaPattern {
        let aarohan: [String]
        let avarohan: [String]
    }

    /// Registry of known aarohan/avarohan patterns for supported ragas.
    ///
    /// Patterns use Swar raw values. Notes listed are those allowed in each
    /// direction; the full raga scale is the union of aarohan and avarohan notes.
    private static let knownPatterns: [String: RagaPattern] = [
        "Yaman": RagaPattern(
            aarohan: ["Sa", "Re", "Ga", "Tivra Ma", "Pa", "Dha", "Ni"],
            avarohan: ["Ni", "Dha", "Pa", "Tivra Ma", "Ga", "Re", "Sa"]
        ),
        "Bhairav": RagaPattern(
            aarohan: ["Sa", "Komal Re", "Ga", "Ma", "Pa", "Komal Dha", "Ni"],
            avarohan: ["Ni", "Komal Dha", "Pa", "Ma", "Ga", "Komal Re", "Sa"]
        ),
        "Kafi": RagaPattern(
            aarohan: ["Sa", "Re", "Komal Ga", "Ma", "Pa", "Dha", "Komal Ni"],
            avarohan: ["Komal Ni", "Dha", "Pa", "Ma", "Komal Ga", "Re", "Sa"]
        ),
    ]
}
