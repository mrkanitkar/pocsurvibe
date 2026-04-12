import Testing
@testable import SVAudio
@testable import SVLearning

@MainActor
struct RagaScoringTests {
    // MARK: - RagaScoringContext Tests

    @Test func ragaScoringContextFromValidRaga() {
        let context = RagaScoringContext.from(ragaName: "Yaman")
        #expect(context != nil)
        #expect(context?.ragaName == "Yaman")
        #expect(context?.allowedSwars.contains("Tivra Ma") == true)
        #expect(context?.allowedSwars.contains("Ma") == false)
    }

    @Test func ragaScoringContextReturnsNilForEmptyRaga() {
        #expect(RagaScoringContext.from(ragaName: "") == nil)
    }

    @Test func ragaScoringContextReturnsNilForUnknownRaga() {
        #expect(RagaScoringContext.from(ragaName: "UnknownRaga") == nil)
    }

    @Test func ragaScoringContextIsNoteInRaga() {
        let context = RagaScoringContext.from(ragaName: "Yaman")!
        #expect(context.isNoteInRaga("Sa"))
        #expect(context.isNoteInRaga("Tivra Ma"))
        #expect(!context.isNoteInRaga("Ma"))
        #expect(!context.isNoteInRaga("Komal Re"))
    }

    // MARK: - NoteScoreCalculator Without Raga Context

    @Test func scoringWithoutRagaContextIsUnchanged() {
        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 5.0,
            timingDeviationSeconds: 0.05,
            durationDeviation: 0.1
        )
        #expect(score.accuracy > 0.8)
        #expect(score.isOutOfRaga == nil)
    }

    // MARK: - NoteScoreCalculator With Raga Context

    @Test func ragaContextUsesJICentsDeviation() {
        let ragaContext = RagaScoringContext.from(ragaName: "Yaman")!

        // Scenario: 12ET says 20¢ off, but JI says only 5¢ off
        // With raga context, the JI cents should be used → higher score
        let scoreWithRaga = NoteScoreCalculator.score(
            expectedNote: "Tivra Ma",
            detectedNote: "Tivra Ma",
            pitchDeviationCents: 20.0,
            timingDeviationSeconds: 0.05,
            durationDeviation: 0.1,
            ragaPitchDeviationCents: 5.0,
            ragaContext: ragaContext
        )

        let scoreWithout = NoteScoreCalculator.score(
            expectedNote: "Tivra Ma",
            detectedNote: "Tivra Ma",
            pitchDeviationCents: 20.0,
            timingDeviationSeconds: 0.05,
            durationDeviation: 0.1
        )

        // Raga-aware score should be higher due to smaller JI deviation
        #expect(scoreWithRaga.accuracy > scoreWithout.accuracy)
        #expect(scoreWithRaga.isOutOfRaga == false)
    }

    @Test func outOfRagaNoteGetsPenalized() {
        let ragaContext = RagaScoringContext.from(ragaName: "Yaman")!

        // Play shuddh Ma in Yaman — should be penalized
        let score = NoteScoreCalculator.score(
            expectedNote: "Tivra Ma",
            detectedNote: "Ma",
            pitchDeviationCents: 10.0,
            timingDeviationSeconds: 0.05,
            durationDeviation: 0.1,
            ragaContext: ragaContext
        )

        #expect(score.isOutOfRaga == true)
        // Pitch accuracy capped at 0.3, but composite = pitch*0.5 + timing*0.3 + duration*0.2
        // With good timing/duration, composite can exceed 0.5 — verify it's below uncapped score
        let uncappedScore = NoteScoreCalculator.score(
            expectedNote: "Tivra Ma", detectedNote: "Tivra Ma",
            pitchDeviationCents: 10.0, timingDeviationSeconds: 0.05,
            durationDeviation: 0.1
        )
        #expect(score.accuracy < uncappedScore.accuracy,
                "Out-of-raga note should score lower than in-raga note")
    }

    @Test func inRagaNoteNotPenalized() {
        let ragaContext = RagaScoringContext.from(ragaName: "Yaman")!

        let score = NoteScoreCalculator.score(
            expectedNote: "Sa",
            detectedNote: "Sa",
            pitchDeviationCents: 3.0,
            timingDeviationSeconds: 0.02,
            durationDeviation: 0.05,
            ragaPitchDeviationCents: 2.0,
            ragaContext: ragaContext
        )

        #expect(score.isOutOfRaga == false)
        #expect(score.accuracy > 0.8)
    }

    @Test func missedNoteHasNilOutOfRaga() {
        let score = NoteScoreCalculator.missedNote(expectedNote: "Sa")
        #expect(score.isOutOfRaga == nil)
    }

    // MARK: - NoteScore Model

    @Test func noteScoreDefaultIsOutOfRagaIsNil() {
        let score = NoteScore(
            grade: .perfect,
            accuracy: 1.0,
            pitchDeviationCents: 0,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            expectedNote: "Sa"
        )
        #expect(score.isOutOfRaga == nil)
    }

    @Test func noteScorePreservesIsOutOfRaga() {
        let score = NoteScore(
            grade: .miss,
            accuracy: 0.3,
            pitchDeviationCents: 10,
            timingDeviationSeconds: 0.1,
            durationDeviation: 0.2,
            expectedNote: "Tivra Ma",
            detectedNote: "Ma",
            isOutOfRaga: true
        )
        #expect(score.isOutOfRaga == true)
    }
}
