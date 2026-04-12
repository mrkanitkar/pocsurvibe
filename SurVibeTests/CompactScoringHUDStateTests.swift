import Testing

@testable import SurVibe

// MARK: - Accuracy Formatting Tests

@MainActor
struct CompactScoringHUDAccuracyTests {

    @Test func zeroAccuracyFormatsAsZeroPercent() {
        #expect(CompactScoringHUD.formatAccuracy(0.0) == "0%")
    }

    @Test func fullAccuracyFormatsAs100Percent() {
        #expect(CompactScoringHUD.formatAccuracy(1.0) == "100%")
    }

    @Test func midAccuracyRoundsToNearestPercent() {
        // 0.856 * 100 = 85.6, rounds to 86
        #expect(CompactScoringHUD.formatAccuracy(0.856) == "86%")
    }

    @Test func halfAccuracyFormatsAs50Percent() {
        #expect(CompactScoringHUD.formatAccuracy(0.5) == "50%")
    }

    @Test func lowAccuracyFormatsCorrectly() {
        // 0.123 * 100 = 12.3, rounds to 12
        #expect(CompactScoringHUD.formatAccuracy(0.123) == "12%")
    }

    @Test func accuracyBelowZeroClampsToZero() {
        #expect(CompactScoringHUD.formatAccuracy(-0.5) == "0%")
    }

    @Test func accuracyAboveOneClampsTo100() {
        #expect(CompactScoringHUD.formatAccuracy(1.5) == "100%")
    }

    @Test func verySmallAccuracyRoundsDown() {
        // 0.004 * 100 = 0.4, rounds to 0
        #expect(CompactScoringHUD.formatAccuracy(0.004) == "0%")
    }

    @Test func nearPerfectAccuracyRoundsUp() {
        // 0.999 * 100 = 99.9, rounds to 100
        #expect(CompactScoringHUD.formatAccuracy(0.999) == "100%")
    }

    @Test func oneThirdAccuracyFormatsAs33Percent() {
        // 1.0 / 3.0 = 0.3333..., * 100 = 33.33, rounds to 33
        #expect(CompactScoringHUD.formatAccuracy(1.0 / 3.0) == "33%")
    }
}

// MARK: - Progress Fraction Tests

@MainActor
struct CompactScoringHUDProgressTests {

    @Test func progressFractionWithZeroTotalReturnsZero() {
        let fraction = CompactScoringHUD.progressFraction(notesHit: 0, totalNotes: 0)
        #expect(fraction == 0.0)
    }

    @Test func progressFractionWithAllHitsReturnsOne() {
        let fraction = CompactScoringHUD.progressFraction(notesHit: 50, totalNotes: 50)
        #expect(fraction == 1.0)
    }

    @Test func progressFractionWithNoHitsReturnsZero() {
        let fraction = CompactScoringHUD.progressFraction(notesHit: 0, totalNotes: 50)
        #expect(fraction == 0.0)
    }

    @Test func progressFractionPartialHits() {
        let fraction = CompactScoringHUD.progressFraction(notesHit: 25, totalNotes: 50)
        #expect(abs(fraction - 0.5) < 0.001)
    }

    @Test func progressFractionSmallValues() {
        let fraction = CompactScoringHUD.progressFraction(notesHit: 1, totalNotes: 3)
        #expect(abs(fraction - 1.0 / 3.0) < 0.001)
    }

    @Test func progressFractionSingleNote() {
        let fraction = CompactScoringHUD.progressFraction(notesHit: 1, totalNotes: 1)
        #expect(fraction == 1.0)
    }
}
