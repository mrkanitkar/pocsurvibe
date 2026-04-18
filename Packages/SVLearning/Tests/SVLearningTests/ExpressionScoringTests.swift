import SVAudio
import Testing

@testable import SVLearning

/// Tests for expression-aware scoring in NoteScoreCalculator.
///
/// Validates that detected and expected expression types influence
/// the composite accuracy via the expression weight component.
///
/// Weight formulas verified:
/// - Expression only (no dynamics): 45% pitch + 25% timing + 15% duration + 15% expression
/// - Expression + dynamics: 40% pitch + 25% timing + 15% duration + 10% dynamics + 10% expression
/// - No expression: standard 50% pitch + 30% timing + 20% duration
@Suite("Expression Scoring")
struct ExpressionScoringTests {

    @Test("exact expression match produces maximum accuracy")
    func exactMatch() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            detectedExpression: .gamaka,
            expectedExpression: .gamaka
        )
        // All components = 1.0 -> composite = 1.0
        #expect(score.accuracy > 0.95)
    }

    @Test("related expression (vibrato for gamaka) gets partial credit")
    func relatedExpression() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Ga",
            detectedNote: "Ga",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            detectedExpression: .vibrato,
            expectedExpression: .gamaka
        )
        // vibrato for gamaka = 0.5 partial credit
        // Formula: 0.45*1.0 + 0.25*1.0 + 0.15*1.0 + 0.15*0.5 = 0.925
        #expect(score.accuracy > 0.90)
        #expect(score.accuracy < 1.0)
    }

    @Test("no expression markers uses standard 3-component formula")
    func noExpressionBackwardCompat() {
        let without = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 5,
            timingDeviationSeconds: 0.02,
            durationDeviation: 0.05
        )
        let alsoWithout = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 5,
            timingDeviationSeconds: 0.02,
            durationDeviation: 0.05,
            detectedExpression: nil,
            expectedExpression: nil
        )
        #expect(without.accuracy == alsoWithout.accuracy)
    }

    @Test("expression with dynamics uses 5-component formula")
    func expressionWithDynamics() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Pa",
            detectedNote: "Pa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            playedVelocity: 80,
            expectedVelocity: 80,
            detectedExpression: .gamaka,
            expectedExpression: .gamaka
        )
        // All 5 components = 1.0 -> composite = 1.0
        #expect(score.accuracy > 0.95)
    }

    @Test("stable when gamaka expected gets low partial credit")
    func missingExpression() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Re",
            detectedNote: "Re",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            detectedExpression: .stable,
            expectedExpression: .gamaka
        )
        // stable for gamaka = 0.2 partial credit
        // Formula: 0.45*1.0 + 0.25*1.0 + 0.15*1.0 + 0.15*0.2 = 0.88
        #expect(score.accuracy > 0.80)
        #expect(score.accuracy < 0.95)
    }

    @Test("meend when gamaka expected gets moderate partial credit")
    func wrongButExpressive() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Ga",
            detectedNote: "Ga",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            detectedExpression: .meend,
            expectedExpression: .gamaka
        )
        // meend for gamaka = 0.3 partial credit
        // Formula: 0.45*1.0 + 0.25*1.0 + 0.15*1.0 + 0.15*0.3 = 0.895
        #expect(score.accuracy > 0.85)
        #expect(score.accuracy < 0.95)
    }

    @Test("indeterminate expression gets minimal credit")
    func indeterminateExpression() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Ma",
            detectedNote: "Ma",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            detectedExpression: .indeterminate,
            expectedExpression: .gamaka
        )
        // indeterminate = 0.1 partial credit
        // Formula: 0.45*1.0 + 0.25*1.0 + 0.15*1.0 + 0.15*0.1 = 0.865
        #expect(score.accuracy > 0.80)
        #expect(score.accuracy < 0.90)
    }

    @Test("only detected expression without expected does not activate expression scoring")
    func onlyDetectedNoExpected() {
        let withDetectedOnly = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            detectedExpression: .gamaka,
            expectedExpression: nil
        )
        let standard = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0
        )
        // Expression scoring only activates when BOTH detected AND expected are present
        #expect(withDetectedOnly.accuracy == standard.accuracy)
    }
}
