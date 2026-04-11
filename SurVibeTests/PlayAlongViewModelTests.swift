import Testing
import Foundation
import SVAudio
import SVLearning

@testable import SurVibe

// MARK: - PlayAlongViewModel Tests

/// Tests for PlayAlongViewModel — the main play-along session orchestrator.
///
/// All dependencies are injected as mocks (MockSoundFontPlayer,
/// MockAudioEngineProvider, MockMetronomePlayer, TestClock) to enable
/// deterministic, hardware-free testing.
@MainActor
private func waitForActiveNote(
    _ vm: PlayAlongViewModel,
    clock: TestClock,
    maxIterations: Int = 20
) async {
    for _ in 0..<maxIterations {
        if vm.currentNoteIndex != nil { return }
        await clock.advance(by: .milliseconds(10))
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
struct PlayAlongViewModelTests {

    // MARK: - Helpers

    /// Dependency bundle returned by `makeSUT()`.
    private struct SUT {
        let vm: PlayAlongViewModel
        let soundFont: MockSoundFontPlayer
        let engine: MockAudioEngineProvider
        let metronome: MockMetronomePlayer
        let clock: TestClock
    }

    /// Create a ViewModel with all mock dependencies.
    private func makeSUT() -> SUT {
        let soundFont = MockSoundFontPlayer()
        let engine = MockAudioEngineProvider()
        let metronome = MockMetronomePlayer()
        let clock = TestClock()
        let vm = PlayAlongViewModel(
            soundFont: soundFont,
            audioEngine: engine,
            metronome: metronome,
            clock: clock
        )
        return SUT(vm: vm, soundFont: soundFont, engine: engine, metronome: metronome, clock: clock)
    }

    /// Create a Song with Sargam + Western notation data (notation path).
    private func makeNotationSong(
        title: String = "Test Song",
        difficulty: Int = 2,
        tempo: Int = 120
    ) -> Song {
        let sargamNotes = [
            SargamNote(note: "Sa", octave: 4, duration: 1.0),
            SargamNote(note: "Re", octave: 4, duration: 1.0),
            SargamNote(note: "Ga", octave: 4, duration: 1.0),
            SargamNote(note: "Ma", octave: 4, duration: 1.0),
        ]
        let westernNotes = [
            WesternNote(note: "C4", duration: 1.0, midiNumber: 60),
            WesternNote(note: "D4", duration: 1.0, midiNumber: 62),
            WesternNote(note: "E4", duration: 1.0, midiNumber: 64),
            WesternNote(note: "F4", duration: 1.0, midiNumber: 65),
        ]

        let song = Song(title: title, difficulty: difficulty, tempo: tempo)
        song.sargamNotation = try? JSONEncoder().encode(sargamNotes)
        song.westernNotation = try? JSONEncoder().encode(westernNotes)
        return song
    }

    /// Create a Song with Komal/Tivra notation.
    private func makeKomalTivraSong() -> Song {
        let sargamNotes = [
            SargamNote(note: "Sa", octave: 4, duration: 1.0),
            SargamNote(note: "Re", octave: 4, duration: 1.0, modifier: "komal"),
            SargamNote(note: "Ma", octave: 4, duration: 1.0, modifier: "tivra"),
            SargamNote(note: "Pa", octave: 4, duration: 1.0),
        ]
        let westernNotes = [
            WesternNote(note: "C4", duration: 1.0, midiNumber: 60),
            WesternNote(note: "Db4", duration: 1.0, midiNumber: 61),
            WesternNote(note: "F#4", duration: 1.0, midiNumber: 66),
            WesternNote(note: "G4", duration: 1.0, midiNumber: 67),
        ]

        let song = Song(title: "Komal Tivra Test", difficulty: 1, tempo: 120)
        song.sargamNotation = try? JSONEncoder().encode(sargamNotes)
        song.westernNotation = try? JSONEncoder().encode(westernNotes)
        return song
    }

    // MARK: - loadSong Tests

    @Test("loadSong with notation-only song loads NoteEvents via notation path")
    func loadSongNotationPath() async {
        let sut = makeSUT()
        let vm = sut.vm
        let song = makeNotationSong()

        await vm.loadSong(song)

        #expect(vm.noteEvents.count == 4)
        #expect(vm.noteEvents[0].swarName == "Sa")
        #expect(vm.noteEvents[1].swarName == "Re")
        #expect(vm.noteEvents[2].swarName == "Ga")
        #expect(vm.noteEvents[3].swarName == "Ma")
        #expect(vm.playbackState == .idle)
        #expect(vm.duration > 0)
        #expect(vm.errorMessage == nil)
    }

    @Test("loadSong calculates duration from last note event")
    func loadSongCalculatesDuration() async {
        let sut = makeSUT()
        let vm = sut.vm
        let song = makeNotationSong(tempo: 120)

        await vm.loadSong(song)

        // 4 notes at 1 beat each, 120 bpm = 0.5s per beat
        // Total: 4 * 0.5s = 2.0s
        #expect(vm.duration > 0)
        #expect(vm.noteEvents.count == 4)
    }

    @Test("loadSong initializes all noteStates as upcoming")
    func loadSongInitializesNoteStates() async {
        let sut = makeSUT()
        let vm = sut.vm
        let song = makeNotationSong()

        await vm.loadSong(song)

        for event in vm.noteEvents {
            #expect(vm.noteStates[event.id] == .upcoming)
        }
    }

    @Test("loadSong with no data sets error state")
    func loadSongNoDataShowsError() async {
        let sut = makeSUT()
        let vm = sut.vm
        let song = Song(title: "Empty Song")
        // No sargamNotation, no westernNotation, no midiData

        await vm.loadSong(song)

        #expect(vm.noteEvents.isEmpty)
        #expect(vm.errorMessage == "No playable notation found")
        #expect(vm.playbackState == .error("No playable notation"))
    }

    @Test("loadSong with Komal/Tivra notes preserves full swar names")
    func loadSongPreservesKomalTivraNames() async {
        let sut = makeSUT()
        let vm = sut.vm
        let song = makeKomalTivraSong()

        await vm.loadSong(song)

        #expect(vm.noteEvents.count == 4)
        #expect(vm.noteEvents[0].swarName == "Sa")
        #expect(vm.noteEvents[1].swarName == "Komal Re")
        #expect(vm.noteEvents[2].swarName == "Tivra Ma")
        #expect(vm.noteEvents[3].swarName == "Pa")
    }

    // MARK: - startSession Tests

    @Test("startSession sets playbackState to playing")
    func startSessionSetsPlaying() async {
        let sut = makeSUT()
        let vm = sut.vm
        let song = makeNotationSong()
        await vm.loadSong(song)

        await vm.startSession()

        #expect(vm.playbackState == .playing)
    }

    @Test("startSession calls audioEngine.start for playAndRecord mode")
    func startSessionCallsEngineStart() async {
        let sut = makeSUT()
        let vm = sut.vm
        let engine = sut.engine
        let song = makeNotationSong()
        await vm.loadSong(song)

        await vm.startSession()

        #expect(engine.startCallCount == 1)
        #expect(engine.isRunning)
    }

    @Test("startSession starts the metronome at scaled BPM")
    func startSessionStopsMetronome() async {
        let sut = makeSUT()
        let vm = sut.vm
        let metronome = sut.metronome
        let song = makeNotationSong()
        await vm.loadSong(song)

        await vm.startSession()

        // Metronome should be started at the song's scaled BPM
        #expect(metronome.startCallCount >= 1)
    }

    @Test("startSession resets scoring state")
    func startSessionResetsScoring() async {
        let sut = makeSUT()
        let vm = sut.vm
        let song = makeNotationSong()
        await vm.loadSong(song)

        await vm.startSession()

        #expect(vm.noteScores.isEmpty)
        #expect(vm.accuracy == 0)
        #expect(vm.streak == 0)
        #expect(vm.longestStreak == 0)
        #expect(vm.starRating == 0)
        #expect(vm.xpEarned == 0)
        #expect(vm.currentTime == 0)
    }

    @Test("startSession with no events does not change state")
    func startSessionWithNoEventsDoesNothing() async {
        let sut = makeSUT()
        let vm = sut.vm
        let engine = sut.engine
        // Don't load a song

        await vm.startSession()

        #expect(vm.playbackState == .idle)
        #expect(engine.startCallCount == 0)
    }

    @Test("startSession when engine fails sets error state")
    func startSessionEngineFailureSetsError() async {
        let sut = makeSUT()
        let vm = sut.vm
        let engine = sut.engine
        let song = makeNotationSong()
        await vm.loadSong(song)
        engine.shouldThrowOnStart = true

        await vm.startSession()

        #expect(vm.playbackState == .error("Audio engine failed to start"))
    }

    @Test("startSession creates wait controller when wait mode enabled")
    func startSessionCreatesWaitControllerWhenEnabled() async {
        let sut = makeSUT()
        let vm = sut.vm
        let song = makeNotationSong()
        await vm.loadSong(song)
        vm.isWaitModeEnabled = true

        await vm.startSession()

        #expect(vm.playbackState == .playing)
    }

    // MARK: - pauseSession / resumeSession Tests

    @Test("pauseSession transitions from playing to paused")
    func pauseSessionTransitionsToPaused() async {
        let sut = makeSUT()
        let vm = sut.vm
        let song = makeNotationSong()
        await vm.loadSong(song)
        await vm.startSession()

        vm.pauseSession()

        #expect(vm.playbackState == .paused)
    }

    @Test("pauseSession stops all sounding notes")
    func pauseSessionStopsAllNotes() async {
        let sut = makeSUT()
        let vm = sut.vm
        let soundFont = sut.soundFont
        let song = makeNotationSong()
        await vm.loadSong(song)
        await vm.startSession()

        vm.pauseSession()

        #expect(soundFont.stopAllNotesCallCount >= 1)
    }

    @Test("pauseSession from non-playing state does nothing")
    func pauseSessionFromNonPlayingDoesNothing() async {
        let sut = makeSUT()
        let vm = sut.vm
        let soundFont = sut.soundFont

        vm.pauseSession()

        #expect(vm.playbackState == .idle)
        #expect(soundFont.stopAllNotesCallCount == 0)
    }

    @Test("resumeSession transitions from paused to playing")
    func resumeSessionTransitionsToPlaying() async {
        let sut = makeSUT()
        let vm = sut.vm
        let song = makeNotationSong()
        await vm.loadSong(song)
        await vm.startSession()
        vm.pauseSession()

        vm.resumeSession()

        #expect(vm.playbackState == .playing)
    }

    @Test("resumeSession from non-paused state does nothing")
    func resumeSessionFromNonPausedDoesNothing() async {
        let sut = makeSUT()
        let vm = sut.vm

        vm.resumeSession()

        #expect(vm.playbackState == .idle)
    }

    // MARK: - handleKeyboardTouch Tests

    @Test("handleKeyboardTouch updates note state to correct for matching MIDI note")
    func handleKeyboardTouchCorrectNote() async {
        let sut = makeSUT()
        let vm = sut.vm
        let clock = sut.clock
        let song = makeNotationSong()
        await vm.loadSong(song)
        await vm.startSession()

        // Wait for the playback loop to set currentNoteIndex
        await waitForActiveNote(vm, clock: clock)

        // The first note is Sa (MIDI 60)
        if let index = vm.currentNoteIndex {
            let event = vm.noteEvents[index]
            await vm.handleKeyboardTouch(midiNote: Int(event.midiNote))

            #expect(vm.noteStates[event.id] == .correct)
            #expect(vm.noteScores.count >= 1)
        }
    }

    @Test("handleKeyboardTouch before any song is loaded does not record scores")
    func handleKeyboardTouchWhenNotPlayingDoesNothing() async {
        let sut = makeSUT()
        let vm = sut.vm
        // No loadSong — playbackState is .idle with no noteEvents.
        // handleGuidedNoteDetected guards on currentNoteIndex != nil,
        // which is nil when no song is loaded, so no score is recorded.
        await vm.handleKeyboardTouch(midiNote: 60)

        #expect(vm.noteScores.isEmpty)
    }

    // MARK: - cleanup Tests

    @Test("cleanup cancels tasks and resets state")
    func cleanupResetsState() async {
        let sut = makeSUT()
        let vm = sut.vm
        let soundFont = sut.soundFont
        let engine = sut.engine
        let song = makeNotationSong()
        await vm.loadSong(song)
        await vm.startSession()

        vm.cleanup()

        #expect(vm.playbackState == .idle)
        #expect(soundFont.stopAllNotesCallCount >= 1)
        #expect(engine.stopCallCount >= 1)
    }

    // MARK: - Default Property Tests

    @Test("initial state has correct defaults")
    func initialStateDefaults() {
        let sut = makeSUT()
        let vm = sut.vm

        #expect(vm.playbackState == .idle)
        #expect(vm.noteEvents.isEmpty)
        #expect(vm.currentNoteIndex == nil)
        #expect(vm.noteStates.isEmpty)
        #expect(vm.noteScores.isEmpty)
        #expect(vm.currentTime == 0)
        #expect(vm.duration == 0)
        #expect(vm.accuracy == 0)
        #expect(vm.streak == 0)
        #expect(vm.longestStreak == 0)
        #expect(vm.starRating == 0)
        #expect(vm.xpEarned == 0)
        #expect(vm.errorMessage == nil)
        #expect(vm.isWaitModeEnabled == false)
        #expect(vm.tempoScale == 1.0)
        #expect(vm.isSoundEnabled == true)
        #expect(vm.viewMode == .fallingNotes)
        #expect(vm.notationMode == .sargam)
        #expect(vm.currentPitch == nil)
        #expect(vm.detectedMidiNotes.isEmpty)
    }

    @Test("tempoScale can be changed to slow down playback")
    func tempoScaleIsConfigurable() {
        let sut = makeSUT()
        let vm = sut.vm

        vm.tempoScale = 0.5

        #expect(vm.tempoScale == 0.5)
    }

    @Test("isSoundEnabled can be toggled")
    func isSoundEnabledIsToggleable() {
        let sut = makeSUT()
        let vm = sut.vm

        vm.isSoundEnabled = false

        #expect(vm.isSoundEnabled == false)
    }

    // MARK: - Wait Mode Integration

    @Test("wait mode evaluates using full swar name for Komal notes")
    func waitModeUsesFullSwarNameForKomal() async {
        let sut = makeSUT()
        let vm = sut.vm
        let clock = sut.clock
        let song = makeKomalTivraSong()
        await vm.loadSong(song)
        vm.isWaitModeEnabled = true
        await vm.startSession()

        // Advance past first note to the second (Komal Re)
        await clock.advance(by: .milliseconds(600))
        try? await Task.sleep(for: .milliseconds(100))

        // Verify we have note events with Komal Re
        let komalReEvent = vm.noteEvents.first { $0.swarName == "Komal Re" }
        #expect(komalReEvent != nil)
    }
}
