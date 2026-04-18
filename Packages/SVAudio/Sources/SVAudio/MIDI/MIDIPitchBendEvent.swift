import CoreMIDI
import Foundation

/// Resolution of a pitch bend value, distinguishing MIDI 1.0 and 2.0 precision.
///
/// MIDI 1.0 pitch bend uses 14-bit unsigned values (0-16383, center at 8192).
/// MIDI 2.0 pitch bend uses 32-bit unsigned values (0-4294967295, center at 2147483648).
public enum PitchBendResolution: Sendable, Equatable {
    /// MIDI 1.0: 14-bit pitch bend (0-16383, center 8192).
    case midi1
    /// MIDI 2.0: 32-bit pitch bend (0-4294967295, center 2147483648).
    case midi2
}

/// A MIDI pitch bend event received from a live input device.
///
/// Represents both channel-wide and per-note pitch bend messages. Channel pitch
/// bend applies to all sounding notes on the channel; per-note pitch bend
/// (MIDI 2.0 only) targets a specific note number.
///
/// ## Pitch Bend Range
///
/// The default pitch bend range is +/- 2 semitones (200 cents). Controllers
/// can configure this via RPN 0x0000, but SurVibe uses the default for scoring.
///
/// `Sendable` value type that safely crosses isolation boundaries between
/// the CoreMIDI high-priority callback thread and the main actor.
public struct MIDIPitchBendEvent: Sendable, Equatable {
    /// Raw pitch bend value as a signed 32-bit integer.
    ///
    /// For MIDI 1.0: range -8192 to +8191 (derived from 14-bit unsigned 0-16383, center 8192).
    /// For MIDI 2.0: range -2147483648 to +2147483647 (derived from 32-bit unsigned, center 2^31).
    /// Zero means no bend (center position).
    public let value: Int32

    /// Target note number for per-note pitch bend (MIDI 2.0 only).
    ///
    /// `nil` for channel-wide pitch bend. When non-nil, the bend applies only
    /// to the specified note, leaving other sounding notes unaffected.
    public let noteNumber: UInt8?

    /// MIDI channel (0-15).
    public let channel: UInt8

    /// Hardware-precise CoreMIDI timestamp (host ticks from `mach_absolute_time`).
    ///
    /// `nil` only when the event was synthesised by a test double.
    public let midiTimestamp: MIDITimeStamp?

    /// Whether this is a per-note pitch bend (MIDI 2.0) rather than channel-wide.
    public var isPerNote: Bool { noteNumber != nil }

    /// Resolution of the raw pitch bend value.
    public let resolution: PitchBendResolution

    /// Create a MIDI pitch bend event.
    ///
    /// - Parameters:
    ///   - value: Signed pitch bend value (centered at 0).
    ///   - noteNumber: Target note for per-note bend, or nil for channel bend.
    ///   - channel: MIDI channel (0-15). Defaults to 0.
    ///   - midiTimestamp: Hardware CoreMIDI timestamp. Defaults to nil.
    ///   - resolution: Pitch bend resolution. Defaults to `.midi2`.
    public init(
        value: Int32,
        noteNumber: UInt8? = nil,
        channel: UInt8 = 0,
        midiTimestamp: MIDITimeStamp? = nil,
        resolution: PitchBendResolution = .midi2
    ) {
        self.value = value
        self.noteNumber = noteNumber
        self.channel = channel
        self.midiTimestamp = midiTimestamp
        self.resolution = resolution
    }

    /// Convert the raw pitch bend value to cents deviation.
    ///
    /// Maps the signed bend value to cents using the specified bend range.
    /// At +/- 2 semitones (default), full bend = +/- 200 cents.
    ///
    /// - Parameter bendRangeSemitones: Pitch bend range in semitones. Defaults to 2.0.
    /// - Returns: Pitch deviation in cents from the unbent pitch.
    public func toCents(bendRangeSemitones: Double = 2.0) -> Double {
        let rangeCents = bendRangeSemitones * 100.0
        switch resolution {
        case .midi1:
            // 14-bit: value range -8192 to +8191
            return (Double(value) / 8192.0) * rangeCents
        case .midi2:
            // 32-bit: value range -2^31 to +2^31-1
            return (Double(value) / 2_147_483_648.0) * rangeCents
        }
    }
}
