// SurVibe/PlayAlong/Coordinators/ScoringCoordinator.swift
import Foundation
import SVLearning

/// Tracks per-note scoring, running accuracy, streaks, and session-final
/// star rating + XP for the play-along experience.
///
/// Extracted from `PlayAlongViewModel` in SP-3a. Pure MainActor computation;
/// no audio, no SwiftData, no UI. Held as `let scoring = ScoringCoordinator()`
/// by `PlayAlongViewModel`, which re-exposes every property as a delegating
/// computed property so existing views/tests continue to read
/// `viewModel.accuracy` etc. unchanged (AD-1 facade).
///
/// ## Invariants
/// - `notesHit` counts non-miss records only.
/// - `accuracy` is the arithmetic mean of every recorded score's `accuracy`.
/// - `streak` resets to 0 on the first `.miss` and grows on any non-miss.
/// - `longestStreak` is monotonic (only grows).
/// - `starRating` and `xpEarned` are 0 until `finalize(songDifficulty:)` runs.
///
/// ## Thread safety
/// `@MainActor`-isolated. CoreMIDI callbacks that produce scores must hop to
/// MainActor before calling `record(_:)` (matches SP-0 AD-4 / SP-3 AD-6).
@Observable
@MainActor
final class ScoringCoordinator {
    // MARK: - Observed state

    /// Every note score recorded this session.
    private(set) var noteScores: [NoteScore] = []

    /// Count of non-miss note scores. Maintained incrementally.
    private(set) var notesHit: Int = 0

    /// Overall session accuracy (0.0–1.0), updated after every `record`.
    private(set) var accuracy: Double = 0

    /// Current streak of consecutive non-miss notes.
    private(set) var streak: Int = 0

    /// Longest streak achieved this session. Monotonic.
    private(set) var longestStreak: Int = 0

    /// Star rating (0–5). Computed by `finalize(songDifficulty:)`.
    private(set) var starRating: Int = 0

    /// XP earned. Computed by `finalize(songDifficulty:)`.
    private(set) var xpEarned: Int = 0

    /// Percentage of expected notes the user pressed correctly (0.0–1.0).
    ///
    /// Set by `finalize(songDifficulty:)`. Equals `notesHit / max(1, noteScores.count)`.
    /// Zero until finalization runs.
    private(set) var notesCorrectPercent: Double = 0

    /// Weighted timing accuracy (0.0–1.0): perfect=1.0, good=0.7, late/early=0.4, miss=0.0.
    ///
    /// Set by `finalize(songDifficulty:)`. Zero until finalization runs.
    private(set) var timingAccuracyPercent: Double = 0

    // MARK: - Internal state

    /// Running sum of accuracy values for O(1) average maintenance.
    private var accuracySum: Double = 0

    /// Running sum of per-note timing weights for `timingAccuracyPercent`.
    private var timingWeightSum: Double = 0

    // MARK: - Recording

    /// Append a note score and update `notesHit`, `accuracySum`, `accuracy`.
    ///
    /// This is the only sanctioned entry point for adding scores —
    /// direct `noteScores.append` would break invariants.
    func record(_ score: NoteScore) {
        noteScores.append(score)
        accuracySum += score.accuracy
        timingWeightSum += timingWeight(for: score.grade)
        if score.grade != .miss {
            notesHit += 1
        }
        accuracy =
            noteScores.isEmpty
            ? 0
            : accuracySum / Double(noteScores.count)
    }

    // MARK: - Private Helpers

    /// Timing weight used for `timingAccuracyPercent` aggregation.
    ///
    /// Mirrors the spec §5.1 weighting: perfect=1.0, good=0.7, fair=0.4, miss=0.0.
    private func timingWeight(for grade: NoteGrade) -> Double {
        switch grade {
        case .perfect: return 1.0
        case .good: return 0.7
        case .fair: return 0.4
        case .miss: return 0.0
        }
    }

    /// Update `streak` and `longestStreak` after a note.
    ///
    /// Miss resets the current streak to 0. Non-miss grows the streak and
    /// raises `longestStreak` if beaten.
    func updateStreak(grade: NoteGrade) {
        if grade != .miss {
            streak += 1
            longestStreak = max(longestStreak, streak)
        } else {
            streak = 0
        }
    }

    // MARK: - Finalization

    /// Compute session-final metrics: final accuracy, star rating, XP,
    /// split scoring (notesCorrectPercent, timingAccuracyPercent),
    /// and a streak-from-grade-sequence recomputation.
    ///
    /// Called once at session completion by `PlayAlongViewModel.completeSession`
    /// (SP-3b will move the call into `PlaybackCoordinator`).
    ///
    /// - Parameter songDifficulty: The song's `difficulty` field (1–5).
    func finalize(songDifficulty: Int) {
        let count = noteScores.count
        accuracy =
            count == 0
            ? 0
            : accuracySum / Double(count)
        notesCorrectPercent =
            count == 0
            ? 0
            : Double(notesHit) / Double(count)
        timingAccuracyPercent =
            count == 0
            ? 0
            : timingWeightSum / Double(count)
        starRating = PracticeScoring.starRating(accuracy: accuracy)
        xpEarned = PracticeScoring.xpEarned(
            accuracy: accuracy,
            difficulty: songDifficulty
        )
        longestStreak = max(
            longestStreak,
            PracticeScoring.longestStreak(grades: noteScores.map(\.grade))
        )
    }

    // MARK: - Reset

    /// Clear all state. Call at session start (`PlayAlongViewModel.loadSong`).
    func reset() {
        noteScores = []
        notesHit = 0
        accuracy = 0
        streak = 0
        longestStreak = 0
        starRating = 0
        xpEarned = 0
        notesCorrectPercent = 0
        timingAccuracyPercent = 0
        accuracySum = 0
        timingWeightSum = 0
    }
}
