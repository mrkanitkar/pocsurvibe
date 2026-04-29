// Packages/SVAudio/Sources/SVAudio/Protocols/MultiChannelEngineProtocol.swift
import Foundation

/// Protocol exposing the production multi-channel audio engine surface used by
/// Play-Along, Song Playback, Practice listen-first, Interactive Piano, and
/// Isomorphic Sargam features. The concrete implementation is
/// `ProductionMultiChannelEngine`. Test doubles conform inline.
@MainActor
public protocol MultiChannelEngineProtocol: AnyObject {

    // MARK: - Touch input
    /// Trigger a note on `samplers[0]` (Acoustic Grand). Velocity defaults to 100.
    func playTouchNote(_ midiNote: UInt8, velocity: UInt8)
    /// Stop a note on `samplers[0]`.
    func stopTouchNote(_ midiNote: UInt8)
    /// Stop every active note on the touch sampler.
    func stopAllTouchNotes()

    // MARK: - Song lifecycle
    /// Load a song from raw MIDI or MusicXML bytes. Replaces any currently-loaded song.
    /// `.musicXML` runs through `VerovioBridge` (~5–6 s); `.midi` is fast (~70 ms).
    func loadSong(source: MIDISource) async throws
    /// Unload current song. Stops sequencer, resets position. Samplers stay attached + warm.
    func unloadSong()
    /// Metadata for the loaded song; nil before first load and after `unloadSong`.
    var currentSong: SongHandle? { get }

    // MARK: - Transport
    func play() throws
    func pause()
    func stop()
    var isPlaying: Bool { get }
    var currentPositionInSeconds: TimeInterval { get }

    // MARK: - Tempo (TimePitch — pitch preserved)
    /// Set playback rate (0.5...1.5 — clamped if outside).
    func setRate(_ rate: Float)
    var rate: Float { get }

    // MARK: - Memory pressure
    /// Reset samplers[1..15] (free their loaded SF2 program data). Only when no song playing.
    func flushSongPrograms()

    // MARK: - Direct slot dispatch (v2 — take playback uses AVAudioSequencer; this
    // surface is for fallback / one-shot dispatch scenarios.)

    /// Trigger a note on `samplers[slot]`.
    ///
    /// Used by Play tab v2 take playback (slot 2) and other one-shot dispatch
    /// scenarios that bypass `AVAudioSequencer`.
    ///
    /// - Parameters:
    ///   - slot: Sampler slot index (0...15). Out-of-range values are ignored.
    ///   - midi: MIDI note number (0–127).
    ///   - velocity: Key velocity (0–127).
    ///   - channel: MIDI channel (0–15).
    func playNoteOnSlot(_ slot: Int, midi: UInt8, velocity: UInt8, channel: UInt8)

    /// Stop a note on `samplers[slot]`.
    ///
    /// - Parameters:
    ///   - slot: Sampler slot index (0...15). Out-of-range values are ignored.
    ///   - midi: MIDI note number to stop (0–127).
    ///   - channel: MIDI channel (0–15).
    func stopNoteOnSlot(_ slot: Int, midi: UInt8, channel: UInt8)

    /// Send All Notes Off (CC 123) across every channel on `samplers[slot]`.
    ///
    /// - Parameter slot: Sampler slot index (0...15). Out-of-range values are ignored.
    func allNotesOffOnSlot(_ slot: Int)

    /// Send a Control Change message to `samplers[slot]`.
    ///
    /// - Parameters:
    ///   - slot: Sampler slot index (0...15). Out-of-range values are ignored.
    ///   - controller: MIDI controller number (0–127, e.g. 64 = sustain).
    ///   - value: Controller value (0–127).
    ///   - channel: MIDI channel (0–15).
    func sendControlChangeOnSlot(_ slot: Int, controller: UInt8, value: UInt8, channel: UInt8)
}

/// Default no-op implementations so existing conformers (mocks / test doubles)
/// keep compiling without modification. Production conformers override these.
public extension MultiChannelEngineProtocol {
    func playNoteOnSlot(_ slot: Int, midi: UInt8, velocity: UInt8, channel: UInt8) {}
    func stopNoteOnSlot(_ slot: Int, midi: UInt8, channel: UInt8) {}
    func allNotesOffOnSlot(_ slot: Int) {}
    func sendControlChangeOnSlot(_ slot: Int, controller: UInt8, value: UInt8, channel: UInt8) {}
}

/// Per-song metadata returned to callers.
public struct SongHandle: Sendable, Equatable {
    public let trackCount: Int
    public let durationSeconds: TimeInterval
    /// GM program per track (track 0 → programs[0]).
    public let programs: [UInt8]

    public init(trackCount: Int, durationSeconds: TimeInterval, programs: [UInt8]) {
        self.trackCount = trackCount
        self.durationSeconds = durationSeconds
        self.programs = programs
    }
}
