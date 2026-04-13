import Foundation
import Testing

@testable import SVLearning

// MARK: - NoteScoreCalculator Timing & Duration Tests

/// Tests for timing and duration accuracy computation in `NoteScoreCalculator`.
///
/// Verifies that the calculator correctly penalizes non-zero timing and duration
/// deviations according to the thresholds defined in `PracticeConstants`.
struct NoteScoreCalculatorTests {

    // MARK: - Timing Accuracy

    @Test
    func perfectTimingGivesFullTimingWeight() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0
        )

        // All deviations zero: composite should be 1.0.
        #expect(score.accuracy == 1.0)
        #expect(score.grade == .perfect)
    }

    @Test
    func timingWithinPerfectThresholdScoresOne() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0.08,
            durationDeviation: 0
        )

        // 0.08s is within perfectTimingSeconds (0.1s), so timing accuracy = 1.0.
        // Composite = 0.5 * 1.0 + 0.3 * 1.0 + 0.2 * 1.0 = 1.0.
        #expect(score.accuracy == 1.0)
    }

    @Test
    func timingBetweenPerfectAndGoodReducesScore() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0.18,
            durationDeviation: 0
        )

        // 0.18s is between perfectTimingSeconds (0.1) and goodTimingSeconds (0.25).
        // Timing accuracy should be between 0.7 and 0.9.
        // Composite = 0.5 * 1.0 + 0.3 * timingAcc + 0.2 * 1.0.
        #expect(score.accuracy < 1.0)
        #expect(score.accuracy > 0.7)
    }

    @Test
    func timingBetweenGoodAndFairReducesScoreMore() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0.35,
            durationDeviation: 0
        )

        // 0.35s is between goodTimingSeconds (0.25) and fairTimingSeconds (0.5).
        // Timing accuracy should be between 0.5 and 0.7.
        let scoreAt018 = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0.18,
            durationDeviation: 0
        )
        #expect(score.accuracy < scoreAt018.accuracy)
    }

    @Test
    func timingBeyondFairThresholdGivesLowScore() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0.8,
            durationDeviation: 0
        )

        // 0.8s is beyond fairTimingSeconds (0.5).
        // Timing accuracy should be below 0.5.
        // Composite = 0.5 * 1.0 + 0.3 * lowAcc + 0.2 * 1.0 < 0.85.
        #expect(score.accuracy < 0.85)
    }

    // MARK: - Duration Accuracy

    @Test
    func perfectDurationGivesFullDurationWeight() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0
        )

        #expect(score.accuracy == 1.0)
    }

    @Test
    func durationWithinPerfectThresholdScoresOne() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0.10
        )

        // 0.10 is within perfectDurationFraction (0.15), so duration accuracy = 1.0.
        #expect(score.accuracy == 1.0)
    }

    @Test
    func durationBetweenPerfectAndGoodReducesScore() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0.22
        )

        // 0.22 is between perfectDurationFraction (0.15) and goodDurationFraction (0.30).
        #expect(score.accuracy < 1.0)
        #expect(score.accuracy > 0.8)
    }

    @Test
    func durationFiftyPercentOffReducesScoreSignificantly() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0.5
        )

        // 0.5 is exactly at fairDurationFraction threshold.
        // Duration accuracy = 0.5, composite = 0.5 + 0.3 + 0.2 * 0.5 = 0.9.
        #expect(score.accuracy < 1.0)
    }

    @Test
    func durationOneHundredPercentOffReducesScoreMore() {
        let halfOffScore = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0.5
        )

        let doubleOffScore = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 1.0
        )

        #expect(doubleOffScore.accuracy < halfOffScore.accuracy)
    }

    // MARK: - Combined Deviations

    @Test
    func bothDeviationsReduceCompositeScore() {
        let perfectScore = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0
        )

        let combinedScore = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0.2,
            durationDeviation: 0.3
        )

        #expect(combinedScore.accuracy < perfectScore.accuracy)
        #expect(combinedScore.accuracy > 0)
    }

    // MARK: - Score Records Deviation Values

    @Test
    func scoreRecordsTimingDeviationInResult() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 5,
            timingDeviationSeconds: 0.15,
            durationDeviation: 0.25
        )

        #expect(score.timingDeviationSeconds == 0.15)
        #expect(score.durationDeviation == 0.25)
    }

    // MARK: - Weight Verification

    @Test
    func timingWeightIsThirtyPercent() {
        #expect(PracticeConstants.timingWeight == 0.30)
    }

    @Test
    func durationWeightIsTwentyPercent() {
        #expect(PracticeConstants.durationWeight == 0.20)
    }

    @Test
    func allWeightsSumToOne() {
        let total =
            PracticeConstants.pitchWeight
            + PracticeConstants.timingWeight
            + PracticeConstants.durationWeight
        #expect(abs(total - 1.0) < 0.001)
    }
}
