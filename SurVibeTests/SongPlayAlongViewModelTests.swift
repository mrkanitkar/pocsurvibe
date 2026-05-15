// SurVibeTests/SongPlayAlongViewModelTests.swift
import Foundation
import SVAudio
import Testing
@testable import SurVibe

@MainActor
struct SongPlayAlongViewModelTests {

    // MARK: - Helpers

    private static func makeNote(
        timestamp: TimeInterval,
        duration: TimeInterval,
        midi: UInt8,
        swar: String = "Sa"
    ) -> NoteEvent {
        NoteEvent(
            id: UUID(),
            midiNote: midi,
            swarName: swar,
            westernName: "C4",
            octave: 4,
            timestamp: timestamp,
            duration: duration,
            velocity: 100
        )
    }

    private static func makeTwoNoteSequence() -> [NoteEvent] {
        [
            makeNote(timestamp: 0.0, duration: 0.5, midi: 60),
            makeNote(timestamp: 0.5, duration: 0.5, midi: 62, swar: "Re")
        ]
    }

    // MARK: - Initial state

    @Test
    func initialStateIsIdle() {
        let vm = SongPlayAlongViewModel()
        #expect(vm.playbackState == .idle)
        #expect(vm.noteEvents.isEmpty)
        #expect(vm.duration == 0)
        #expect(vm.tickState.currentNoteIndex == nil)
        #expect(vm.scoring == nil)
    }

    @Test
    func tempoScaleClampsToValidRange() {
        let vm = SongPlayAlongViewModel()
        vm.tempoScale = 0.1
        #expect(vm.tempoScale == 0.5)
        vm.tempoScale = 5.0
        #expect(vm.tempoScale == 1.5)
        vm.tempoScale = 1.2
        #expect(vm.tempoScale == 1.2)
    }

    // MARK: - Transport

    @Test
    func playFromIdleTransitionsToPlaying() async {
        let vm = SongPlayAlongViewModel()
        vm.installNoteEventsForTesting(Self.makeTwoNoteSequence())
        #expect(vm.playbackState == .idle)

        await vm.play()

        #expect(vm.playbackState == .playing)
    }

    @Test
    func pauseFromPlayingTransitionsToPaused() async {
        let vm = SongPlayAlongViewModel()
        vm.installNoteEventsForTesting(Self.makeTwoNoteSequence())
        await vm.play()

        vm.pause()

        #expect(vm.playbackState == .paused)
    }

    @Test
    func resumeFromPausedTransitionsToPlaying() async {
        let vm = SongPlayAlongViewModel()
        vm.installNoteEventsForTesting(Self.makeTwoNoteSequence())
        await vm.play()
        vm.pause()

        vm.resume()

        #expect(vm.playbackState == .playing)
    }

    @Test
    func playWithEmptyNoteEventsDoesNothing() async {
        let vm = SongPlayAlongViewModel()
        // No notes installed.

        await vm.play()

        #expect(vm.playbackState == .idle)
    }

    // MARK: - Tick handler

    @Test
    func tickForTestingAdvancesCursorAndActiveSet() async {
        let vm = SongPlayAlongViewModel()
        vm.installNoteEventsForTesting([
            Self.makeNote(timestamp: 0.0, duration: 0.5, midi: 60),
            Self.makeNote(timestamp: 0.5, duration: 0.5, midi: 62, swar: "Re"),
            Self.makeNote(timestamp: 1.0, duration: 0.5, midi: 64, swar: "Ga")
        ])
        await vm.play()

        vm.tickForTesting(at: 0.25)
        #expect(vm.tickState.currentNoteIndex == 0)
        #expect(vm.tickState.activeMidiNotes == [60])

        vm.tickForTesting(at: 0.6)
        #expect(vm.tickState.currentNoteIndex == 1)
        #expect(vm.tickState.activeMidiNotes == [62])
    }

    @Test
    func tickPastDurationTransitionsToStopped() async {
        let vm = SongPlayAlongViewModel()
        vm.installNoteEventsForTesting([
            Self.makeNote(timestamp: 0.0, duration: 0.5, midi: 60)
        ])
        await vm.play()
        #expect(vm.playbackState == .playing)

        vm.tickForTesting(at: 1.0)  // 0.5s past duration 0.5

        #expect(vm.playbackState == .stopped)
    }

    @Test
    func tickIsIdempotentAtCompletion() async {
        let vm = SongPlayAlongViewModel()
        vm.installNoteEventsForTesting([
            Self.makeNote(timestamp: 0.0, duration: 0.5, midi: 60)
        ])
        await vm.play()
        vm.tickForTesting(at: 1.0)
        #expect(vm.playbackState == .stopped)

        // A second tick should not regress state or crash.
        vm.tickForTesting(at: 1.5)
        #expect(vm.playbackState == .stopped)
    }

    // MARK: - Keyboard input + scoring

    @Test
    func handleKeyboardNoteOnRecordsHitWhenNoteIsActive() async {
        let vm = SongPlayAlongViewModel()
        vm.installNoteEventsForTesting([
            Self.makeNote(timestamp: 0.0, duration: 1.0, midi: 60)
        ])
        await vm.play()
        vm.tickForTesting(at: 0.1)  // note 60 is active

        vm.handleKeyboardNoteOn(60)

        #expect(vm.tickState.userPressedNotes.contains(60))
        #expect(vm.scoring?.notesHit == 1)
    }

    @Test
    func handleKeyboardNoteOnWithWrongNoteDoesNotScore() async {
        let vm = SongPlayAlongViewModel()
        vm.installNoteEventsForTesting([
            Self.makeNote(timestamp: 0.0, duration: 1.0, midi: 60)
        ])
        await vm.play()
        vm.tickForTesting(at: 0.1)

        vm.handleKeyboardNoteOn(72)  // wrong key

        #expect(vm.tickState.userPressedNotes.contains(72))
        #expect(vm.scoring?.notesHit == 0)
    }

    @Test
    func handleKeyboardNoteOffRemovesFromUserPressed() async {
        let vm = SongPlayAlongViewModel()
        vm.installNoteEventsForTesting([
            Self.makeNote(timestamp: 0.0, duration: 1.0, midi: 60)
        ])
        await vm.play()
        vm.handleKeyboardNoteOn(60)
        vm.handleKeyboardNoteOff(60)
        #expect(!vm.tickState.userPressedNotes.contains(60))
    }

    // MARK: - Restart

    @Test
    func restartReinitialisesScoringAndState() async {
        let vm = SongPlayAlongViewModel()
        vm.installNoteEventsForTesting([
            Self.makeNote(timestamp: 0.0, duration: 0.5, midi: 60)
        ])
        await vm.play()
        vm.tickForTesting(at: 0.1)
        vm.handleKeyboardNoteOn(60)
        #expect(vm.scoring?.notesHit == 1)

        await vm.restart()

        #expect(vm.scoring?.notesHit == 0)
        #expect(vm.playbackState == .playing)
    }

    // MARK: - Cleanup

    @Test
    func cleanupResetsTickStateAndReturnsToIdle() async {
        let vm = SongPlayAlongViewModel()
        vm.installNoteEventsForTesting(Self.makeTwoNoteSequence())
        await vm.play()
        vm.tickForTesting(at: 0.3)
        #expect(vm.tickState.currentNoteIndex != nil)

        vm.cleanup()

        #expect(vm.playbackState == .idle)
        #expect(vm.tickState.currentNoteIndex == nil)
        #expect(vm.tickState.activeMidiNotes.isEmpty)
    }
}
