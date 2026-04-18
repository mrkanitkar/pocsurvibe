import Foundation
import Testing
@testable import SurVibe
import SVAudio
import SVLearning

// MARK: - Chord scoring integration tests (MAJ-2)

/// Tests for the chord-aware scoring path that wires
/// `PracticeAudioProcessor.chordStream` (MIN-21) into
/// `NoteMatchingActor.evaluateChord` (MAJ-2) and back into `ScoringDiff`.
///
/// `PlayAlongViewModel` requires a `@MainActor` audio engine and SwiftData
/// stack, so these tests exercise the contract from two angles:
/// 1. `NoteMatchingActor.evaluateChord` directly — covers the completeness
///    arithmetic (full match, partial, zero, extra-note tolerance).
/// 2. `ScoringDiff.chordCompleteness` defaulting — covers the backward-
///    compatible nil for single-note events.
@MainActor
struct ChordScoringIntegrationTests {

    // MARK: - Helpers

    /// Build a minimal NoteEvent for tests.
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

    // MARK: - evaluateChord — happy path

    @Test("evaluateChord returns 1.0 when all expected notes are detected")
    func evaluateChordFullMatchReturnsOne() async {
        let actor = NoteMatchingActor()
        let completeness = await actor.evaluateChord(
            expectedChordNotes: [60, 64, 67],
            detectedNotes: [60, 64, 67]
        )
        #expect(completeness == 1.0)
    }

    // MARK: - evaluateChord — partial match

    @Test("evaluateChord returns 2/3 when one of three expected notes is missing")
    func evaluateChordPartialMatchReturnsFraction() async {
        let actor = NoteMatchingActor()
        let completeness = await actor.evaluateChord(
            expectedChordNotes: [60, 64, 67],
            detectedNotes: [60, 64]
        )
        #expect(abs(completeness - 2.0 / 3.0) < 0.0001)
    }

    // MARK: - evaluateChord — zero match

    @Test("evaluateChord returns 0.0 when no expected notes are detected")
    func evaluateChordNoMatchReturnsZero() async {
        let actor = NoteMatchingActor()
        let completeness = await actor.evaluateChord(
            expectedChordNotes: [60, 64, 67],
            detectedNotes: [62, 65, 69]
        )
        #expect(completeness == 0.0)
    }

    // MARK: - evaluateChord — extra notes do not penalize

    @Test("evaluateChord ignores extra detected notes (no penalty)")
    func evaluateChordExtraNotesDoNotPenalize() async {
        let actor = NoteMatchingActor()
        let completeness = await actor.evaluateChord(
            expectedChordNotes: [60, 64, 67],
            detectedNotes: [60, 64, 67, 72, 79] // C major plus octaves
        )
        #expect(completeness == 1.0)
    }

    // MARK: - evaluateChord — empty expected set

    @Test("evaluateChord returns 1.0 for an empty expected set (degenerate)")
    func evaluateChordEmptyExpectedReturnsOne() async {
        let actor = NoteMatchingActor()
        let completeness = await actor.evaluateChord(
            expectedChordNotes: [],
            detectedNotes: [60, 64, 67]
        )
        #expect(completeness == 1.0)
    }

    // MARK: - evaluateChord — empty detected set

    @Test("evaluateChord returns 0.0 when no notes are detected")
    func evaluateChordEmptyDetectedReturnsZero() async {
        let actor = NoteMatchingActor()
        let completeness = await actor.evaluateChord(
            expectedChordNotes: [60, 64, 67],
            detectedNotes: []
        )
        #expect(completeness == 0.0)
    }

    // MARK: - evaluateChord — actor delegates to ChordScoreCalculator

    @Test("evaluateChord matches ChordScoreCalculator.score completeness")
    func evaluateChordDelegatesToChordScoreCalculator() async {
        let actor = NoteMatchingActor()
        let expected: Set<Int> = [60, 64, 67, 71]    // C maj7
        let detected: Set<Int> = [60, 67]            // root + fifth only
        let actorResult = await actor.evaluateChord(
            expectedChordNotes: expected,
            detectedNotes: detected
        )
        let calculatorResult = ChordScoreCalculator.score(
            expectedNotes: expected,
            detectedNotes: detected
        )
        #expect(actorResult == calculatorResult.completeness)
        #expect(actorResult == 0.5)
    }

    // MARK: - ScoringDiff — chordCompleteness default

    @Test("ScoringDiff.chordCompleteness defaults to nil for single-note events")
    func scoringDiffChordCompletenessDefaultsNil() async {
        let actor = NoteMatchingActor()
        let event = makeEvent(midiNote: 60)
        let diff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil
        )
        #expect(diff.chordCompleteness == nil,
                "Single-note evaluations must leave chordCompleteness nil")
    }

    // MARK: - ScoringDiff — chordCompleteness can be assigned

    @Test("ScoringDiff.chordCompleteness can be populated post-evaluation")
    func scoringDiffChordCompletenessIsAssignable() async {
        let actor = NoteMatchingActor()
        let event = makeEvent(midiNote: 60)
        var diff = await actor.evaluate(
            midiNote: 60,
            expectedEvent: event,
            currentPitch: nil,
            ragaScoringContext: nil,
            waitModeMatch: nil
        )
        diff.chordCompleteness = 0.75
        #expect(diff.chordCompleteness == 0.75)
    }
}
