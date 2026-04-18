import Foundation
import SVAudio

/// Score result for a single note attempt during practice.
///
/// Contains the overall grade, individual deviation measurements for pitch,
/// timing, and duration, plus the composite accuracy percentage used for
/// scoring and display.
public struct NoteScore: Sendable, Equatable, Identifiable {
    /// Unique identifier for this score.
    public let id: UUID

    /// Overall grade for this note attempt.
    public let grade: NoteGrade

    /// Composite accuracy percentage (0.0–1.0).
    ///
    /// Computed as a weighted combination of pitch, timing, and duration
    /// accuracy: 50% pitch + 30% timing + 20% duration.
    public let accuracy: Double

    /// Absolute pitch deviation in cents from the target note.
    public let pitchDeviationCents: Double

    /// Timing deviation in seconds from the expected note onset.
    public let timingDeviationSeconds: Double

    /// Duration deviation as a fraction of expected duration (0.0 = perfect).
    public let durationDeviation: Double

    /// The expected note name (swar) for this attempt.
    public let expectedNote: String

    /// The detected note name (swar) from pitch detection, if any.
    public let detectedNote: String?

    /// Whether the detected note was outside the active raga's scale.
    /// `nil` when no raga context was active during scoring.
    public let isOutOfRaga: Bool?

    /// Expression result detected during this note (logged for data collection, scored in Phase 5).
    public var expressionResult: ExpressionResult?

    /// Timestamp of this score.
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        grade: NoteGrade,
        accuracy: Double,
        pitchDeviationCents: Double,
        timingDeviationSeconds: Double,
        durationDeviation: Double,
        expectedNote: String,
        detectedNote: String? = nil,
        isOutOfRaga: Bool? = nil,
        expressionResult: ExpressionResult? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.grade = grade
        self.accuracy = accuracy
        self.pitchDeviationCents = pitchDeviationCents
        self.timingDeviationSeconds = timingDeviationSeconds
        self.durationDeviation = durationDeviation
        self.expectedNote = expectedNote
        self.detectedNote = detectedNote
        self.isOutOfRaga = isOutOfRaga
        self.expressionResult = expressionResult
        self.timestamp = timestamp
    }
}
