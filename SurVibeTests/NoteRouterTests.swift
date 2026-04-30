// SurVibeTests/NoteRouterTests.swift
import Foundation
import SVAudio
import SVCore
import SVLearning
import Testing

@testable import SurVibe

/// Unit tests for `NoteRouter` (SP-3d).
///
/// `NoteRouter` is the input domain coordinator extracted from
/// `PlayAlongViewModel`. Owns MIDI input, mic pitch detection, chord
/// detection, note input processing (scoring dispatch + raga enrichment),
/// guided free-play state, and `latencyPreset` with its restart side-effect.
///
/// ADR-002 Phase 1 invariants (preserved by construction):
/// - CoreMIDI → MIDINoteHighlightCoordinator path stays lock-free
/// - NoteMatchingActor custom actor receives scoring dispatches
///
/// ## Mock surface
/// - `MockMIDIInputProvider` (existing SP-0 double) — simulates MIDI keyboard.
/// - `MockAudioEngineProvider` (SP-0) — exposes `startCallCount`, `stopCallCount`.
/// - `MockSoundFontPlayer` (SP-0) — exposes `stopAllNotesCallCount`.
/// - `MockMetronomePlayer` (SP-0) — exposes `startCallCount`, `stopCallCount`.
/// - `NoteEventFactory` (test helper) — builds NoteEvents with correct UInt8 types.
@MainActor
@Suite("NoteRouter")
struct NoteRouterTests {

    // MARK: - Helpers

    /// Build a `PlaybackCoordinator` with test doubles.
    private func makePlayback(scoring: ScoringCoordinator) -> PlaybackCoordinator {
        PlaybackCoordinator(scoring: scoring)
    }

    /// Build a `NoteRouter` with optional dependency overrides.
    ///
    /// All parameters are provided explicitly because `@MainActor` default
    /// expressions in function signatures are not evaluated in the correct isolation
    /// context (same pattern used in `PlaybackCoordinatorTests.makeCoordinator`).
    private func makeRouter(
        midi: MockMIDIInputProvider,
        scoring: ScoringCoordinator,
        playback: PlaybackCoordinator
    ) -> NoteRouter {
        NoteRouter(
            midiInput: midi,
            scoring: scoring,
            playback: playback
        )
    }

    /// Convenience overload — fresh mocks when the test doesn't inspect them.
    private func makeRouter() -> NoteRouter {
        let scoring = ScoringCoordinator()
        let playback = makePlayback(scoring: scoring)
        return makeRouter(
            midi: MockMIDIInputProvider(),
            scoring: scoring,
            playback: playback
        )
    }

    // MARK: - Tests

    /// A freshly-created router reports no MIDI connection, no pitch, no
    /// detected notes, guided-play waiting state, and no expected note.
    @Test
    func initialStateHasNoConnectionAndNoCurrentPitch() {
        let router = makeRouter()
        #expect(router.isMIDIConnected == false)
        #expect(router.midiDeviceName == nil)
        #expect(router.currentPitch == nil)
        #expect(router.detectedMidiNotes.isEmpty)
        #expect(router.guidedPlayState == .waitingForNote)
        #expect(router.expectedMidiNote == nil)
        #expect(router.isStuck == false)
    }

    /// `handleKeyboardNoteOn` inserts the note number into `detectedMidiNotes`.
    @Test
    func handleKeyboardNoteOnInsertsIntoDetectedSet() {
        let router = makeRouter()
        router.handleKeyboardNoteOn(midiNote: 60)
        #expect(router.detectedMidiNotes.contains(60))
    }

    /// `handleKeyboardNoteOff` removes a previously-inserted note from
    /// `detectedMidiNotes` so the sheet view un-highlights the key.
    @Test
    func handleKeyboardNoteOffRemovesFromDetectedSet() {
        let router = makeRouter()
        router.handleKeyboardNoteOn(midiNote: 60)
        router.handleKeyboardNoteOff(midiNote: 60)
        #expect(!router.detectedMidiNotes.contains(60))
    }

    /// `skipGuidedNote` records a missed score (not a hit), advances
    /// `currentNoteIndex` to the next note, and resets guided-play state
    /// to `.waitingForNote`.
    @Test
    func skipGuidedNoteAdvancesIndexAndRecordsMissed() {
        let scoring = ScoringCoordinator()
        let playback = makePlayback(scoring: scoring)
        playback.installNoteEventsForTesting([
            NoteEventFactory.make(swarName: "Sa", midiNote: 60),
            NoteEventFactory.make(swarName: "Re", midiNote: 62),
        ])
        playback.currentNoteIndex = 0
        let router = makeRouter(
            midi: MockMIDIInputProvider(),
            scoring: scoring,
            playback: playback
        )

        router.skipGuidedNote()

        #expect(scoring.notesHit == 0, "Skip records as missed, not hit")
        #expect(scoring.noteScores.count == 1, "One missed score recorded")
        #expect(playback.currentNoteIndex == 1, "Advanced to next note")
    }

    /// Setting `latencyPreset` persists the raw value to UserDefaults under the
    /// expected key so the choice survives app launches.
    @Test
    func latencyPresetSetterPersistsToUserDefaults() {
        let key = "com.survibe.playAlong.latencyPreset"
        UserDefaults.standard.removeObject(forKey: key)
        let router = makeRouter()

        // Use .balanced (non-default; default is .fast) for a meaningful round-trip.
        router.latencyPreset = LatencyPreset.balanced

        let stored = UserDefaults.standard.string(forKey: key)
        #expect(stored == LatencyPreset.balanced.rawValue, "Setter persists to UserDefaults")

        // Clean up to avoid polluting subsequent tests.
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// `NoteRouter` reads the persisted `LatencyPreset` from UserDefaults at
    /// construction time so the user's preferred buffer size is restored.
    @Test
    func latencyPresetReadsFromUserDefaultsAtConstruction() {
        let key = "com.survibe.playAlong.latencyPreset"
        UserDefaults.standard.set(LatencyPreset.ultraFast.rawValue, forKey: key)
        // .ultraFast is a non-default case (default is .fast); verifies round-trip from UserDefaults.

        let router = makeRouter()
        #expect(router.latencyPreset == .ultraFast)

        // Clean up.
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// `updateExpectedMidiNote` reads the MIDI note number from the event at
    /// `currentNoteIndex` and publishes it to `expectedMidiNote` so the sheet
    /// view can highlight the target key.
    @Test
    func updateExpectedMidiNoteSetsExpectedFromCurrentEvent() {
        let scoring = ScoringCoordinator()
        let playback = makePlayback(scoring: scoring)
        playback.installNoteEventsForTesting([
            NoteEventFactory.make(swarName: "Sa", midiNote: 60)
        ])
        playback.currentNoteIndex = 0
        let router = makeRouter(
            midi: MockMIDIInputProvider(),
            scoring: scoring,
            playback: playback
        )

        router.updateExpectedMidiNote()

        #expect(router.expectedMidiNote == 60)
    }

    /// `stopInputDetection` cancels all in-flight tasks and removes MIDI / mic
    /// callbacks so no spurious events are delivered after teardown.
    @Test
    func stopInputDetectionCancelsTasksAndClearsCallbacks() {
        let midi = MockMIDIInputProvider()
        let scoring = ScoringCoordinator()
        let playback = makePlayback(scoring: scoring)
        let router = makeRouter(midi: midi, scoring: scoring, playback: playback)

        router.stopInputDetection()

        // The MIDI provider's `onNoteEvent` callback must be cleared to
        // prevent CoreMIDI from delivering events to a deallocated router.
        #expect(midi.onNoteEvent == nil, "onNoteEvent callback cleared on stop")
        #expect(router.detectedMidiNotes.isEmpty, "detectedMidiNotes cleared on stop")
    }
}
