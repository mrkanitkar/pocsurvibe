import Testing
import Foundation
@testable import SurVibe
import SVAudio
import SVLearning

// MARK: - NoteMatchingActor Tests

/// Tests for `NoteMatchingActor.evaluate()` — the off-main-actor scoring engine.
///
/// Verifies that scoring, state transitions, and streak outcomes are correct
/// for standard mode, wait mode, and edge cases.
@MainActor
struct NoteMatchingActorTests {

    // MARK: - Helpers

    /// Build a minimal NoteEvent for test purposes.
    private func makeEvent(midiNote: UInt8 = 60, swarName: String = "Sa") -> NoteEvent {
        NoteEvent(
            id: UUID(),
            midiNote: midiNote,
            swarName: swarName,
            westernName: "C4",
            octave: 4,
            timestamp: 0.0,
            duration: 0.5,
            velocity: 100
        )
    }

    // MARK: - Standard Mode: Correct Note

    @Test func correctNoteReturnsCorrectStateAndHit() async {
        let actor = NoteMatchingActor()
        let event = makeEvent(midiNote: 60)

        let diff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil
        )

        #expect(diff.noteEventID == event.id)
        #expect(diff.newState == .correct)
        #expect(diff.score != nil)
        if case .hit = diff.streakOutcome { } else {
            Issue.record("Expected .hit streak outcome for correct note")
        }
    }

    // MARK: - Standard Mode: Wrong Note

    @Test func wrongNoteReturnsWrongStateAndMiss() async {
        let actor = NoteMatchingActor()
        let event = makeEvent(midiNote: 60)

        let diff = await actor.evaluate(
            midiNote: 62, // D4, wrong note
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil
        )

        #expect(diff.noteEventID == event.id)
        #expect(diff.newState == .wrong)
        #expect(diff.score != nil)
        if case .miss = diff.streakOutcome { } else {
            Issue.record("Expected .miss streak outcome for wrong note")
        }
    }

    // MARK: - Wait Mode: Match

    @Test func waitModeMatchReturnsCorrectStateAndHit() async {
        let actor = NoteMatchingActor()
        let event = makeEvent(midiNote: 60)

        let diff = await actor.evaluate(
            midiNote: 62, // MIDI note doesn't matter in wait mode — only waitModeMatch does
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: true
        )

        #expect(diff.noteEventID == event.id)
        #expect(diff.newState == .correct)
        #expect(diff.score != nil)
        if case .hit = diff.streakOutcome { } else {
            Issue.record("Expected .hit streak outcome for wait mode match")
        }
    }

    // MARK: - Wait Mode: No Match

    @Test func waitModeNoMatchReturnsWrongStateAndNoChange() async {
        let actor = NoteMatchingActor()
        let event = makeEvent(midiNote: 60)

        let diff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: false
        )

        #expect(diff.noteEventID == event.id)
        #expect(diff.newState == .wrong)
        #expect(diff.score == nil)
        if case .noChange = diff.streakOutcome { } else {
            Issue.record("Expected .noChange streak outcome for wait mode mismatch")
        }
    }

    // MARK: - Pitch Deviation

    @Test func centsDeviationFromPitchResultIsUsed() async {
        let actor = NoteMatchingActor()
        let event = makeEvent(midiNote: 60)
        let pitch = PitchResult(
            frequency: 261.63,
            amplitude: 0.8,
            noteName: "Sa",
            octave: 4,
            centsOffset: 15.0,
            confidence: 0.95,
            ragaCentsOffset: nil
        )

        let diff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: pitch,
            ragaScoringContext: nil,
            waitModeMatch: nil
        )

        // Score should exist and use the 15-cent deviation (better than 0 fallback)
        #expect(diff.score != nil)
        let scoreDeviation = diff.score?.pitchDeviationCents ?? -1
        #expect(scoreDeviation == 15.0)
    }

    // MARK: - Concurrent Safety

    @Test func concurrentEvaluationsProduceIndependentResults() async {
        let actor = NoteMatchingActor()
        let correctEvent = makeEvent(midiNote: 60)
        let wrongEvent = makeEvent(midiNote: 62)

        async let correctDiff = actor.evaluate(
            midiNote: 60,
            expectedEvent: correctEvent,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil
        )

        async let wrongDiff = actor.evaluate(
            midiNote: 65,
            expectedEvent: wrongEvent,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil
        )

        let (correct, wrong) = await (correctDiff, wrongDiff)

        #expect(correct.newState == .correct)
        #expect(wrong.newState == .wrong)
        #expect(correct.noteEventID != wrong.noteEventID)
    }

    // MARK: - ScoringDiff Sendability

    @Test func scoringDiffIsProducedWithExpectedFields() async {
        let actor = NoteMatchingActor()
        let eventID = UUID()
        let event = NoteEvent(
            id: eventID,
            midiNote: 60,
            swarName: "Sa",
            westernName: "C4",
            octave: 4,
            timestamp: 1.0,
            duration: 0.4,
            velocity: 80
        )

        let diff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil
        )

        #expect(diff.noteEventID == eventID)
        #expect(diff.newState == .correct)
    }
}
