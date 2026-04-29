import Foundation
import SVCore

/// Immutable snapshot of a take used by `TakePlaybackEngine`.
///
/// A snapshot is a Sendable value type so it can be passed across
/// isolation boundaries (constructed on the main actor from the live
/// `ScratchpadState`/`RecordedTake`, then read on the audio thread once
/// loaded into `AVAudioSequencer`). Times are wall-clock seconds relative
/// to the take's start; `AVAudioSequencer` interprets them via the
/// `MIDISerializer` tempo meta event (60 BPM, PPQ 1000 ⇒ 1 tick = 1 ms).
public struct TakeSnapshot: Sendable {
    /// Recorded notes in the take.
    public let notes: [RecordedNote]
    /// CC64 sustain-pedal events in the take.
    public let sustain: [RecordedSustainEvent]
    /// General MIDI program number used when scheduling on slot 2.
    public let instrumentProgram: UInt8
    /// MIDI note number representing Sa for this take (e.g. 60 = C4).
    public let saPitchMidi: UInt8

    /// Creates a take snapshot.
    ///
    /// - Parameters:
    ///   - notes: Recorded notes.
    ///   - sustain: CC64 sustain events.
    ///   - instrumentProgram: GM program number (0–127).
    ///   - saPitchMidi: Sa pitch in MIDI (e.g. 60 = C4).
    public init(
        notes: [RecordedNote],
        sustain: [RecordedSustainEvent],
        instrumentProgram: UInt8,
        saPitchMidi: UInt8
    ) {
        self.notes = notes
        self.sustain = sustain
        self.instrumentProgram = instrumentProgram
        self.saPitchMidi = saPitchMidi
    }
}

/// Hand-filter applied during scheduling.
///
/// Splits at MIDI 60 (Middle C / Sa@C4): treble = `>= 60`, bass = `< 60`.
public enum HandFilter: Sendable {
    /// Schedule every note in the snapshot.
    case both
    /// Schedule only notes with MIDI >= 60.
    case trebleOnly
    /// Schedule only notes with MIDI < 60.
    case bassOnly
}
