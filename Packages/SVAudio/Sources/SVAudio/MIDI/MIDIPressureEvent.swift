import CoreMIDI
import Foundation

/// A MIDI pressure (aftertouch) event received from a live input device.
///
/// Represents both polyphonic key pressure (per-note) and channel pressure
/// (affects all notes on the channel). Polyphonic aftertouch carries a
/// `noteNumber`; channel aftertouch does not.
///
/// ## Resolution
///
/// MIDI 1.0 aftertouch uses 7-bit values (0-127). MIDI 2.0 uses 32-bit
/// values (0-4294967295). The `pressure7Bit` computed property normalizes
/// 32-bit values to 7-bit for compatibility with existing pipelines.
///
/// `Sendable` value type that safely crosses isolation boundaries between
/// the CoreMIDI high-priority callback thread and the main actor.
public struct MIDIPressureEvent: Sendable, Equatable {
    /// Target note number for polyphonic aftertouch.
    ///
    /// `nil` for channel pressure (applies to all notes on the channel).
    /// Non-nil for polyphonic key pressure (applies to a specific note).
    public let noteNumber: UInt8?

    /// Raw pressure value (0-4294967295 for MIDI 2.0, 0-127 for MIDI 1.0).
    ///
    /// Full 32-bit range for MIDI 2.0 messages. MIDI 1.0 values are
    /// stored left-shifted to fill the 32-bit range (value << 25).
    public let pressure: UInt32

    /// MIDI channel (0-15).
    public let channel: UInt8

    /// Hardware-precise CoreMIDI timestamp (host ticks from `mach_absolute_time`).
    ///
    /// `nil` only when the event was synthesised by a test double.
    public let midiTimestamp: MIDITimeStamp?

    /// Whether this is a per-note (polyphonic) pressure event.
    ///
    /// `true` when `noteNumber` is non-nil (poly aftertouch).
    /// `false` when `noteNumber` is nil (channel aftertouch).
    public var isPerNote: Bool { noteNumber != nil }

    /// Pressure value normalized to 7-bit range (0-127).
    ///
    /// Extracts the top 7 bits from the 32-bit pressure value for
    /// compatibility with MIDI 1.0 consumers and display purposes.
    public var pressure7Bit: UInt8 {
        UInt8(pressure >> 25)
    }

    /// Create a MIDI pressure event.
    ///
    /// - Parameters:
    ///   - noteNumber: Target note for poly aftertouch, or nil for channel pressure.
    ///   - pressure: Raw pressure value. Range depends on source resolution.
    ///   - channel: MIDI channel (0-15). Defaults to 0.
    ///   - midiTimestamp: Hardware CoreMIDI timestamp. Defaults to nil.
    public init(
        noteNumber: UInt8? = nil,
        pressure: UInt32,
        channel: UInt8 = 0,
        midiTimestamp: MIDITimeStamp? = nil
    ) {
        self.noteNumber = noteNumber
        self.pressure = pressure
        self.channel = channel
        self.midiTimestamp = midiTimestamp
    }
}
