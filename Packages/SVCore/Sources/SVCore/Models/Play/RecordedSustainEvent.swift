import Foundation

/// CC 64 (sustain pedal) event captured alongside notes.
///
/// `down == true` corresponds to a CC64 value ≥ 64 (pedal pressed); `down == false`
/// corresponds to CC64 < 64 (pedal released). Timing is in seconds relative to
/// the scratchpad/take start.
public struct RecordedSustainEvent: Sendable, Codable, Hashable, Equatable {
    public let timeSec: TimeInterval
    public let down: Bool          // ≥64 = down, <64 = up
    public let channel: UInt8

    /// Creates a sustain pedal event.
    ///
    /// - Parameters:
    ///   - timeSec: Event time in seconds, relative to scratchpad/take start.
    ///   - down: True if CC64 ≥ 64 (pedal down), false otherwise.
    ///   - channel: MIDI channel (0–15); defaults to 0.
    public init(timeSec: TimeInterval, down: Bool, channel: UInt8 = 0) {
        self.timeSec = timeSec
        self.down = down
        self.channel = channel
    }
}
