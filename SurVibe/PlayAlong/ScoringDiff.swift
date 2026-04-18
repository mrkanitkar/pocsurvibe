import Foundation
import SVAudio
import SVLearning

/// Minimal state delta produced by `NoteMatchingActor` for a single note evaluation.
///
/// Carries only the fields that must be written back to `PlayAlongViewModel` on
/// `@MainActor`. Keeping this struct small reduces the data crossing the actor
/// isolation boundary to the bare minimum, avoiding unnecessary `@Observable`
/// mutation triggers.
///
/// `ScoringDiff` is `Sendable` because all stored properties are value types.
struct ScoringDiff: Sendable {
    /// ID of the note event whose state changed.
    let noteEventID: UUID

    /// New visual state to assign to `noteStates[noteEventID]`.
    let newState: FallingNotesLayoutEngine.NoteState

    /// Score produced for this attempt, or `nil` if no score was generated
    /// (e.g., wrong note in wait mode that did not match).
    let score: NoteScore?

    /// Whether the streak should increment (hit) or reset (miss) after this note.
    let streakOutcome: StreakOutcome

    /// Latency probe token with t0–t2 stamped (input → DSP → match).
    ///
    /// Forwarded to `MIDINoteHighlightCoordinator` to stamp t3 (frame presented)
    /// and record the complete pipeline measurement.
    var probeToken: ProbeToken?

    /// Chord completeness fraction (0.0–1.0) when this event is part of a
    /// simultaneous chord; `nil` for single-note events.
    ///
    /// Populated by `PlayAlongViewModel` after the per-note evaluate when the
    /// expected event belongs to a chord group (multiple `NoteEvent`s within a
    /// 10 ms window) and a fresh `ChordResult` is available from the mic chord
    /// stream. Used to blend chord completeness into the per-note accuracy.
    var chordCompleteness: Double?

    /// Streak outcome for a note attempt.
    enum StreakOutcome: Sendable {
        /// Note was hit — streak increments. Grade is carried for display.
        case hit(grade: NoteGrade)
        /// Note was missed — streak resets.
        case miss
        /// Wait-mode mismatch — no streak change.
        case noChange
    }
}
