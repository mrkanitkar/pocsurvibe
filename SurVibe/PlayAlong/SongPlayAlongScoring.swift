// SurVibe/PlayAlong/Lean/SongPlayAlongScoring.swift
import Foundation

/// Minimal scoring for Songs Play Along — counts hits and misses.
///
/// Replaces the 166-line `ScoringCoordinator` plus the chord/raga logic
/// scattered through `NoteRouter`. The lean version only tracks what the
/// screenshot shows: `notesHit / totalNotes` and percent.
///
/// Live during a session; reset on restart/cleanup.
@Observable
@MainActor
final class SongPlayAlongScoring {

    /// Total notes in the loaded song. Snapshot at construction time.
    let totalNotes: Int

    /// Count of correctly-played notes.
    private(set) var notesHit: Int = 0

    /// Count of missed notes (expected but not played in time).
    private(set) var notesMissed: Int = 0

    /// 0–100 percent. Computed from `notesHit / totalNotes` (uses total,
    /// not attempted, so partial sessions still show meaningful progress).
    var accuracyPercent: Int {
        guard totalNotes > 0 else { return 0 }
        return Int((Double(notesHit) / Double(totalNotes) * 100).rounded())
    }

    /// - Parameter totalNotes: Snapshot of `noteEvents.count` from the loaded song.
    init(totalNotes: Int) {
        self.totalNotes = totalNotes
    }

    /// Increment the hit counter. Called when the user plays a key that
    /// matches one of the currently-active sequenced notes.
    func recordHit() { notesHit += 1 }

    /// Increment the miss counter. Reserved for future use.
    func recordMiss() { notesMissed += 1 }

    /// Reset hit / miss counters. Called on restart / cleanup.
    func reset() {
        notesHit = 0
        notesMissed = 0
    }
}
