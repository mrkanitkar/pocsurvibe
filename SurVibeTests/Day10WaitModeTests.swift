import Testing

@testable import SurVibe
import SVLearning

// MARK: - WaitModeConfiguration Tests

@MainActor
struct WaitModeConfigurationTests {
    @Test func defaultConfigurationValues() {
        let config = WaitModeConfiguration()

        #expect(config.isEnabled == false)
        #expect(config.waitCriteria == .correctPitch)
        #expect(config.patienceSeconds == 10.0)
        #expect(config.pitchToleranceCents == 25.0)
    }

    @Test func customConfigurationRetainsAllValues() {
        let config = WaitModeConfiguration(
            isEnabled: true,
            waitCriteria: .withinTolerance,
            patienceSeconds: 5.0,
            pitchToleranceCents: 50.0
        )

        #expect(config.isEnabled == true)
        #expect(config.waitCriteria == .withinTolerance)
        #expect(config.patienceSeconds == 5.0)
        #expect(config.pitchToleranceCents == 50.0)
    }

    @Test func identicalConfigurationsAreEqual() {
        let configA = WaitModeConfiguration(
            isEnabled: true,
            waitCriteria: .withinTolerance,
            patienceSeconds: 8.0,
            pitchToleranceCents: 30.0
        )
        let configB = WaitModeConfiguration(
            isEnabled: true,
            waitCriteria: .withinTolerance,
            patienceSeconds: 8.0,
            pitchToleranceCents: 30.0
        )

        #expect(configA == configB)
    }

    @Test func differentConfigurationsAreNotEqual() {
        let configA = WaitModeConfiguration(
            isEnabled: true,
            waitCriteria: .correctPitch,
            patienceSeconds: 10.0,
            pitchToleranceCents: 25.0
        )
        let configB = WaitModeConfiguration(
            isEnabled: false,
            waitCriteria: .withinTolerance,
            patienceSeconds: 5.0,
            pitchToleranceCents: 50.0
        )

        #expect(configA != configB)
    }

    @Test func allWaitCriteriaCasesExist() {
        let cases = WaitCriteria.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.correctPitch))
        #expect(cases.contains(.withinTolerance))
        #expect(cases.contains(.pitchAndDuration))
    }
}

// MARK: - WaitModeEngine Tests

@MainActor
struct WaitModeEngineTests {
    @Test @MainActor func initialStateIsIdle() {
        let engine = WaitModeEngine()

        #expect(engine.state == .idle)
        #expect(engine.correctOnFirstAttempt == 0)
        #expect(engine.skippedCount == 0)
        #expect(engine.totalAttempts == 0)
    }

    @Test @MainActor func waitForNoteTransitionsToWaiting() {
        let engine = WaitModeEngine(
            configuration: WaitModeConfiguration(patienceSeconds: 0)
        )

        engine.waitForNote()

        #expect(engine.state == .waiting)
    }

    @Test @MainActor func correctAttemptTransitionsToAdvancing() {
        let engine = WaitModeEngine(
            configuration: WaitModeConfiguration(patienceSeconds: 0)
        )
        engine.waitForNote()

        engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )

        #expect(engine.state == .advancing)
    }

    @Test @MainActor func correctAttemptReturnsTrue() {
        let engine = WaitModeEngine(
            configuration: WaitModeConfiguration(patienceSeconds: 0)
        )
        engine.waitForNote()

        let result = engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )

        #expect(result == true)
    }

    @Test @MainActor func incorrectAttemptStaysInWaitingAndReturnsFalse() {
        let engine = WaitModeEngine(
            configuration: WaitModeConfiguration(patienceSeconds: 0)
        )
        engine.waitForNote()

        let result = engine.evaluateAttempt(
            detectedNoteName: "Re",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )

        #expect(result == false)
        #expect(engine.state == .waiting)
    }

    @Test @MainActor func skipCurrentNoteTransitionsToSkippedAndIncrementsCount() {
        let engine = WaitModeEngine(
            configuration: WaitModeConfiguration(patienceSeconds: 0)
        )
        engine.waitForNote()

        engine.skipCurrentNote()

        #expect(engine.state == .skipped)
        #expect(engine.skippedCount == 1)
    }

    @Test @MainActor func skipCurrentNoteOnlyWorksFromWaitingState() {
        let engine = WaitModeEngine(
            configuration: WaitModeConfiguration(patienceSeconds: 0)
        )

        // State is .idle — skip should be a no-op
        engine.skipCurrentNote()
        #expect(engine.state == .idle)
        #expect(engine.skippedCount == 0)

        // Transition to advancing via correct attempt, then try skip
        engine.waitForNote()
        engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )
        #expect(engine.state == .advancing)

        engine.skipCurrentNote()
        #expect(engine.state == .advancing)
        #expect(engine.skippedCount == 0)
    }

    @Test @MainActor func resetReturnsToIdleAndZeroesAllCounters() {
        let engine = WaitModeEngine(
            configuration: WaitModeConfiguration(patienceSeconds: 0)
        )
        engine.waitForNote()
        engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )
        // Engine now has correctOnFirstAttempt=1, totalAttempts=1

        engine.waitForNote()
        engine.skipCurrentNote()
        // Engine now has skippedCount=1

        engine.reset()

        #expect(engine.state == .idle)
        #expect(engine.correctOnFirstAttempt == 0)
        #expect(engine.skippedCount == 0)
        #expect(engine.totalAttempts == 0)
    }

    @Test @MainActor func correctOnFirstAttemptIncrementsOnFirstCorrectTry() {
        let engine = WaitModeEngine(
            configuration: WaitModeConfiguration(patienceSeconds: 0)
        )
        engine.waitForNote()

        engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )

        #expect(engine.correctOnFirstAttempt == 1)
    }

    @Test @MainActor func correctOnFirstAttemptDoesNotIncrementAfterIncorrectAttempt() {
        let engine = WaitModeEngine(
            configuration: WaitModeConfiguration(patienceSeconds: 0)
        )
        engine.waitForNote()

        // First attempt is wrong
        engine.evaluateAttempt(
            detectedNoteName: "Re",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )

        // Second attempt is correct
        engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )

        #expect(engine.correctOnFirstAttempt == 0)
        #expect(engine.state == .advancing)
    }

    @Test @MainActor func totalAttemptsIncrementsOnEveryEvaluateAttemptCall() {
        let engine = WaitModeEngine(
            configuration: WaitModeConfiguration(patienceSeconds: 0)
        )
        engine.waitForNote()

        // Three incorrect attempts
        engine.evaluateAttempt(
            detectedNoteName: "Re",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )
        engine.evaluateAttempt(
            detectedNoteName: "Ga",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )
        engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )

        #expect(engine.totalAttempts == 3)
    }

    @Test @MainActor func evaluateAttemptReturnsFalseWhenNotInWaitingState() {
        let engine = WaitModeEngine(
            configuration: WaitModeConfiguration(patienceSeconds: 0)
        )

        // State is .idle
        let resultIdle = engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )
        #expect(resultIdle == false)
        #expect(engine.totalAttempts == 0)

        // Advance to .advancing state
        engine.waitForNote()
        engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )
        #expect(engine.state == .advancing)

        let resultAdvancing = engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )
        #expect(resultAdvancing == false)
        #expect(engine.totalAttempts == 1)
    }
}

// MARK: - Pitch Tolerance Tests (via WaitModeEngine)

@MainActor
struct PitchToleranceTests {
    @Test @MainActor func noteWithinToleranceIsCorrect() {
        let config = WaitModeConfiguration(
            isEnabled: true,
            waitCriteria: .withinTolerance,
            patienceSeconds: 0,
            pitchToleranceCents: 25.0
        )
        let engine = WaitModeEngine(configuration: config)
        engine.waitForNote()

        let result = engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 20.0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )

        #expect(result == true)
        #expect(engine.state == .advancing)
    }

    @Test @MainActor func noteOutsideToleranceIsIncorrect() {
        let config = WaitModeConfiguration(
            isEnabled: true,
            waitCriteria: .withinTolerance,
            patienceSeconds: 0,
            pitchToleranceCents: 25.0
        )
        let engine = WaitModeEngine(configuration: config)
        engine.waitForNote()

        let result = engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 30.0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )

        #expect(result == false)
        #expect(engine.state == .waiting)
    }

    @Test @MainActor func noteAtExactBoundaryIsCorrect() {
        let config = WaitModeConfiguration(
            isEnabled: true,
            waitCriteria: .withinTolerance,
            patienceSeconds: 0,
            pitchToleranceCents: 25.0
        )
        let engine = WaitModeEngine(configuration: config)
        engine.waitForNote()

        let result = engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: 25.0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )

        #expect(result == true)
        #expect(engine.state == .advancing)
    }

    @Test @MainActor func noteNameMismatchEvenWithinToleranceIsIncorrect() {
        let config = WaitModeConfiguration(
            isEnabled: true,
            waitCriteria: .withinTolerance,
            patienceSeconds: 0,
            pitchToleranceCents: 25.0
        )
        let engine = WaitModeEngine(configuration: config)
        engine.waitForNote()

        let result = engine.evaluateAttempt(
            detectedNoteName: "Re",
            detectedOctave: 4,
            detectedCents: 5.0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )

        #expect(result == false)
        #expect(engine.state == .waiting)
    }

    @Test @MainActor func negativeCentsOffsetWithinToleranceIsCorrect() {
        let config = WaitModeConfiguration(
            isEnabled: true,
            waitCriteria: .withinTolerance,
            patienceSeconds: 0,
            pitchToleranceCents: 25.0
        )
        let engine = WaitModeEngine(configuration: config)
        engine.waitForNote()

        let result = engine.evaluateAttempt(
            detectedNoteName: "Sa",
            detectedOctave: 4,
            detectedCents: -20.0,
            expectedNoteName: "Sa",
            expectedOctave: 4
        )

        #expect(result == true)
        #expect(engine.state == .advancing)
    }
}

// MARK: - SectionScorer Wait Mode Integration Tests

@MainActor
struct SectionScorerWaitModeTests {
    @Test func customSectionSizeProducesCorrectSections() {
        let scores = (0..<6).map { _ in makeScore(accuracy: 0.80) }

        let sections = SectionScorer.scoreSections(scores: scores, sectionSize: 2)

        #expect(sections.count == 3)
        #expect(sections[0].noteRange == 0..<2)
        #expect(sections[1].noteRange == 2..<4)
        #expect(sections[2].noteRange == 4..<6)
    }

    @Test func singleScoreReturnsSingleSection() {
        let scores = [makeScore(accuracy: 0.75)]

        let sections = SectionScorer.scoreSections(scores: scores)

        #expect(sections.count == 1)
        #expect(sections[0].noteRange == 0..<1)
        #expect(sections[0].noteScores.count == 1)
    }

    @Test func sectionGradeMatchesAverageAccuracy() {
        let scores = [
            makeScore(accuracy: 0.95),
            makeScore(accuracy: 0.92),
            makeScore(accuracy: 0.91),
            makeScore(accuracy: 0.90),
        ]

        let sections = SectionScorer.scoreSections(scores: scores)

        #expect(sections.count == 1)
        #expect(sections[0].grade == .perfect)
    }

    @Test func weakestFirstPreservesSectionIdentity() {
        let lowScores = (0..<4).map { _ in makeScore(accuracy: 0.30) }
        let highScores = (0..<4).map { _ in makeScore(accuracy: 0.90) }

        let allScores = highScores + lowScores
        let sections = SectionScorer.scoreSections(scores: allScores)
        let sorted = SectionScorer.weakestFirst(sections: sections)

        // The weakest section (index 1, accuracy 0.30) should come first
        #expect(sorted[0].sectionIndex == 1)
        #expect(sorted[1].sectionIndex == 0)
    }

    @Test func sectionAccuracyIsAverageOfNoteScores() {
        let scores = [
            makeScore(accuracy: 0.60),
            makeScore(accuracy: 0.80),
            makeScore(accuracy: 1.00),
            makeScore(accuracy: 0.60),
        ]

        let sections = SectionScorer.scoreSections(scores: scores)

        #expect(sections.count == 1)
        let expected = 0.75
        #expect(abs(sections[0].accuracy - expected) < 0.001)
    }

    // MARK: - Helpers

    private func makeScore(accuracy: Double) -> NoteScore {
        NoteScore(
            grade: NoteGrade.from(accuracy: accuracy),
            accuracy: accuracy,
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            expectedNote: "Sa"
        )
    }
}

// MARK: - PracticeDifficultyAdvisor Tests

@MainActor
struct PracticeDifficultyAdvisorTests {
    @Test func fewerThanTwoSessionsReturnsKeepPracticing() {
        let advice = PracticeDifficultyAdvisor.advise(
            recentAccuracies: [0.50],
            currentDifficulty: 3,
            waitModeEnabled: false
        )

        #expect(advice.suggestedAction == .keepPracticing)
    }

    @Test func noSessionsReturnsKeepPracticing() {
        let advice = PracticeDifficultyAdvisor.advise(
            recentAccuracies: [],
            currentDifficulty: 3,
            waitModeEnabled: false
        )

        #expect(advice.suggestedAction == .keepPracticing)
    }

    @Test func highAccuracyBelowMaxDifficultySuggestsTryHarder() {
        let advice = PracticeDifficultyAdvisor.advise(
            recentAccuracies: [0.95, 0.92],
            currentDifficulty: 3,
            waitModeEnabled: false
        )

        #expect(advice.suggestedAction == .tryHarder)
    }

    @Test func highAccuracyAtMaxDifficultyDoesNotSuggestTryHarder() {
        // At difficulty 5, average 0.95 should not suggest tryHarder
        // because currentDifficulty is already at max
        let advice = PracticeDifficultyAdvisor.advise(
            recentAccuracies: [0.95, 0.95],
            currentDifficulty: 5,
            waitModeEnabled: false
        )

        #expect(advice.suggestedAction != .tryHarder)
    }

    @Test func lowAccuracyWithWaitModeDisabledSuggestsEnableWaitMode() {
        let advice = PracticeDifficultyAdvisor.advise(
            recentAccuracies: [0.20, 0.30],
            currentDifficulty: 3,
            waitModeEnabled: false
        )

        #expect(advice.suggestedAction == .enableWaitMode)
    }

    @Test func lowAccuracyWithWaitModeEnabledAboveMinDifficultySuggestsTryEasier() {
        let advice = PracticeDifficultyAdvisor.advise(
            recentAccuracies: [0.20, 0.30],
            currentDifficulty: 3,
            waitModeEnabled: true
        )

        #expect(advice.suggestedAction == .tryEasier)
    }

    @Test func lowAccuracyWithWaitModeEnabledAtMinDifficultySuggestsRepeatSong() {
        let advice = PracticeDifficultyAdvisor.advise(
            recentAccuracies: [0.20, 0.30],
            currentDifficulty: 1,
            waitModeEnabled: true
        )

        #expect(advice.suggestedAction == .repeatSong)
    }

    @Test func improvingTrendSuggestsKeepPracticing() {
        // Average is below master but improving — should get keepPracticing
        let advice = PracticeDifficultyAdvisor.advise(
            recentAccuracies: [0.50, 0.65],
            currentDifficulty: 3,
            waitModeEnabled: false
        )

        #expect(advice.suggestedAction == .keepPracticing)
    }

    @Test func plateauBelowMasterySuggestsRepeatSong() {
        // Not improving (latest <= previous), average below mastery
        let advice = PracticeDifficultyAdvisor.advise(
            recentAccuracies: [0.70, 0.65],
            currentDifficulty: 3,
            waitModeEnabled: false
        )

        #expect(advice.suggestedAction == .repeatSong)
    }

    @Test func adviceMessageIsNotEmpty() {
        let advice = PracticeDifficultyAdvisor.advise(
            recentAccuracies: [0.50, 0.60],
            currentDifficulty: 2,
            waitModeEnabled: false
        )

        #expect(!advice.message.isEmpty)
    }
}
