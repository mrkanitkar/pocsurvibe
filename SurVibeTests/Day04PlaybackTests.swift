import Foundation
import SVAudio
import SVCore
import Testing

@testable import SurVibe

// MARK: - PlaybackState Tests

@Suite("Day 4 — PlaybackState Tests")
@MainActor
struct Day04PlaybackStateTests {

    @Test("PlaybackState idle is the default value")
    func idleIsDefault() {
        let state: PlaybackState = .idle
        #expect(state == .idle)
    }

    @Test("PlaybackState all distinct cases are not equal")
    func distinctCasesNotEqual() {
        #expect(PlaybackState.idle != PlaybackState.loading)
        #expect(PlaybackState.loading != PlaybackState.playing)
        #expect(PlaybackState.playing != PlaybackState.paused)
        #expect(PlaybackState.paused != PlaybackState.stopped)
        #expect(PlaybackState.stopped != PlaybackState.idle)
    }

    @Test("PlaybackState error carries message string")
    func errorCarriesMessage() {
        let state: PlaybackState = .error("Something went wrong")
        #expect(state == .error("Something went wrong"))
    }

    @Test("PlaybackState errors with different messages are not equal")
    func differentErrorMessages() {
        #expect(PlaybackState.error("A") != PlaybackState.error("B"))
    }

    @Test("PlaybackState error is not equal to non-error cases")
    func errorNotEqualToOtherCases() {
        let errorState: PlaybackState = .error("fail")
        #expect(errorState != .idle)
        #expect(errorState != .loading)
        #expect(errorState != .playing)
        #expect(errorState != .paused)
        #expect(errorState != .stopped)
    }

    @Test("PlaybackState conforms to Sendable")
    func sendableConformance() {
        let state: PlaybackState = .playing
        let _: any Sendable = state
        #expect(true)
    }
}

// MARK: - SongPlaybackEngine Tests

@Suite("Day 4 — SongPlaybackEngine Tests")
@MainActor
struct Day04SongPlaybackEngineTests {

    @MainActor
    @Test("SongPlaybackEngine initial state is idle with zeroed properties")
    func engineInitialState() {
        let engine = SongPlaybackEngine()
        #expect(engine.playbackState == .idle)
        #expect(engine.currentPosition == 0)
        #expect(engine.duration == 0)
        #expect(engine.midiEvents.isEmpty)
        #expect(engine.songTitle.isEmpty)
        #expect(engine.currentNoteIndex == nil)
        #expect(engine.nextNoteIndex == nil)
    }

    @MainActor
    @Test("SongPlaybackEngine play with no events loaded stays idle")
    func playWithNoEventsIsNoOp() {
        let engine = SongPlaybackEngine()
        engine.play()
        // play() guards on midiEvents.isEmpty — remains idle
        #expect(engine.playbackState == .idle)
    }

    @MainActor
    @Test("SongPlaybackEngine pause from idle is no-op")
    func pauseFromIdleIsNoOp() {
        let engine = SongPlaybackEngine()
        engine.pause()
        #expect(engine.playbackState == .idle)
    }

    @MainActor
    @Test("SongPlaybackEngine resume from idle is no-op")
    func resumeFromIdleIsNoOp() {
        let engine = SongPlaybackEngine()
        engine.resume()
        #expect(engine.playbackState == .idle)
    }

    @MainActor
    @Test("SongPlaybackEngine stop from idle is no-op")
    func stopFromIdleIsNoOp() {
        let engine = SongPlaybackEngine()
        engine.stop()
        #expect(engine.playbackState == .idle)
    }

    @MainActor
    @Test("SongPlaybackEngine load with nil midiData stays idle (notation-only mode)")
    func loadNilMidiData() async {
        let engine = SongPlaybackEngine()
        let song = Song()
        song.midiData = nil
        await engine.load(song: song)
        // Nil MIDI data enters notation-only mode — engine stays idle, no error
        #expect(engine.playbackState == .idle,
                "Expected .idle (notation-only mode) for nil midiData, got \(engine.playbackState)")
    }

    @MainActor
    @Test("SongPlaybackEngine load with empty midiData stays idle (notation-only mode)")
    func loadEmptyMidiData() async {
        let engine = SongPlaybackEngine()
        let song = Song()
        song.midiData = Data()
        await engine.load(song: song)
        // Empty MIDI data enters notation-only mode — engine stays idle, no error
        #expect(engine.playbackState == .idle,
                "Expected .idle (notation-only mode) for empty midiData, got \(engine.playbackState)")
    }

    @MainActor
    @Test("SongPlaybackEngine load captures song title")
    func loadCapturesSongTitle() async {
        let engine = SongPlaybackEngine()
        let song = Song(title: "Twinkle Star")
        await engine.load(song: song)
        #expect(engine.songTitle == "Twinkle Star")
    }

    @MainActor
    @Test("SongPlaybackEngine load with valid MIDI transitions to idle with events")
    func loadValidMidiTransitionsToIdle() async {
        let engine = SongPlaybackEngine()
        let song = Song(title: "Test Song")
        song.midiData = buildMinimalMIDI(noteNumber: 60, velocity: 100, durationTicks: 480)
        await engine.load(song: song)
        #expect(engine.playbackState == .idle)
        #expect(!engine.midiEvents.isEmpty)
        #expect(engine.duration > 0)
        #expect(engine.currentPosition == 0)
        #expect(engine.nextNoteIndex == 0)
    }

    @MainActor
    @Test("SongPlaybackEngine play after successful load transitions to playing")
    func playAfterLoadTransitionsToPlaying() async {
        let engine = SongPlaybackEngine()
        let song = Song(title: "Test Song")
        song.midiData = buildMinimalMIDI(noteNumber: 60, velocity: 100, durationTicks: 480)
        await engine.load(song: song)
        engine.play()
        #expect(engine.playbackState == .playing)
    }

    @MainActor
    @Test("SongPlaybackEngine stop after play resets position to zero")
    func stopResetsPosition() async {
        let engine = SongPlaybackEngine()
        let song = Song(title: "Test Song")
        song.midiData = buildMinimalMIDI(noteNumber: 60, velocity: 100, durationTicks: 480)
        await engine.load(song: song)
        engine.play()
        engine.stop()
        #expect(engine.playbackState == .stopped)
        #expect(engine.currentPosition == 0)
        #expect(engine.currentNoteIndex == nil)
    }

    // MARK: - MIDIEvent Tests (via SVAudio)

    @Test("MIDIEvent stores correct values")
    func midiEventValues() {
        let event = MIDIEvent(noteNumber: 60, velocity: 100, timestamp: 1.5, duration: 0.5)
        #expect(event.noteNumber == 60)
        #expect(event.velocity == 100)
        #expect(event.timestamp == 1.5)
        #expect(event.duration == 0.5)
    }

    @Test("MIDIEvent equality for identical values")
    func midiEventEquality() {
        let event1 = MIDIEvent(noteNumber: 60, velocity: 100, timestamp: 1.0, duration: 0.5)
        let event2 = MIDIEvent(noteNumber: 60, velocity: 100, timestamp: 1.0, duration: 0.5)
        #expect(event1 == event2)
        #expect(event1.hashValue == event2.hashValue)
    }

    @Test("MIDIEvent inequality for different note numbers")
    func midiEventDifferentNotes() {
        let event1 = MIDIEvent(noteNumber: 60, velocity: 100, timestamp: 1.0, duration: 0.5)
        let event2 = MIDIEvent(noteNumber: 62, velocity: 100, timestamp: 1.0, duration: 0.5)
        #expect(event1 != event2)
    }

    @Test("MIDIEvent is Codable via round-trip")
    func midiEventCodable() throws {
        let event = MIDIEvent(noteNumber: 60, velocity: 100, timestamp: 1.5, duration: 0.5)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(MIDIEvent.self, from: data)
        #expect(decoded == event)
    }

    @Test("MIDIEvent conforms to Sendable")
    func midiEventSendable() {
        let event = MIDIEvent(noteNumber: 60, velocity: 100, timestamp: 0.0, duration: 0.5)
        let _: any Sendable = event
        #expect(true)
    }

    // MARK: - AnalyticsEvent Tests (Day 4 new events)

    @Test("Day 4 analytics events have correct raw values")
    func day4AnalyticsEventRawValues() {
        #expect(AnalyticsEvent.doorTapped.rawValue == "door_tapped")
        #expect(AnalyticsEvent.songPlaybackStarted.rawValue == "song_playback_started")
        #expect(AnalyticsEvent.songPlaybackPaused.rawValue == "song_playback_paused")
        #expect(AnalyticsEvent.songPlaybackCompleted.rawValue == "song_playback_completed")
    }

    @Test("AnalyticsEvent conforms to Sendable")
    func analyticsEventSendable() {
        let event = AnalyticsEvent.songPlaybackStarted
        let _: any Sendable = event
        #expect(true)
    }

    @Test("AnalyticsEvent raw values use snake_case convention")
    func analyticsEventSnakeCase() {
        let day4Events: [AnalyticsEvent] = [
            .doorTapped, .songPlaybackStarted, .songPlaybackPaused, .songPlaybackCompleted,
        ]
        for event in day4Events {
            #expect(event.rawValue == event.rawValue.lowercased())
            #expect(!event.rawValue.contains(" "))
        }
    }
}

// MARK: - Test Helpers

/// Build a minimal SMF format 0 MIDI file with a single note.
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
    // 480 = 0x1E0 → VLQ = [0x83, 0x60]
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
