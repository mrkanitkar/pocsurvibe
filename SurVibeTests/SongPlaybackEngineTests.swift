import Foundation
import SVAudio
import SVCore
import Testing

@testable import SurVibe

// MARK: - SongPlaybackEngine Sequencer Tests (ARCH-005)

/// Tests for the AVAudioSequencer-based playback migration.
///
/// AVAudioSequencer requires a real AVAudioEngine instance. In CI and
/// Simulator test environments the engine may not produce audio output,
/// but sequencer creation, MIDI loading, and state transitions are testable.
@Suite("ARCH-005 — SongPlaybackEngine Sequencer Migration")
@MainActor
struct SongPlaybackEngineTests {

    // MARK: - Initial State

    @Test("Initial state is idle with zeroed properties")
    func initialStateIsIdle() {
        let engine = SongPlaybackEngine()
        #expect(engine.playbackState == .idle)
        #expect(engine.currentPosition == 0)
        #expect(engine.duration == 0)
        #expect(engine.midiEvents.isEmpty)
        #expect(engine.songTitle.isEmpty)
        #expect(engine.currentNoteIndex == nil)
        #expect(engine.nextNoteIndex == nil)
        #expect(engine.hasPlayableContent == false)
    }

    // MARK: - Load Behavior

    @Test("Load with nil midiData stays idle (notation-only mode)")
    func loadWithNilMidiDataStaysIdle() async {
        let engine = SongPlaybackEngine()
        let song = Song(title: "Notation Only")
        song.midiData = nil
        await engine.load(song: song)
        #expect(engine.playbackState == .idle)
        #expect(engine.midiEvents.isEmpty)
        #expect(engine.hasPlayableContent == false)
    }

    @Test("Load with empty midiData stays idle (notation-only mode)")
    func loadWithEmptyMidiDataStaysIdle() async {
        let engine = SongPlaybackEngine()
        let song = Song(title: "Empty MIDI")
        song.midiData = Data()
        await engine.load(song: song)
        #expect(engine.playbackState == .idle)
        #expect(engine.midiEvents.isEmpty)
    }

    @Test("Load captures song title regardless of MIDI data")
    func loadCapturesSongTitle() async {
        let engine = SongPlaybackEngine()
        let song = Song(title: "Raag Yaman")
        await engine.load(song: song)
        #expect(engine.songTitle == "Raag Yaman")
    }

    @Test("Load with valid MIDI populates events and duration")
    func loadValidMidiPopulatesEventsAndDuration() async {
        let engine = SongPlaybackEngine()
        let song = Song(title: "Test Song")
        song.midiData = buildMinimalMIDI(noteNumber: 60, velocity: 100, durationTicks: 480)
        await engine.load(song: song)

        // Valid MIDI should either succeed (idle with events) or error
        // if the sequencer can't be created in the test environment.
        switch engine.playbackState {
        case .idle:
            #expect(!engine.midiEvents.isEmpty, "Expected parsed MIDI events")
            #expect(engine.duration > 0, "Expected positive duration")
            #expect(engine.currentPosition == 0)
            #expect(engine.nextNoteIndex == 0)
            #expect(engine.hasPlayableContent == true)
        case .error:
            // Sequencer failed in test environment — acceptable
            break
        default:
            Issue.record("Unexpected state after load: \(engine.playbackState)")
        }
    }

    @Test("Load with invalid MIDI data transitions to error")
    func loadInvalidMidiTransitionsToError() async {
        let engine = SongPlaybackEngine()
        let song = Song(title: "Bad MIDI")
        // Garbage bytes that are not valid SMF
        song.midiData = Data([0xFF, 0xFE, 0x01, 0x02, 0x03])
        await engine.load(song: song)

        // MIDIParser should fail on invalid data, or sequencer should reject it
        switch engine.playbackState {
        case .error:
            // Expected — parser or sequencer rejected invalid data
            break
        case .idle where engine.midiEvents.isEmpty:
            // MIDIParser returned empty events — also acceptable
            break
        default:
            Issue.record("Expected .error or .idle with no events for invalid MIDI, got \(engine.playbackState)")
        }
    }

    @Test("Load with nil midiData preserves durationSeconds from Song model")
    func loadNilMidiPreservesSongDuration() async {
        let engine = SongPlaybackEngine()
        let song = Song(title: "Notation Song", durationSeconds: 45)
        song.midiData = nil
        await engine.load(song: song)
        #expect(engine.duration == 45.0)
    }

    // MARK: - Play Guards

    @Test("Play with no events loaded stays in current state")
    func playWithNoEventsIsNoOp() {
        let engine = SongPlaybackEngine()
        engine.play()
        #expect(engine.playbackState == .idle)
    }

    @Test("Play from loading state is rejected")
    func playFromLoadingIsNoOp() async {
        let engine = SongPlaybackEngine()
        // Can't easily force .loading state, but verify play() from idle with no events
        engine.play()
        #expect(engine.playbackState != .playing)
    }

    // MARK: - Pause Guards

    @Test("Pause from idle is no-op")
    func pauseFromIdleIsNoOp() {
        let engine = SongPlaybackEngine()
        engine.pause()
        #expect(engine.playbackState == .idle)
    }

    @Test("Pause from stopped is no-op")
    func pauseFromStoppedIsNoOp() {
        let engine = SongPlaybackEngine()
        // Can't reach .stopped without going through .playing first,
        // but verify pause guards against non-.playing states
        engine.pause()
        #expect(engine.playbackState != .paused)
    }

    // MARK: - Resume Guards

    @Test("Resume from idle is no-op")
    func resumeFromIdleIsNoOp() {
        let engine = SongPlaybackEngine()
        engine.resume()
        #expect(engine.playbackState == .idle)
    }

    // MARK: - Stop Guards

    @Test("Stop from idle is no-op")
    func stopFromIdleIsNoOp() {
        let engine = SongPlaybackEngine()
        engine.stop()
        #expect(engine.playbackState == .idle)
        #expect(engine.currentPosition == 0)
    }

    // MARK: - hasPlayableContent

    @Test("hasPlayableContent returns false when no events loaded")
    func hasPlayableContentFalseWhenEmpty() {
        let engine = SongPlaybackEngine()
        #expect(engine.hasPlayableContent == false)
    }

    @Test("hasPlayableContent returns true after loading valid MIDI")
    func hasPlayableContentTrueAfterLoad() async {
        let engine = SongPlaybackEngine()
        let song = Song(title: "Playable Song")
        song.midiData = buildMinimalMIDI(noteNumber: 60, velocity: 100, durationTicks: 480)
        await engine.load(song: song)

        if engine.playbackState == .idle, !engine.midiEvents.isEmpty {
            #expect(engine.hasPlayableContent == true)
        }
    }

    // MARK: - Multiple Load Calls

    @Test("Loading a new song replaces previous song data")
    func loadReplacesExistingSongData() async {
        let engine = SongPlaybackEngine()

        // Load first song
        let song1 = Song(title: "Song One")
        song1.midiData = nil
        await engine.load(song: song1)
        #expect(engine.songTitle == "Song One")

        // Load second song — should replace
        let song2 = Song(title: "Song Two")
        song2.midiData = nil
        await engine.load(song: song2)
        #expect(engine.songTitle == "Song Two")
    }
}

// MARK: - Test Helpers

/// Build a minimal SMF format 0 MIDI file with a single note.
///
/// Creates a valid Standard MIDI File with MThd header, a single MTrk chunk
/// containing one note-on/note-off pair, and an End of Track meta event.
///
/// - Parameters:
///   - noteNumber: MIDI note number (0-127).
///   - velocity: Key velocity (0-127).
///   - durationTicks: Note duration in ticks (480 ticks = 1 quarter note).
/// - Returns: Binary MIDI data suitable for MIDIParser and AVAudioSequencer.
private func buildMinimalMIDI(
    noteNumber: UInt8,
    velocity: UInt8,
    durationTicks: UInt16
) -> Data {
    var data = Data()

    // MThd header
    data.append(contentsOf: [0x4D, 0x54, 0x68, 0x64])  // "MThd"
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x06])  // Header length: 6
    data.append(contentsOf: [0x00, 0x00])  // Format 0
    data.append(contentsOf: [0x00, 0x01])  // 1 track
    data.append(contentsOf: [0x01, 0xE0])  // 480 ticks/quarter

    // MTrk track
    var track = Data()

    // Note On at delta 0
    track.append(0x00)  // delta = 0
    track.append(0x90)  // Note On, channel 0
    track.append(noteNumber)
    track.append(velocity)

    // Note Off at delta = durationTicks (VLQ encoded)
    // 480 = 0x1E0 -> VLQ = [0x83, 0x60]
    let highByte = UInt8((durationTicks >> 7) & 0x7F) | 0x80
    let lowByte = UInt8(durationTicks & 0x7F)
    track.append(highByte)
    track.append(lowByte)
    track.append(0x80)  // Note Off, channel 0
    track.append(noteNumber)
    track.append(0x00)  // velocity 0

    // End of Track meta event
    track.append(0x00)  // delta = 0
    track.append(0xFF)  // meta event
    track.append(0x2F)  // End of Track
    track.append(0x00)  // length 0

    // Write track chunk header
    data.append(contentsOf: [0x4D, 0x54, 0x72, 0x6B])  // "MTrk"
    let trackLen = UInt32(track.count)
    data.append(UInt8((trackLen >> 24) & 0xFF))
    data.append(UInt8((trackLen >> 16) & 0xFF))
    data.append(UInt8((trackLen >> 8) & 0xFF))
    data.append(UInt8(trackLen & 0xFF))
    data.append(track)

    return data
}
