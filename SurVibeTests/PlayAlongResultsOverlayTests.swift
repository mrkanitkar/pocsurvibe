import Testing
import SVLearning

@testable import SurVibe

// MARK: - D4 Results Overlay Split Score Tests

/// Tests for the split-score metrics in `PlayAlongResultsOverlay` (Task D4).
///
/// Validates the data → formatted-string pipeline for "Notes correct" and
/// "Timing" headline metrics, and the `ScoringCoordinator` finalization
/// that populates them. Layout is verified via Xcode Previews, not here.
@Suite("PlayAlongResultsOverlay Split Score Tests")
@MainActor
struct PlayAlongResultsOverlayTests {

    // MARK: - formatAccuracy helper (used by metric() function)

    @Test("notesCorrectPercent 0.80 formats as 80%")
    func notesCorrectPercent80FormatsCorrectly() {
        let formatted = CompactScoringHUD.formatAccuracy(0.80)
        #expect(formatted == "80%")
    }

    @Test("timingAccuracyPercent 0.70 formats as 70%")
    func timingAccuracyPercent70FormatsCorrectly() {
        let formatted = CompactScoringHUD.formatAccuracy(0.70)
        #expect(formatted == "70%")
    }

    @Test("zero notesCorrectPercent formats as 0%")
    func zeroNotesCorrectFormatsAsZeroPercent() {
        let formatted = CompactScoringHUD.formatAccuracy(0.0)
        #expect(formatted == "0%")
    }

    @Test("perfect notesCorrectPercent formats as 100%")
    func perfectNotesCorrectFormatsAs100Percent() {
        let formatted = CompactScoringHUD.formatAccuracy(1.0)
        #expect(formatted == "100%")
    }

    @Test("fractional value rounds to nearest percent")
    func fractionalValueRoundsCorrectly() {
        // 0.856 * 100 = 85.6 → rounds to 86
        #expect(CompactScoringHUD.formatAccuracy(0.856) == "86%")
        // 0.124 * 100 = 12.4 → rounds to 12
        #expect(CompactScoringHUD.formatAccuracy(0.124) == "12%")
    }
}

// MARK: - ScoringCoordinator Split Metrics Tests

/// Tests for `ScoringCoordinator.notesCorrectPercent` and `timingAccuracyPercent`
/// populated by `finalize(songDifficulty:)`.
@Suite("ScoringCoordinator Split Score Tests")
@MainActor
struct ScoringCoordinatorSplitTests {

    // MARK: - Helpers

    private func makeScore(grade: NoteGrade) -> NoteScore {
        NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: grade == .miss ? "Re" : "Sa",
            pitchDeviationCents: grade == .miss ? 200 : 0,
            timingDeviationSeconds: grade == .perfect ? 0.01 : 0.2,
            durationDeviation: 0,
            ragaContext: nil
        )
    }

    // MARK: - notesCorrectPercent

    @Test("notesCorrectPercent is zero before finalize")
    func notesCorrectPercentIsZeroBeforeFinalize() {
        let coordinator = ScoringCoordinator()
        coordinator.record(makeScore(grade: .perfect))
        #expect(coordinator.notesCorrectPercent == 0.0)
    }

    @Test("notesCorrectPercent equals notesHit fraction after finalize")
    func notesCorrectPercentAfterFinalize() {
        let coordinator = ScoringCoordinator()
        // 3 perfect (non-miss), 1 miss → 3/4 = 0.75
        coordinator.record(makeScore(grade: .perfect))
        coordinator.record(makeScore(grade: .perfect))
        coordinator.record(makeScore(grade: .perfect))
        coordinator.record(makeScore(grade: .miss))
        coordinator.finalize(songDifficulty: 1)
        #expect(coordinator.notesHit == 3)
        #expect(coordinator.notesCorrectPercent == 0.75)
    }

    @Test("notesCorrectPercent is zero with all misses after finalize")
    func notesCorrectPercentAllMissesAfterFinalize() {
        let coordinator = ScoringCoordinator()
        coordinator.record(makeScore(grade: .miss))
        coordinator.record(makeScore(grade: .miss))
        coordinator.finalize(songDifficulty: 1)
        #expect(coordinator.notesCorrectPercent == 0.0)
    }

    @Test("notesCorrectPercent is 1.0 with all perfect after finalize")
    func notesCorrectPercentAllPerfectAfterFinalize() {
        let coordinator = ScoringCoordinator()
        coordinator.record(makeScore(grade: .perfect))
        coordinator.record(makeScore(grade: .perfect))
        coordinator.finalize(songDifficulty: 1)
        #expect(coordinator.notesCorrectPercent == 1.0)
    }

    // MARK: - timingAccuracyPercent

    @Test("timingAccuracyPercent is zero before finalize")
    func timingAccuracyPercentIsZeroBeforeFinalize() {
        let coordinator = ScoringCoordinator()
        coordinator.record(makeScore(grade: .perfect))
        #expect(coordinator.timingAccuracyPercent == 0.0)
    }

    @Test("timingAccuracyPercent is zero with empty scores")
    func timingAccuracyPercentEmptyScores() {
        let coordinator = ScoringCoordinator()
        coordinator.finalize(songDifficulty: 1)
        #expect(coordinator.timingAccuracyPercent == 0.0)
    }

    @Test("timingAccuracyPercent is 1.0 for all-perfect session")
    func timingAccuracyPercentAllPerfect() {
        let coordinator = ScoringCoordinator()
        // Force all scores to .perfect grade by passing 0 deviation
        for _ in 0..<3 {
            let score = NoteScoreCalculator.score(
                expectedNote: "Sa",
                detectedNote: "Sa",
                pitchDeviationCents: 0,
                timingDeviationSeconds: 0.01,
                durationDeviation: 0,
                ragaContext: nil
            )
            coordinator.record(score)
        }
        coordinator.finalize(songDifficulty: 1)
        // All perfect → weight = 1.0 each → mean = 1.0
        #expect(coordinator.timingAccuracyPercent == 1.0)
    }

    @Test("timingAccuracyPercent is 0.0 for all-miss session")
    func timingAccuracyPercentAllMiss() {
        let coordinator = ScoringCoordinator()
        coordinator.record(makeScore(grade: .miss))
        coordinator.record(makeScore(grade: .miss))
        coordinator.finalize(songDifficulty: 1)
        #expect(coordinator.timingAccuracyPercent == 0.0)
    }

    // MARK: - Reset

    @Test("reset clears split metrics")
    func resetClearsSplitMetrics() {
        let coordinator = ScoringCoordinator()
        coordinator.record(makeScore(grade: .perfect))
        coordinator.finalize(songDifficulty: 1)
        coordinator.reset()
        #expect(coordinator.notesCorrectPercent == 0.0)
        #expect(coordinator.timingAccuracyPercent == 0.0)
    }
}
