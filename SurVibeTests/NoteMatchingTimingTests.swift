import Foundation
import SVLearning
import Testing

@testable import SurVibe

// MARK: - NoteMatchingActor Timing & Duration Tests

/// Tests for timing and duration deviation wiring in `NoteMatchingActor`.
///
/// Verifies that non-zero timing and duration deviations flow through
/// `evaluate()` into `NoteScoreCalculator.score()` and reduce the
/// composite accuracy in standard mode, while wait mode remains unaffected.
@MainActor
struct NoteMatchingTimingTests {

    // MARK: - Helpers

    /// Build a minimal NoteEvent for test purposes.
    private func makeEvent(
        midiNote: UInt8 = 60,
        swarName: String = "Sa",
        timestamp: TimeInterval = 1.0,
        duration: TimeInterval = 0.5
    ) -> NoteEvent {
        NoteEvent(
            id: UUID(),
            midiNote: midiNote,
            swarName: swarName,
            westernName: "C4",
            octave: 4,
            timestamp: timestamp,
            duration: duration,
            velocity: 100
        )
    }

    // MARK: - Standard Mode: Perfect Timing

    @Test
    func perfectTimingGivesHighAccuracy() async {
        let actor = NoteMatchingActor()
        let event = makeEvent()

        let diff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0,
            durationDeviation: 0
        )

        #expect(diff.newState == .correct)
        // With 0 deviation on all axes, accuracy should be 1.0 (perfect).
        #expect(diff.score?.accuracy == 1.0)
    }

    // MARK: - Standard Mode: Late Timing

    @Test
    func lateTimingReducesAccuracy() async {
        let actor = NoteMatchingActor()
        let event = makeEvent()

        let perfectDiff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0,
            durationDeviation: 0
        )

        let lateDiff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0.2,
            durationDeviation: 0
        )

        #expect(lateDiff.newState == .correct)
        let perfectAccuracy = perfectDiff.score?.accuracy ?? 0
        let lateAccuracy = lateDiff.score?.accuracy ?? 0
        // 0.2s deviation (between perfect 0.1s and good 0.25s) should reduce accuracy.
        #expect(lateAccuracy < perfectAccuracy)
    }

    // MARK: - Standard Mode: Very Late Timing

    @Test
    func veryLateTimingReducesAccuracyMore() async {
        let actor = NoteMatchingActor()
        let event = makeEvent()

        let slightlyLateDiff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0.2,
            durationDeviation: 0
        )

        let veryLateDiff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0.3,
            durationDeviation: 0
        )

        let slightlyLateAccuracy = slightlyLateDiff.score?.accuracy ?? 0
        let veryLateAccuracy = veryLateDiff.score?.accuracy ?? 0
        // 0.3s is worse than 0.2s.
        #expect(veryLateAccuracy < slightlyLateAccuracy)
    }

    // MARK: - Standard Mode: Duration Too Short

    @Test
    func shortDurationReducesAccuracy() async {
        let actor = NoteMatchingActor()
        let event = makeEvent()

        let perfectDiff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0,
            durationDeviation: 0
        )

        // 50% too short.
        let shortDiff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0,
            durationDeviation: 0.5
        )

        let perfectAccuracy = perfectDiff.score?.accuracy ?? 0
        let shortAccuracy = shortDiff.score?.accuracy ?? 0
        #expect(shortAccuracy < perfectAccuracy)
    }

    // MARK: - Standard Mode: Duration Too Long

    @Test
    func longDurationReducesAccuracyMore() async {
        let actor = NoteMatchingActor()
        let event = makeEvent()

        let halfOffDiff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0,
            durationDeviation: 0.5
        )

        // 100% too long.
        let doubleOffDiff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0,
            durationDeviation: 1.0
        )

        let halfOffAccuracy = halfOffDiff.score?.accuracy ?? 0
        let doubleOffAccuracy = doubleOffDiff.score?.accuracy ?? 0
        #expect(doubleOffAccuracy < halfOffAccuracy)
    }

    // MARK: - Wrong Note Keeps Zero Deviation

    @Test
    func wrongNoteKeepsZeroDeviation() async {
        let actor = NoteMatchingActor()
        let event = makeEvent(midiNote: 60)

        // Pass non-zero deviations — they should be ignored for wrong notes.
        let diff = await actor.evaluate(
            midiNote: 62,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0.3,
            durationDeviation: 0.5
        )

        #expect(diff.newState == .wrong)
        // Wrong note path hardcodes timingDeviationSeconds: 0, durationDeviation: 0.
        #expect(diff.score?.timingDeviationSeconds == 0)
        #expect(diff.score?.durationDeviation == 0)
    }

    // MARK: - Wait Mode Unaffected

    @Test
    func waitModeIgnoresTimingDeviation() async {
        let actor = NoteMatchingActor()
        let event = makeEvent(midiNote: 60)

        // Wait mode match with non-zero timing values — should be ignored.
        let diff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: true,
            timingDeviationSeconds: 0.5,
            durationDeviation: 0.8
        )

        #expect(diff.newState == .correct)
        // Wait mode hardcodes timingDeviationSeconds: 0, durationDeviation: 0.
        #expect(diff.score?.timingDeviationSeconds == 0)
        #expect(diff.score?.durationDeviation == 0)
    }

    // MARK: - Composite Score Decreases

    @Test
    func compositeScoreDecreasesWithBothDeviations() async {
        let actor = NoteMatchingActor()
        let event = makeEvent()

        let perfectDiff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0,
            durationDeviation: 0
        )

        let deviatedDiff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0.2,
            durationDeviation: 0.3
        )

        let perfectAccuracy = perfectDiff.score?.accuracy ?? 0
        let deviatedAccuracy = deviatedDiff.score?.accuracy ?? 0
        #expect(deviatedAccuracy < perfectAccuracy)
        // With timing 0.2s and duration 0.3, the composite should still be positive.
        #expect(deviatedAccuracy > 0)
    }

    // MARK: - Backward Compatibility

    @Test
    func defaultParametersPreserveExistingBehavior() async {
        let actor = NoteMatchingActor()
        let event = makeEvent()

        // Call without timing/duration parameters (uses defaults of 0).
        let defaultDiff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil
        )

        // Call with explicit zeros.
        let explicitDiff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0,
            durationDeviation: 0
        )

        #expect(defaultDiff.score?.accuracy == explicitDiff.score?.accuracy)
    }

    // MARK: - Score Records Deviation Values

    @Test
    func scoreRecordsTimingDeviationValue() async {
        let actor = NoteMatchingActor()
        let event = makeEvent()

        let diff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil,
            timingDeviationSeconds: 0.15,
            durationDeviation: 0.25
        )

        #expect(diff.score?.timingDeviationSeconds == 0.15)
        #expect(diff.score?.durationDeviation == 0.25)
    }
}
