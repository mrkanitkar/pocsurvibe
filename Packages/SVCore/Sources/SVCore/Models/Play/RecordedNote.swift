import Foundation

/// A single note captured by the Play tab scratchpad or a saved take.
///
/// Timing fields are wall-clock seconds relative to the scratchpad/take start
/// (`onTimeSec` is captured in MIDI Phase 1 from `MIDIInputEvent.midiTimestamp`,
/// never via `Date()` on Phase 2 — see Play tab v2 spec §5.2.1).
public struct RecordedNote: Identifiable, Equatable, Sendable, Codable, Hashable {
    public let id: UUID
    public let midi: UInt8
    public let velocity: UInt8
    public let velocity16Bit: UInt16
    public let onTimeSec: TimeInterval
    public let offTimeSec: TimeInterval
    public let channel: UInt8

    /// Creates a recorded note.
    ///
    /// - Parameters:
    ///   - id: Stable identifier; defaults to a fresh `UUID`.
    ///   - midi: MIDI note number (0–127).
    ///   - velocity: 7-bit MIDI velocity (0–127).
    ///   - velocity16Bit: Optional 16-bit MIDI 2.0 velocity; 0 when unavailable.
    ///   - onTimeSec: Note-on time in seconds, relative to scratchpad/take start.
    ///   - offTimeSec: Note-off time in seconds, relative to scratchpad/take start.
    ///   - channel: MIDI channel (0–15); defaults to 0.
    public init(
        id: UUID = UUID(),
        midi: UInt8,
        velocity: UInt8,
        velocity16Bit: UInt16 = 0,
        onTimeSec: TimeInterval,
        offTimeSec: TimeInterval,
        channel: UInt8 = 0
    ) {
        self.id = id
        self.midi = midi
        self.velocity = velocity
        self.velocity16Bit = velocity16Bit
        self.onTimeSec = onTimeSec
        self.offTimeSec = offTimeSec
        self.channel = channel
    }
}
