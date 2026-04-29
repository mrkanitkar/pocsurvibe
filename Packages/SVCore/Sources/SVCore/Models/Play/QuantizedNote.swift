import Foundation

/// Staff assignment for a quantized note. Mirrors v1's MIDI ≥60 split.
public enum Staff: String, Sendable, Codable, Hashable, CaseIterable {
    case treble, bass
}

/// A single note after quantization — ready for MusicXML serialization.
///
/// `startBeat` is measured in quarter-note beats from score start; `duration` is
/// a discrete `MusicalDuration`. Voice 1 is reserved for the treble staff and
/// voice 2 for the bass staff to match v1 behavior.
public struct QuantizedNote: Sendable, Codable, Hashable, Equatable {
    public let midi: UInt8
    public let startBeat: Double          // in quarter-note beats from score start
    public let duration: MusicalDuration
    public let velocity: UInt8
    public let staff: Staff               // treble = ≥60, bass = <60 (matches v1 split)
    public let voice: Int                 // 1 for treble, 2 for bass

    /// Creates a quantized note.
    ///
    /// - Parameters:
    ///   - midi: MIDI note number (0–127).
    ///   - startBeat: Start time in quarter-note beats from score start.
    ///   - duration: Discrete musical duration.
    ///   - velocity: 7-bit MIDI velocity (0–127).
    ///   - staff: Treble or bass staff assignment.
    ///   - voice: MusicXML voice number (1 = treble, 2 = bass).
    public init(
        midi: UInt8,
        startBeat: Double,
        duration: MusicalDuration,
        velocity: UInt8,
        staff: Staff,
        voice: Int
    ) {
        self.midi = midi
        self.startBeat = startBeat
        self.duration = duration
        self.velocity = velocity
        self.staff = staff
        self.voice = voice
    }
}
