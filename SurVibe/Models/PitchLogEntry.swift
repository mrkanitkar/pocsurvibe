import Foundation
import SwiftData

/// Persisted pitch detection result captured during a practice session.
///
/// Stores frequency, confidence, and detected note name with session-relative
/// timestamps for offline analysis, ML training data, and intonation tracking.
/// Append-only per CloudKit rules — entries are never deleted or modified.
///
/// ## CloudKit Compatibility
/// - All fields have explicit default values.
/// - `note` stores the detected Swar name as a plain String (e.g., "Sa", "Re").
/// - Queryable by `sessionID` to reconstruct pitch contour for a session.
@Model
final class PitchLogEntry {
    // MARK: - Properties

    /// Practice session this pitch detection belongs to.
    var sessionID: UUID = UUID()

    /// Session-relative timestamp in seconds (0.0 = session start).
    var timestamp: Double = 0.0

    /// Detected fundamental frequency in Hz.
    var frequency: Double = 0.0

    /// Pitch detection confidence (0.0 = no confidence, 1.0 = maximum confidence).
    var confidence: Double = 0.0

    /// Detected note name (e.g., "Sa", "Re", "Komal Ga").
    var note: String = ""

    // MARK: - Initialization

    /// Create a pitch detection log entry.
    ///
    /// - Parameters:
    ///   - sessionID: UUID of the practice session this detection belongs to.
    ///   - timestamp: Session-relative time in seconds.
    ///   - frequency: Detected frequency in Hz.
    ///   - confidence: Detection confidence (0.0-1.0).
    ///   - note: Detected note name string.
    init(
        sessionID: UUID,
        timestamp: Double,
        frequency: Double,
        confidence: Double,
        note: String
    ) {
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.frequency = frequency
        self.confidence = confidence
        self.note = note
    }
}
