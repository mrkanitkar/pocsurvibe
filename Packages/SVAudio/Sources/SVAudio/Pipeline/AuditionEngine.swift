import AVFoundation
import Foundation

/// One MIDI event passed from a producer (CoreMIDI receive callback,
/// MIDI file parser, etc.) to a renderer's audio thread via a lock-free ring.
///
/// Distinct from the higher-level `MIDIEvent` (Playback/MIDIEvent.swift), which
/// represents a parsed score-time note with duration. `RealtimeMIDIEvent`
/// carries the five raw MIDI bytes plus a host-time timestamp, sized for
/// fixed-stride ring-buffer storage on the realtime audio path.
public struct RealtimeMIDIEvent: Sendable, Equatable {
    public let timestamp: UInt64   // host-time ticks; 0 = "as soon as possible"
    public let channel: UInt8      // 0-15 (low nibble of MIDI status)
    public let status: UInt8       // full MIDI status byte (e.g. 0x90 = note on ch 0)
    public let data1: UInt8        // first data byte (note number, controller, etc.)
    public let data2: UInt8        // second data byte (velocity, value, etc.)

    public init(
        timestamp: UInt64, channel: UInt8, status: UInt8, data1: UInt8, data2: UInt8
    ) {
        self.timestamp = timestamp
        self.channel = channel
        self.status = status
        self.data1 = data1
        self.data2 = data2
    }
}

/// Which synth engine drives the audition pipeline. Persisted in the
/// rawValue (UserDefaults / log lines) so add new cases at the end.
public enum EngineKind: String, CaseIterable, Sendable, Identifiable {
    case apple = "apple"
    case fluidsynth = "fluidsynth"

    public var id: String { rawValue }

    /// Label shown in the SwiftUI picker.
    public var displayName: String {
        switch self {
        case .apple: return "Apple AVAudioUnitSampler"
        case .fluidsynth: return "FluidSynth 2.5"
        }
    }
}

/// One renderer the audition pipeline can hand a `RenderedMIDI` to.
/// Each implementation owns its own internal node graph and MIDI plumbing;
/// the pipeline coordinator only sees the `output` node it should hook
/// into the downstream `AVAudioUnitTimePitch`.
@MainActor
public protocol AuditionEngine: AnyObject {
    /// Picker label (typically `kind.displayName`).
    var displayName: String { get }

    /// The single `AVAudioNode` this engine exposes to the pipeline. Must
    /// be attached to `AudioEngineManager.shared.engine` by the time
    /// `setup(rendered:bankURL:)` returns.
    var output: AVAudioNode { get }

    /// Whether the underlying sequencer is currently producing audio.
    var isPlaying: Bool { get }

    /// Allocate samplers/voices, load `bankURL`, route MIDI from `rendered`
    /// into the engine's internal MIDI dispatch, and attach `output`.
    func setup(rendered: RenderedMIDI, bankURL: URL) throws

    /// Swap the loaded SF2 to a new bank using the same per-track programs
    /// captured in the previous `setup`. Used when the user toggles A↔B.
    func loadBank(_ bankURL: URL) throws

    /// Start sequencer playback.
    func play() throws

    /// Pause without resetting position.
    func pause()

    /// Stop and reset to start of sequence.
    func stop()

    /// Detach all nodes from the shared engine. Idempotent.
    func tearDown()

    /// Single-line snapshot for `pipeline_log.txt`. Engines should include
    /// preset assignments, voice counts, render-block stats, etc.
    func diagnosticSummary() -> String
}

/// Builds an `AuditionEngine` given a kind. Centralising construction here
/// keeps the SwiftUI section ignorant of the concrete types and lets future
/// engines (SF2Lib in Phase 2) be added with one switch arm.
@MainActor
public enum AuditionEngineFactory {
    public static func make(kind: EngineKind) -> AuditionEngine {
        fatalError("Engine '\(kind.rawValue)' not yet implemented")
    }
}
