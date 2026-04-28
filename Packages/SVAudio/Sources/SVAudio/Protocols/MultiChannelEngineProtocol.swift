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
