import Foundation
import SwiftData

/// Per-note score entry persisted after a practice session.
///
/// Captures individual note-level accuracy data that was previously discarded
/// when only aggregate `RiyazEntry.accuracyPercent` was saved. Enables
/// post-session drill-down review of each note attempt.
///
/// ## CloudKit Compatibility
/// - All fields have explicit default values.
/// - `grade` stores `NoteGrade.rawValue` as a String (enum compatibility).
/// - Append-only: entries are never deleted or modified after creation.
/// - Query by `sessionID` to reconstruct full session detail.
@Model
final class NoteScoreEntry {
    /// Unique identifier for this entry (auto-generated UUID).
    var id: UUID = UUID()

    /// Session identifier linking this entry to its parent practice session.
    ///
    /// All `NoteScoreEntry` rows from the same session share this UUID,
    /// enabling grouped queries for post-session review.
    var sessionID: UUID = UUID()

    /// Zero-based index of this note within the session sequence.
    var noteIndex: Int = 0

    /// Pitch accuracy component (0.0--1.0).
    var pitchAccuracy: Double = 0.0

    /// Timing accuracy component (0.0--1.0).
    var timingAccuracy: Double = 0.0

    /// Duration accuracy component (0.0--1.0).
    var durationAccuracy: Double = 0.0

    /// Weighted composite score (0.0--1.0): 50% pitch + 30% timing + 20% duration.
    var compositeScore: Double = 0.0

    /// Letter grade stored as `NoteGrade.rawValue` string.
    var grade: String = ""

    /// Expected sargam note name (e.g., "Sa", "Re", "Ga").
    var expectedNote: String = ""

    /// Detected frequency in Hz from pitch detection.
    var playedFrequency: Double = 0.0

    /// Detected sargam note name, or empty if pitch was unrecognized.
    var detectedNote: String = ""

    /// Pitch deviation from target in cents (positive = sharp, negative = flat).
    var pitchDeviationCents: Double = 0.0

    /// Timestamp when this note was played.
    var timestamp: Date = Date()

    /// Create a new per-note score entry.
    ///
    /// - Parameters:
    ///   - sessionID: UUID linking to the parent practice session.
    ///   - noteIndex: Zero-based position of this note in the session.
    ///   - pitchAccuracy: Pitch accuracy component (0.0--1.0).
    ///   - timingAccuracy: Timing accuracy component (0.0--1.0).
    ///   - durationAccuracy: Duration accuracy component (0.0--1.0).
    ///   - compositeScore: Weighted composite score (0.0--1.0).
    ///   - grade: `NoteGrade.rawValue` string.
    ///   - expectedNote: Expected sargam note name.
    ///   - playedFrequency: Detected frequency in Hz.
    ///   - detectedNote: Detected sargam note name.
    ///   - pitchDeviationCents: Pitch deviation from target in cents.
    ///   - timestamp: When this note was played.
    init(
        sessionID: UUID = UUID(),
        noteIndex: Int = 0,
        pitchAccuracy: Double = 0.0,
        timingAccuracy: Double = 0.0,
        durationAccuracy: Double = 0.0,
        compositeScore: Double = 0.0,
        grade: String = "",
        expectedNote: String = "",
        playedFrequency: Double = 0.0,
        detectedNote: String = "",
        pitchDeviationCents: Double = 0.0,
        timestamp: Date = Date()
    ) {
        self.id = UUID()
        self.sessionID = sessionID
        self.noteIndex = noteIndex
        self.pitchAccuracy = pitchAccuracy
        self.timingAccuracy = timingAccuracy
        self.durationAccuracy = durationAccuracy
        self.compositeScore = compositeScore
        self.grade = grade
        self.expectedNote = expectedNote
        self.playedFrequency = playedFrequency
        self.detectedNote = detectedNote
        self.pitchDeviationCents = pitchDeviationCents
        self.timestamp = timestamp
    }
}
