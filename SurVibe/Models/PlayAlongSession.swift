import Foundation
import SwiftData

/// Records the outcome of a single Play Along session.
///
/// Persists split scoring metrics: notes-correct percentage and timing-accuracy
/// percentage as distinct headline numbers. The composite score is kept for
/// sorting and backward-compatible display. Created by Amendment A of the
/// Play Tab v2 plan — replaces the ad-hoc session data previously produced by
/// `SessionRecorder`.
@Model
public final class PlayAlongSession {

    // MARK: - Properties

    /// Unique identifier for this session.
    public var id: UUID = UUID()

    /// The song that was practiced.
    public var songID: UUID = UUID()

    /// When the session started.
    public var startedAt: Date = Date()

    /// When the session ended, if completed.
    public var endedAt: Date?

    /// Total notes the user attempted to play.
    public var notesAttempted: Int = 0

    /// Notes where the user hit the correct key (any timing window).
    public var notesCorrect: Int = 0

    /// Expected notes whose timing window passed without input.
    public var notesMissed: Int = 0

    /// Unmatched user keypresses (not blocking but tracked).
    public var notesExtra: Int = 0

    /// Weighted timing accuracy (0.0–1.0): perfect=1.0, good=0.7,
    /// late/early=0.4, miss=0.0.
    public var timingAccuracyPercent: Double = 0

    /// Percentage of expected notes correctly keyed (0.0–1.0).
    public var notesCorrectPercent: Double = 0

    /// Legacy composite NoteScore aggregate, useful for sort/ranking.
    public var compositeScore: Double?

    /// Tempo scale used during the session (0.5–1.5).
    public var tempoScale: Double?

    /// Practice mode used: "both", "rightHand", "leftHand".
    public var practiceMode: String?

    // MARK: - Initialization

    /// Create a new play-along session record.
    ///
    /// All scoring fields default to zero so callers can construct the record
    /// at session start and fill in results at session end.
    ///
    /// - Parameters:
    ///   - songID: Unique identifier of the practiced song.
    ///   - startedAt: Timestamp when the session began.
    ///   - notesAttempted: Total notes the user attempted. Default 0.
    ///   - notesCorrect: Notes where the correct key was hit. Default 0.
    ///   - notesMissed: Expected notes that were missed. Default 0.
    ///   - notesExtra: Unmatched extra keypresses. Default 0.
    ///   - timingAccuracyPercent: Weighted timing accuracy (0.0–1.0). Default 0.
    ///   - notesCorrectPercent: Correct-note percentage (0.0–1.0). Default 0.
    public init(
        songID: UUID,
        startedAt: Date,
        notesAttempted: Int = 0,
        notesCorrect: Int = 0,
        notesMissed: Int = 0,
        notesExtra: Int = 0,
        timingAccuracyPercent: Double = 0,
        notesCorrectPercent: Double = 0
    ) {
        self.id = UUID()
        self.songID = songID
        self.startedAt = startedAt
        self.notesAttempted = notesAttempted
        self.notesCorrect = notesCorrect
        self.notesMissed = notesMissed
        self.notesExtra = notesExtra
        self.timingAccuracyPercent = timingAccuracyPercent
        self.notesCorrectPercent = notesCorrectPercent
    }
}
