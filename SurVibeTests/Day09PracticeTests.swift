import Testing

@testable import SurVibe
import SVLearning

// MARK: - NoteGrade Tests

@MainActor
struct NoteGradeTests {

    // MARK: - Accuracy to Grade Mapping

    @Test func perfectFromHighAccuracy() {
        let grade = NoteGrade.from(accuracy: 0.95)
        #expect(grade == .perfect)
    }

    @Test func goodFromModerateAccuracy() {
        let grade = NoteGrade.from(accuracy: 0.80)
        #expect(grade == .good)
    }

    @Test func fairFromLowAccuracy() {
        let grade = NoteGrade.from(accuracy: 0.55)
        #expect(grade == .fair)
    }

    @Test func missFromVeryLowAccuracy() {
        let grade = NoteGrade.from(accuracy: 0.30)
        #expect(grade == .miss)
    }

    // MARK: - Boundary Values

    @Test func perfectAtExactBoundary() {
        let grade = NoteGrade.from(accuracy: 0.90)
        #expect(grade == .perfect)
    }

    @Test func goodAtExactBoundary() {
        let grade = NoteGrade.from(accuracy: 0.70)
        #expect(grade == .good)
    }

    @Test func fairAtExactBoundary() {
        let grade = NoteGrade.from(accuracy: 0.50)
        #expect(grade == .fair)
    }

    @Test func missFromZeroAccuracy() {
        let grade = NoteGrade.from(accuracy: 0.0)
        #expect(grade == .miss)
    }

    @Test func perfectFromFullAccuracy() {
        let grade = NoteGrade.from(accuracy: 1.0)
        #expect(grade == .perfect)
    }

    // MARK: - Clamping

    @Test func negativeAccuracyClampsToMiss() {
        let grade = NoteGrade.from(accuracy: -0.5)
        #expect(grade == .miss)
    }

    @Test func excessiveAccuracyClampsToPerfect() {
        let grade = NoteGrade.from(accuracy: 1.5)
        #expect(grade == .perfect)
    }

    // MARK: - Properties

    @Test func allCasesHaveNonEmptySFSymbol() {
        for grade in NoteGrade.allCases {
            #expect(!grade.sfSymbol.isEmpty, "Grade \(grade.rawValue) has empty sfSymbol")
        }
    }

    @Test func allCasesHaveNonEmptyRawValue() {
        for grade in NoteGrade.allCases {
            #expect(!grade.rawValue.isEmpty, "Grade has empty rawValue")
        }
    }

    // MARK: - Comparable

    @Test func perfectIsLessThanGoodInComparableOrdering() {
        // Comparable uses lhs.minimumPercentage > rhs.minimumPercentage
        // perfect.minimumPercentage (0.90) > good.minimumPercentage (0.70) = true
        // So .perfect < .good evaluates to true
        #expect(NoteGrade.perfect < NoteGrade.good)
    }

    @Test func goodIsLessThanFairInComparableOrdering() {
        // good.minimumPercentage (0.70) > fair.minimumPercentage (0.50) = true
        #expect(NoteGrade.good < NoteGrade.fair)
    }

    @Test func fairIsLessThanMissInComparableOrdering() {
        // fair.minimumPercentage (0.50) > miss.minimumPercentage (0.0) = true
        #expect(NoteGrade.fair < NoteGrade.miss)
    }

    @Test func missIsNotLessThanPerfect() {
        // miss.minimumPercentage (0.0) > perfect.minimumPercentage (0.90) = false
        #expect(!(NoteGrade.miss < NoteGrade.perfect))
    }

    @Test func perfectIsNotGreaterThanMiss() {
        // In this ordering, perfect < good < fair < miss, so perfect > miss is false
        #expect(!(NoteGrade.perfect > NoteGrade.miss))
    }
}

// MARK: - NoteScoreCalculator Tests

@MainActor
struct NoteScoreCalculatorTests {

    @Test func perfectScoreFromZeroDeviations() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0
        )
        #expect(score.accuracy == 1.0)
        #expect(score.grade == .perfect)
    }

    @Test func goodScoreFromModerateDeviations() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Re",
            detectedNote: "Re",
            pitchDeviationCents: 20,
            timingDeviationSeconds: 0.2,
            durationDeviation: 0.2
        )
        #expect(score.accuracy > 0.70)
        #expect(score.accuracy < 0.90)
        #expect(score.grade == .good)
    }

    @Test func fairScoreFromLargeDeviations() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Ga",
            detectedNote: "Ga",
            pitchDeviationCents: 40,
            timingDeviationSeconds: 0.4,
            durationDeviation: 0.4
        )
        #expect(score.accuracy >= 0.40)
        #expect(score.accuracy <= 0.65)
    }

    @Test func missedNoteHasZeroAccuracyAndMissGrade() {
        let score = NoteScoreCalculator.missedNote(expectedNote: "Pa")
        #expect(score.grade == .miss)
        #expect(score.accuracy == 0.0)
        #expect(score.detectedNote == nil)
    }

    @Test func missedNotePreservesExpectedNote() {
        let score = NoteScoreCalculator.missedNote(expectedNote: "Dha")
        #expect(score.expectedNote == "Dha")
    }

    @Test func pitchWeightDominatesComposite() {
        // Perfect pitch only, worst timing and duration
        // pitch=0 -> pitchAccuracy=1.0, timing=100s -> 0.0, duration=100 -> 0.0
        // composite = 1.0 * 0.50 + 0.0 * 0.30 + 0.0 * 0.20 = 0.50
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 100,
            durationDeviation: 100
        )
        #expect(score.accuracy == 0.50)
    }

    @Test func deviationsArePreservedInResult() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Ma",
            detectedNote: "Ma",
            pitchDeviationCents: 15.5,
            timingDeviationSeconds: 0.12,
            durationDeviation: 0.25
        )
        #expect(score.pitchDeviationCents == 15.5)
        #expect(score.timingDeviationSeconds == 0.12)
        #expect(score.durationDeviation == 0.25)
    }

    @Test func expectedAndDetectedNotesArePreserved() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Ni",
            detectedNote: "Komal Ni",
            pitchDeviationCents: 30,
            timingDeviationSeconds: 0.1,
            durationDeviation: 0.1
        )
        #expect(score.expectedNote == "Ni")
        #expect(score.detectedNote == "Komal Ni")
    }
}

// MARK: - PracticeScoring Tests

@MainActor
struct PracticeScoringTests {

    // MARK: - Helpers

    /// Creates a NoteScore with the given accuracy and grade for testing aggregate functions.
    private func makeScore(accuracy: Double, grade: NoteGrade = .perfect) -> NoteScore {
        NoteScore(
            grade: grade,
            accuracy: accuracy,
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            expectedNote: "Sa"
        )
    }

    // MARK: - Star Rating

    @Test func fiveStarsFromHighAccuracy() {
        #expect(PracticeScoring.starRating(accuracy: 0.95) == 5)
    }

    @Test func fourStarsFromGoodAccuracy() {
        #expect(PracticeScoring.starRating(accuracy: 0.80) == 4)
    }

    @Test func threeStarsFromModerateAccuracy() {
        #expect(PracticeScoring.starRating(accuracy: 0.65) == 3)
    }

    @Test func twoStarsFromLowAccuracy() {
        #expect(PracticeScoring.starRating(accuracy: 0.45) == 2)
    }

    @Test func oneStarFromVeryLowAccuracy() {
        #expect(PracticeScoring.starRating(accuracy: 0.20) == 1)
    }

    @Test func fiveStarsAtExactBoundary() {
        #expect(PracticeScoring.starRating(accuracy: 0.90) == 5)
    }

    @Test func fourStarsAtExactBoundary() {
        #expect(PracticeScoring.starRating(accuracy: 0.75) == 4)
    }

    @Test func threeStarsAtExactBoundary() {
        #expect(PracticeScoring.starRating(accuracy: 0.60) == 3)
    }

    @Test func twoStarsAtExactBoundary() {
        #expect(PracticeScoring.starRating(accuracy: 0.40) == 2)
    }

    @Test func negativeAccuracyClampsToOneStar() {
        #expect(PracticeScoring.starRating(accuracy: -0.5) == 1)
    }

    @Test func excessiveAccuracyClampsToFiveStars() {
        #expect(PracticeScoring.starRating(accuracy: 1.5) == 5)
    }

    // MARK: - XP Earned

    @Test func perfectAccuracyDifficultyOneXP() {
        // accuracyMultiplier = 1.0 + 1.0 * 2.0 = 3.0
        // difficultyMultiplier = 1.0 + 0 * 0.25 = 1.0
        // xp = Int(10 * 3.0 * 1.0) = 30
        let xp = PracticeScoring.xpEarned(accuracy: 1.0, difficulty: 1)
        #expect(xp == 30)
    }

    @Test func zeroAccuracyDifficultyOneXP() {
        // accuracyMultiplier = 1.0 + 0.0 * 2.0 = 1.0
        // difficultyMultiplier = 1.0
        // xp = Int(10 * 1.0 * 1.0) = 10
        let xp = PracticeScoring.xpEarned(accuracy: 0.0, difficulty: 1)
        #expect(xp == 10)
    }

    @Test func higherDifficultyYieldsMoreXP() {
        let xpDifficulty1 = PracticeScoring.xpEarned(accuracy: 0.80, difficulty: 1)
        let xpDifficulty5 = PracticeScoring.xpEarned(accuracy: 0.80, difficulty: 5)
        #expect(xpDifficulty5 > xpDifficulty1)
    }

    // MARK: - Longest Streak

    @Test func longestStreakWithMixedGrades() {
        // [perfect, good, fair, miss, perfect, perfect] -> streak of 3 (first 3), then 2
        let grades: [NoteGrade] = [.perfect, .good, .fair, .miss, .perfect, .perfect]
        #expect(PracticeScoring.longestStreak(grades: grades) == 3)
    }

    @Test func longestStreakAllMisses() {
        let grades: [NoteGrade] = [.miss, .miss, .miss]
        #expect(PracticeScoring.longestStreak(grades: grades) == 0)
    }

    @Test func longestStreakEmpty() {
        #expect(PracticeScoring.longestStreak(grades: []) == 0)
    }

    @Test func longestStreakNoMisses() {
        let grades: [NoteGrade] = [.perfect, .good, .fair, .good, .perfect]
        #expect(PracticeScoring.longestStreak(grades: grades) == 5)
    }

    // MARK: - Average Accuracy

    @Test func averageAccuracyEmpty() {
        #expect(PracticeScoring.averageAccuracy(scores: []) == 0.0)
    }

    @Test func averageAccuracySingleScore() {
        let scores = [makeScore(accuracy: 0.75)]
        #expect(PracticeScoring.averageAccuracy(scores: scores) == 0.75)
    }

    @Test func averageAccuracyMultipleScores() {
        let scores = [
            makeScore(accuracy: 1.0),
            makeScore(accuracy: 0.5),
        ]
        #expect(PracticeScoring.averageAccuracy(scores: scores) == 0.75)
    }

    // MARK: - Grade Counts

    @Test func gradeCountsAreCorrect() {
        let scores = [
            makeScore(accuracy: 0.95, grade: .perfect),
            makeScore(accuracy: 0.95, grade: .perfect),
            makeScore(accuracy: 0.80, grade: .good),
            makeScore(accuracy: 0.55, grade: .fair),
            makeScore(accuracy: 0.10, grade: .miss),
            makeScore(accuracy: 0.10, grade: .miss),
            makeScore(accuracy: 0.10, grade: .miss),
        ]
        let counts = PracticeScoring.gradeCounts(scores: scores)
        #expect(counts[.perfect] == 2)
        #expect(counts[.good] == 1)
        #expect(counts[.fair] == 1)
        #expect(counts[.miss] == 3)
    }

    @Test func gradeCountsIncludesAllGradesEvenIfZero() {
        let scores = [makeScore(accuracy: 0.95, grade: .perfect)]
        let counts = PracticeScoring.gradeCounts(scores: scores)
        #expect(counts[.perfect] == 1)
        #expect(counts[.good] == 0)
        #expect(counts[.fair] == 0)
        #expect(counts[.miss] == 0)
    }
}

// MARK: - SectionScorer Tests

@MainActor
struct Day09SectionScorerTests {

    // MARK: - Helpers

    /// Creates a NoteScore with the given accuracy and grade for testing section scoring.
    private func makeScore(accuracy: Double, grade: NoteGrade = .perfect) -> NoteScore {
        NoteScore(
            grade: grade,
            accuracy: accuracy,
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            expectedNote: "Sa"
        )
    }

    // MARK: - Section Splitting

    @Test func emptyScoresProduceEmptySections() {
        let sections = SectionScorer.scoreSections(scores: [])
        #expect(sections.isEmpty)
    }

    @Test func fourScoresProduceOneSection() {
        let scores = [
            makeScore(accuracy: 1.0),
            makeScore(accuracy: 0.8),
            makeScore(accuracy: 0.6),
            makeScore(accuracy: 0.4),
        ]
        let sections = SectionScorer.scoreSections(scores: scores, sectionSize: 4)
        #expect(sections.count == 1)
        #expect(sections[0].noteScores.count == 4)
    }

    @Test func eightScoresProduceTwoSections() {
        let scores = (0..<8).map { _ in makeScore(accuracy: 0.80) }
        let sections = SectionScorer.scoreSections(scores: scores, sectionSize: 4)
        #expect(sections.count == 2)
        #expect(sections[0].noteScores.count == 4)
        #expect(sections[1].noteScores.count == 4)
    }

    @Test func unevenScoresProducePartialLastSection() {
        let scores = (0..<5).map { _ in makeScore(accuracy: 0.80) }
        let sections = SectionScorer.scoreSections(scores: scores, sectionSize: 4)
        #expect(sections.count == 2)
        #expect(sections[0].noteScores.count == 4)
        #expect(sections[1].noteScores.count == 1)
    }

    @Test func sectionAccuracyMatchesAverageOfNotes() {
        let scores = [
            makeScore(accuracy: 1.0),
            makeScore(accuracy: 0.8),
            makeScore(accuracy: 0.6),
            makeScore(accuracy: 0.4),
        ]
        let sections = SectionScorer.scoreSections(scores: scores, sectionSize: 4)
        let expectedAverage = (1.0 + 0.8 + 0.6 + 0.4) / 4.0
        #expect(sections[0].accuracy == expectedAverage)
    }

    @Test func sectionNoteRangeIsCorrect() {
        let scores = (0..<8).map { _ in makeScore(accuracy: 0.80) }
        let sections = SectionScorer.scoreSections(scores: scores, sectionSize: 4)
        #expect(sections[0].noteRange == 0..<4)
        #expect(sections[1].noteRange == 4..<8)
    }

    @Test func sectionIndexIsSequential() {
        let scores = (0..<12).map { _ in makeScore(accuracy: 0.80) }
        let sections = SectionScorer.scoreSections(scores: scores, sectionSize: 4)
        for (index, section) in sections.enumerated() {
            #expect(section.sectionIndex == index)
        }
    }

    // MARK: - Weakest First Sorting

    @Test func weakestFirstSortsByAccuracyAscending() {
        let scores = [
            makeScore(accuracy: 1.0),
            makeScore(accuracy: 1.0),
            makeScore(accuracy: 1.0),
            makeScore(accuracy: 1.0),
            makeScore(accuracy: 0.3),
            makeScore(accuracy: 0.3),
            makeScore(accuracy: 0.3),
            makeScore(accuracy: 0.3),
            makeScore(accuracy: 0.7),
            makeScore(accuracy: 0.7),
            makeScore(accuracy: 0.7),
            makeScore(accuracy: 0.7),
        ]
        let sections = SectionScorer.scoreSections(scores: scores, sectionSize: 4)
        let sorted = SectionScorer.weakestFirst(sections: sections)

        #expect(sorted.count == 3)
        #expect(sorted[0].accuracy < sorted[1].accuracy)
        #expect(sorted[1].accuracy < sorted[2].accuracy)
    }

    @Test func defaultSectionSizeIsFour() {
        #expect(SectionScorer.defaultSectionSize == 4)
    }
}
