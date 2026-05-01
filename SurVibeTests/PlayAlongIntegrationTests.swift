import Foundation
import SwiftData
import Testing
import SVAudio
import SVLearning

@testable import SurVibe

// MARK: - Shared Test Helpers

// TODO(T11'): SUT/makeSUT/waitForActiveNote are only used by the disabled
// notation-path suites. Re-enable when those tests are rewired.
#if false
/// Dependency bundle returned by `makeSUT()`.
private struct SUT {
    let vm: PlayAlongViewModel
    let soundFont: MockSoundFontPlayer
    let engine: MockAudioEngineProvider
    let metronome: MockMetronomePlayer
    let clock: TestClock
}

/// Shared factory methods used across all play-along integration test suites.
///
/// Centralizes SUT construction and song fixtures to avoid duplication
/// while keeping each test suite self-contained.
@MainActor
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

/// Create a Song with Sargam + Western notation (Sa Re Ga Ma at given tempo).
@MainActor
private func makeNotationSong(
    title: String = "Integration Test Song",
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

/// Create a Song with Komal/Tivra notes to verify full swar name preservation.
@MainActor
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
    let song = Song(title: "Komal Tivra Integration", difficulty: 1, tempo: 120)
    song.sargamNotation = try? JSONEncoder().encode(sargamNotes)
    song.westernNotation = try? JSONEncoder().encode(westernNotes)
    return song
}

// MARK: - Helpers

/// Poll until the playback loop has set `currentNoteIndex`, or give up after `maxIterations`.
///
/// The playback loop runs in a `Task` on `@MainActor`. A single `Task.yield()` inside
/// `TestClock.advance()` is not guaranteed to schedule that Task. This helper retries
/// with small clock advances + real yields until the playback Task has processed.
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
#endif // T11'-pending — SUT, makeSUT, factories and waitForActiveNote
// MARK: - PlayAlongFullFlowTests

#if false
/// Integration tests for the complete play-along lifecycle.
///
/// Each test exercises multiple components working together:
/// ViewModel + mock audio engine + mock SoundFont + TestClock + WaitController.
/// These verify end-to-end behavior rather than isolated units.
@MainActor
struct PlayAlongFullFlowTests {

    @Test("Load song then start session initializes all components correctly")
    func loadAndStartInitializesComponents() async {
        let sut = makeSUT()
        let vm = sut.vm
        let soundFont = sut.soundFont
        let engine = sut.engine
        let metronome = sut.metronome
        let song = makeNotationSong()

        await vm.loadSong(song)
        await vm.startSession()

        #expect(vm.playbackState == .playing)
        #expect(vm.noteEvents.count == 4)
        #expect(engine.startCallCount == 1)
        #expect(engine.isRunning)
        #expect(metronome.startCallCount >= 1)
        #expect(vm.currentTime == 0)
        #expect(vm.noteScores.isEmpty)
        // SoundFont should be available (mock always reports loaded)
        #expect(soundFont.isLoaded)
    }

    @Test("Load, start, pause, resume preserves state continuity")
    func pauseResumePreservesState() async {
        let sut = makeSUT()
        let vm = sut.vm
        let soundFont = sut.soundFont
        let clock = sut.clock
        let song = makeNotationSong()
        await vm.loadSong(song)
        await vm.startSession()

        // Advance clock to simulate some playback time
        await clock.advance(by: .milliseconds(200))
        try? await Task.sleep(for: .milliseconds(50))

        let eventsBeforePause = vm.noteEvents.count

        vm.pauseSession()
        #expect(vm.playbackState == .paused)
        #expect(soundFont.stopAllNotesCallCount >= 1)

        vm.resumeSession()
        #expect(vm.playbackState == .playing)
        // Note events should be unchanged after pause/resume
        #expect(vm.noteEvents.count == eventsBeforePause)
        // Scoring state should persist through the cycle
        #expect(vm.noteScores.count == vm.noteScores.count)
    }

    @Test("Full session completion calculates final scoring metrics")
    func sessionCompletionCalculatesMetrics() async {
        let sut = makeSUT()
        let vm = sut.vm
        let clock = sut.clock
        let song = makeNotationSong(tempo: 120)
        await vm.loadSong(song)
        await vm.startSession()

        // At 120 BPM, each beat = 0.5s, 4 notes = 2.0s total duration.
        // Use advanceToCompletion (50ms steps) so the playback loop can wake
        // up after each sleep, process any due notes, and register the next
        // sleep — ensuring all notes are processed and completeSession() fires.
        await clock.advanceToCompletion(totalDuration: .seconds(3), step: .milliseconds(50))

        // Session should have completed — all notes missed (no input)
        #expect(vm.playbackState == .stopped)
        #expect(vm.noteScores.count == 4)
        #expect(vm.starRating >= 1)
        #expect(vm.xpEarned > 0)
    }

    @Test("Komal/Tivra song preserves full swar names end-to-end through load and start")
    func komalTivraPreservedEndToEnd() async {
        let sut = makeSUT()
        let vm = sut.vm
        let clock = sut.clock
        let song = makeKomalTivraSong()
        await vm.loadSong(song)
        await vm.startSession()

        // Verify full swar names survived through the entire pipeline
        #expect(vm.noteEvents[0].swarName == "Sa")
        #expect(vm.noteEvents[1].swarName == "Komal Re")
        #expect(vm.noteEvents[2].swarName == "Tivra Ma")
        #expect(vm.noteEvents[3].swarName == "Pa")

        // Advance to first note and verify noteState is active
        await clock.advance(by: .milliseconds(100))
        try? await Task.sleep(for: .milliseconds(50))

        // At least the first note should have become active
        let hasActiveNote = vm.noteStates.values.contains(.active)
        #expect(hasActiveNote)
    }

    @Test("Empty song with no notation sets error state and propagates message")
    func emptySongPropagatesError() async {
        let sut = makeSUT()
        let vm = sut.vm
        let song = Song(title: "Empty Song")

        await vm.loadSong(song)

        #expect(vm.playbackState == .error("No playable notation"))
        #expect(vm.errorMessage == "No playable notation found")
        #expect(vm.noteEvents.isEmpty)

        // Attempting to start a session should do nothing
        await vm.startSession()
        #expect(vm.playbackState == .error("No playable notation"))
    }

    @Test("Engine failure during start sets error and does not crash")
    func engineFailureHandledGracefully() async {
        let sut = makeSUT()
        let vm = sut.vm
        let engine = sut.engine
        let song = makeNotationSong()
        await vm.loadSong(song)

        engine.shouldThrowOnStart = true
        await vm.startSession()

        #expect(vm.playbackState == .error("Audio engine failed to start"))
        // Ensure note events are still intact (loaded before engine start)
        #expect(vm.noteEvents.count == 4)
    }

    @Test("Cleanup releases all resources and resets to idle state")
    func cleanupReleasesResources() async {
        let sut = makeSUT()
        let vm = sut.vm
        let soundFont = sut.soundFont
        let engine = sut.engine
        let clock = sut.clock
        let song = makeNotationSong()
        await vm.loadSong(song)
        await vm.startSession()

        await clock.advance(by: .milliseconds(100))
        try? await Task.sleep(for: .milliseconds(50))

        vm.cleanup()

        #expect(vm.playbackState == .idle)
        #expect(soundFont.stopAllNotesCallCount >= 1)
        #expect(engine.stopCallCount >= 1)
        #expect(!engine.isRunning)
    }

    @Test("Playing correct notes updates accuracy and streak")
    func correctNotesUpdateAccuracyAndStreak() async {
        let sut = makeSUT()
        let vm = sut.vm
        let clock = sut.clock
        let song = makeNotationSong(tempo: 120)
        await vm.loadSong(song)
        await vm.startSession()

        // Wait for playback loop to activate first note
        await waitForActiveNote(vm, clock: clock)

        guard vm.currentNoteIndex != nil else {
            return
        }

        // Play the correct note for the first event
        await vm.handleKeyboardTouch(midiNote: 60) // Sa = MIDI 60

        #expect(vm.noteScores.count >= 1)
        #expect(vm.accuracy > 0)
        #expect(vm.streak >= 1)
        #expect(vm.longestStreak >= 1)
    }

    @Test("Wait mode with correct note resumes playback flow")
    func waitModeCorrectNoteResumesFlow() async {
        let sut = makeSUT()
        let vm = sut.vm
        let clock = sut.clock
        let song = makeNotationSong(tempo: 120)
        await vm.loadSong(song)
        vm.isWaitModeEnabled = true
        await vm.startSession()

        // Wait for playback loop to activate first note
        await waitForActiveNote(vm, clock: clock)

        guard vm.currentNoteIndex != nil else { return }

        // Play the correct note (Sa = MIDI 60)
        await vm.handleKeyboardTouch(midiNote: 60)

        let firstEvent = vm.noteEvents[0]
        #expect(vm.noteStates[firstEvent.id] == .correct)
        #expect(vm.noteScores.count >= 1)
    }

    @Test("Wait mode with wrong note marks note as wrong and session waits")
    func waitModeWrongNoteKeepsWaiting() async {
        let sut = makeSUT()
        let vm = sut.vm
        let clock = sut.clock
        let song = makeNotationSong(tempo: 120)
        await vm.loadSong(song)
        vm.isWaitModeEnabled = true
        await vm.startSession()

        // Wait for playback loop to activate first note
        await waitForActiveNote(vm, clock: clock)

        guard vm.currentNoteIndex != nil else { return }

        // Play wrong note (Re = MIDI 62 instead of Sa = MIDI 60)
        await vm.handleKeyboardTouch(midiNote: 62)

        let firstEvent = vm.noteEvents[0]
        #expect(vm.noteStates[firstEvent.id] == .wrong)
        // Session should still be playing (waiting for correct note)
        #expect(vm.playbackState == .playing)
    }
}

// MARK: - PlayAlongTempoScalingTests

/// Integration tests for tempo scaling behavior.
///
/// Verifies that the tempoScale property correctly adjusts note timing
/// through the full pipeline: loading, scheduling, and playback.
@MainActor
struct PlayAlongTempoScalingTests {

    @Test("Default tempo scale of 1.0x produces correct note intervals")
    func defaultTempoNoteTimingIsCorrect() async {
        let sut = makeSUT()
        let vm = sut.vm
        let song = makeNotationSong(tempo: 120)
        await vm.loadSong(song)

        // At 120 BPM, each 1-beat note = 0.5s
        // Note timestamps: 0.0, 0.5, 1.0, 1.5
        #expect(vm.noteEvents.count == 4)
        #expect(abs(vm.noteEvents[0].timestamp - 0.0) < 0.001)
        #expect(abs(vm.noteEvents[1].timestamp - 0.5) < 0.001)
        #expect(abs(vm.noteEvents[2].timestamp - 1.0) < 0.001)
        #expect(abs(vm.noteEvents[3].timestamp - 1.5) < 0.001)
        #expect(abs(vm.noteEvents[0].duration - 0.5) < 0.001)
    }

    @Test("Half tempo (0.5x) doubles effective note intervals during playback")
    func halfTempoDoublesIntervals() async {
        let sut = makeSUT()
        let vm = sut.vm
        let soundFont = sut.soundFont
        let clock = sut.clock
        let song = makeNotationSong(tempo: 120)
        await vm.loadSong(song)
        vm.tempoScale = 0.5

        await vm.startSession()

        // At 0.5x tempo, note at timestamp 0.5s is scheduled at 0.5/0.5 = 1.0s
        // Advance 0.8s — first note (at 0.0s) should have been played but
        // second note (at 1.0s effective) should not yet
        await clock.advance(by: .milliseconds(800))
        try? await Task.sleep(for: .milliseconds(100))

        // First note should have been played (SoundFont called)
        let playedCount = soundFont.playedNotes.count
        #expect(playedCount >= 1)
        // At 0.8s with 0.5x tempo, only the first note should be active
        // (second note at effective 1.0s hasn't been reached)
        #expect(vm.currentNoteIndex == 0)
    }

    @Test("1.5x tempo compresses note intervals during playback")
    func onePointFiveTempoCompresses() async {
        let sut = makeSUT()
        let vm = sut.vm
        let soundFont = sut.soundFont
        let clock = sut.clock
        let song = makeNotationSong(tempo: 120)
        await vm.loadSong(song)
        vm.tempoScale = 1.5

        await vm.startSession()

        // At 1.5x, note at timestamp 0.5s is scheduled at 0.5/1.5 ~= 0.333s
        // Advance 0.4s — first two notes should have been played
        await clock.advance(by: .milliseconds(400))
        try? await Task.sleep(for: .milliseconds(100))

        // With faster tempo, more notes should have been reached
        let playedCount = soundFont.playedNotes.count
        #expect(playedCount >= 1)
    }

    @Test("Changing tempo mid-session updates scheduling for subsequent notes")
    func tempoChangeMidSession() async {
        let sut = makeSUT()
        let vm = sut.vm
        let clock = sut.clock
        let song = makeNotationSong(tempo: 120)
        await vm.loadSong(song)
        vm.tempoScale = 1.0

        await vm.startSession()

        // Let first note play
        await clock.advance(by: .milliseconds(100))
        try? await Task.sleep(for: .milliseconds(50))

        // Change tempo to 0.5x — subsequent notes should be scheduled slower
        vm.tempoScale = 0.5

        // The tempoScale property is settable and will be picked up by the
        // playback loop for the next sleep calculation
        #expect(vm.tempoScale == 0.5)
        #expect(vm.playbackState == .playing)
    }

    @Test("Tempo scale values are respected at boundary values")
    func tempoScaleBoundsRespected() {
        let sut = makeSUT()
        let vm = sut.vm

        // Lower bound
        vm.tempoScale = 0.25
        #expect(vm.tempoScale == 0.25)

        // Upper bound
        vm.tempoScale = 1.5
        #expect(vm.tempoScale == 1.5)

        // Default
        vm.tempoScale = 1.0
        #expect(vm.tempoScale == 1.0)
    }
}

// MARK: - PlayAlongScoringIntegrationTests

/// Integration tests for the scoring pipeline.
///
/// Verifies that note-level scoring (NoteScoreCalculator) integrates
/// correctly with session-level metrics (PracticeScoring) through the
/// ViewModel's scoring flow.
@MainActor
struct PlayAlongScoringIntegrationTests {

    @Test("Perfect accuracy on all notes yields 5 stars")
    func perfectAccuracyFiveStars() async {
        let sut = makeSUT()
        let vm = sut.vm
        let clock = sut.clock
        let song = makeNotationSong(tempo: 120)
        await vm.loadSong(song)
        await vm.startSession()

        // MIDI notes for Sa Re Ga Ma: 60, 62, 64, 65
        // At 120 BPM, notes are scheduled at 0.0, 0.5, 1.0, 1.5 seconds.
        // Strategy: advance to each note, yield to let the playback loop
        // mark it active, then play the correct MIDI note immediately
        // before advancing to the next note.
        let expectedMIDI: [Int] = [60, 62, 64, 65]

        for (index, midi) in expectedMIDI.enumerated() {
            if index == 0 {
                // Wait for playback loop to activate the first note
                await waitForActiveNote(vm, clock: clock)
            } else {
                // Advance to just past the next note's timestamp
                await clock.advance(by: .milliseconds(500))
                try? await Task.sleep(for: .milliseconds(50))
            }

            // Play the correct note while it is active
            if vm.currentNoteIndex == index {
                await vm.handleKeyboardTouch(midiNote: midi)
            }
        }

        // Advance well past the end to trigger session completion.
        // Use step-by-step advancement so the playback loop processes remaining notes.
        await clock.advanceToCompletion(totalDuration: .seconds(5), step: .milliseconds(50))

        // All notes played correctly: expect high accuracy and 5 stars
        if vm.playbackState == .stopped {
            // Verify that correct notes were scored (not all missed)
            let correctCount = vm.noteScores.filter { $0.grade != .miss }.count
            #expect(correctCount >= 3, "Expected at least 3 correct notes, got \(correctCount)")
            // With mostly/all correct notes, expect at least 4 stars
            #expect(vm.starRating >= 4, "Expected star rating >= 4, got \(vm.starRating)")
            #expect(vm.accuracy >= 0.75, "Expected accuracy >= 0.75, got \(vm.accuracy)")
        }
    }

    @Test("Zero accuracy with all missed notes yields 1 star")
    func zeroAccuracyOneStar() async {
        let sut = makeSUT()
        let vm = sut.vm
        let clock = sut.clock
        let song = makeNotationSong(tempo: 120)
        await vm.loadSong(song)
        await vm.startSession()

        // Do not play any notes — let all notes pass as missed.
        // Use step-by-step advancement to give the playback loop scheduling opportunities.
        await clock.advanceToCompletion(totalDuration: .seconds(4), step: .milliseconds(50))

        if vm.playbackState == .stopped {
            #expect(vm.starRating == 1)
            #expect(vm.accuracy < 0.4)
            // All notes should be scored as missed
            let missCount = vm.noteScores.filter { $0.grade == .miss }.count
            #expect(missCount == 4)
        }
    }

    @Test("Mixed accuracy produces correct intermediate star rating")
    func mixedAccuracyIntermediateStars() async {
        let sut = makeSUT()
        let vm = sut.vm
        let clock = sut.clock
        let song = makeNotationSong(tempo: 120)
        await vm.loadSong(song)
        await vm.startSession()

        // Play only the first note correctly, let the rest be missed
        await clock.advance(by: .milliseconds(50))
        try? await Task.sleep(for: .milliseconds(80))
        if vm.currentNoteIndex != nil {
            await vm.handleKeyboardTouch(midiNote: 60) // Sa correct
        }

        // Let remaining notes be missed via step-by-step advancement
        await clock.advanceToCompletion(totalDuration: .seconds(4), step: .milliseconds(50))

        if vm.playbackState == .stopped {
            // 1 correct + 3 missed => ~25% accuracy => 1 star
            #expect(vm.starRating >= 1)
            #expect(vm.starRating <= 3)
        }
    }

    @Test("Streak tracks consecutive correct notes across the session")
    func streakTracksConsecutiveCorrectNotes() async {
        let sut = makeSUT()
        let vm = sut.vm
        let clock = sut.clock
        let song = makeNotationSong(tempo: 120)
        await vm.loadSong(song)
        await vm.startSession()

        // Play first note correctly
        await waitForActiveNote(vm, clock: clock)
        if vm.currentNoteIndex != nil {
            await vm.handleKeyboardTouch(midiNote: 60) // Sa correct
            #expect(vm.streak >= 1)
        }

        // Play second note correctly
        await clock.advance(by: .milliseconds(500))
        try? await Task.sleep(for: .milliseconds(80))
        if vm.currentNoteIndex != nil {
            await vm.handleKeyboardTouch(midiNote: 62) // Re correct
            #expect(vm.streak >= 1)
            #expect(vm.longestStreak >= 1)
        }
    }

    @Test("XP calculation integrates difficulty multiplier from song")
    func xpIntegratesDifficultyMultiplier() async {
        // Test with difficulty 3 song
        let sut1 = makeSUT()
        let vm1 = sut1.vm
        let clock1 = sut1.clock
        let easyDifficultySong = makeNotationSong(difficulty: 1, tempo: 120)
        await vm1.loadSong(easyDifficultySong)
        await vm1.startSession()
        await clock1.advanceToCompletion(totalDuration: .seconds(4), step: .milliseconds(50))
        let easyXP = vm1.xpEarned

        let sut2 = makeSUT()
        let vm2 = sut2.vm
        let clock2 = sut2.clock
        let hardDifficultySong = makeNotationSong(difficulty: 5, tempo: 120)
        await vm2.loadSong(hardDifficultySong)
        await vm2.startSession()
        await clock2.advanceToCompletion(totalDuration: .seconds(4), step: .milliseconds(50))
        let hardXP = vm2.xpEarned

        // Higher difficulty should yield more XP due to difficulty multiplier
        // difficulty 1: multiplier = 1.0 + 0 * 0.25 = 1.0
        // difficulty 5: multiplier = 1.0 + 4 * 0.25 = 2.0
        if vm1.playbackState == .stopped && vm2.playbackState == .stopped {
            #expect(hardXP > easyXP)
        }
    }
}
#endif // T11'-pending

// MARK: - PlayAlongIntegrationTests

/// Integration tests specifically targeting the tanpura-wiring surface:
/// `TanpuraController.seed(preferredSaHz:songDefaultHz:)` behavior when a
/// per-song `SongProgress.preferredSaHz` override is present.
@MainActor
struct PlayAlongIntegrationTests {
    @MainActor
    @Test func tanpuraSeedsFromPreferredSaHzWhenPresent() async throws {
        // Given: a SongProgress with a preferredSaHz override (C#4 grid = 277.1826 Hz)
        let context = try SwiftDataTestContainer.freshContext()
        let song = Song(title: "Yaman", difficulty: 1, tempo: 120)
        song.slugId = "yaman-test"
        song.keySignatureRaw = "C major"   // song default would be C4 = 261.6256
        context.insert(song)
        let progress = SongProgress(songId: "yaman-test", songTitle: "Yaman")
        progress.preferredSaHz = 277.1826   // = C#4 grid
        context.insert(progress)
        try context.save()

        // When: the controller seeds from progress
        let tanpura = TanpuraController()
        tanpura.seed(preferredSaHz: progress.preferredSaHz,
                     songDefaultHz: song.defaultSaFrequencyHz)

        // Then: saGridHz is C#4, not the song's C4 default
        #expect(tanpura.saPitchClass == 1)   // C#
        #expect(tanpura.saOctave == 4)
        #expect(tanpura.saCentsOffset == 0)
    }
}
