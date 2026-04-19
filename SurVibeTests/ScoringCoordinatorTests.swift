// SurVibeTests/ScoringCoordinatorTests.swift
import SVLearning
import Testing

@testable import SurVibe

/// Unit tests for `ScoringCoordinator` (SP-3a).
///
/// `ScoringCoordinator` is a pure-computation `@Observable @MainActor` class
/// extracted from `PlayAlongViewModel`. No audio, no SwiftData, no UI.
@MainActor
@Suite("ScoringCoordinator")
struct ScoringCoordinatorTests {

    /// Helper: build a NoteScore with explicit grade + accuracy.
    ///
    /// All deviation fields are set to zero since scoring coordinator tests
    /// only care about grade and accuracy for aggregate computation.
    private func score(
        grade: NoteGrade,
        accuracy: Double,
        expected: String = "Sa"
    ) -> NoteScore {
        NoteScore(
            grade: grade,
            accuracy: accuracy,
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            expectedNote: expected
        )
    }

    @Test
    func recordIncrementsHitCountForNonMiss() {
        let s = ScoringCoordinator()

        s.record(score(grade: .perfect, accuracy: 1.0))
        s.record(score(grade: .good, accuracy: 0.8))
        s.record(score(grade: .miss, accuracy: 0))

        #expect(s.notesHit == 2, "Only non-miss scores increment notesHit")
        #expect(s.noteScores.count == 3, "All scores are appended")
    }

    @Test
    func accuracyAveragesCorrectly() {
        let s = ScoringCoordinator()

        s.record(score(grade: .perfect, accuracy: 1.0))
        s.record(score(grade: .good, accuracy: 0.6))

        #expect(abs(s.accuracy - 0.8) < 0.0001, "accuracy = average of recorded accuracies")
    }

    @Test
    func updateStreakIncrementsOnHitAndResetsOnMiss() {
        let s = ScoringCoordinator()

        s.updateStreak(grade: .perfect)
        s.updateStreak(grade: .good)
        s.updateStreak(grade: .perfect)
        #expect(s.streak == 3)
        #expect(s.longestStreak == 3)

        s.updateStreak(grade: .miss)
        #expect(s.streak == 0, "Miss resets current streak")
        #expect(s.longestStreak == 3, "Longest streak retained")

        s.updateStreak(grade: .perfect)
        s.updateStreak(grade: .perfect)
        #expect(s.streak == 2)
        #expect(s.longestStreak == 3, "Longest unchanged until beaten")
    }

    @Test
    func finalizeComputesStarRatingAndXP() {
        let s = ScoringCoordinator()

        // Record 4 notes averaging ~0.8 accuracy.
        s.record(score(grade: .perfect, accuracy: 1.0))
        s.record(score(grade: .good, accuracy: 0.7))
        s.record(score(grade: .good, accuracy: 0.8))
        s.record(score(grade: .good, accuracy: 0.7))

        s.finalize(songDifficulty: 3)

        #expect(s.starRating > 0, "Star rating computed from accuracy")
        #expect(s.xpEarned > 0, "XP computed from accuracy and difficulty")
    }

    @Test
    func resetClearsAllState() {
        let s = ScoringCoordinator()

        s.record(score(grade: .perfect, accuracy: 1.0))
        s.record(score(grade: .good, accuracy: 0.8))
        s.updateStreak(grade: .perfect)
        s.finalize(songDifficulty: 5)

        s.reset()

        #expect(s.noteScores.isEmpty)
        #expect(s.notesHit == 0)
        #expect(s.accuracy == 0)
        #expect(s.streak == 0)
        #expect(s.longestStreak == 0)
        #expect(s.starRating == 0)
        #expect(s.xpEarned == 0)
    }
}
