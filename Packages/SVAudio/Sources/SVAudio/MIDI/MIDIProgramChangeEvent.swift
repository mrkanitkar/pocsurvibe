import CoreMIDI
import Foundation

/// A MIDI program change event received from a live input device.
///
/// Carries the selected program (instrument) number and optional bank select
/// information. In MIDI 2.0, program change and bank select are combined into
/// a single atomic message via `MIDI2ProgramChange()`.
///
/// `Sendable` value type that safely crosses isolation boundaries between
/// the CoreMIDI high-priority callback thread and the main actor.
public struct MIDIProgramChangeEvent: Sendable, Equatable {
    /// Program number (0-127). Selects the instrument/patch.
    public let program: UInt8

    /// Bank select MSB (CC0). Valid only when `bankIsValid` is `true`.
    public let bankMSB: UInt8

    /// Bank select LSB (CC32). Valid only when `bankIsValid` is `true`.
    public let bankLSB: UInt8

    /// Whether the bank select values are valid.
    ///
    /// In MIDI 2.0, the program change message carries a flag indicating
    /// whether bank select is present. When `false`, `bankMSB` and `bankLSB`
    /// should be ignored (they default to 0).
    public let bankIsValid: Bool

    /// MIDI channel (0-15).
    public let channel: UInt8

    /// Hardware-precise CoreMIDI timestamp (host ticks from `mach_absolute_time`).
    ///
    /// `nil` only when the event was synthesised by a test double.
    public let midiTimestamp: MIDITimeStamp?

    /// Create a MIDI program change event.
    ///
    /// - Parameters:
    ///   - program: Program number (0-127).
    ///   - bankMSB: Bank select MSB. Defaults to 0.
    ///   - bankLSB: Bank select LSB. Defaults to 0.
    ///   - bankIsValid: Whether bank select is present. Defaults to false.
    ///   - channel: MIDI channel (0-15). Defaults to 0.
    ///   - midiTimestamp: Hardware CoreMIDI timestamp. Defaults to nil.
    public init(
        program: UInt8,
        bankMSB: UInt8 = 0,
        bankLSB: UInt8 = 0,
        bankIsValid: Bool = false,
        channel: UInt8 = 0,
        midiTimestamp: MIDITimeStamp? = nil
    ) {
        self.program = program
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.bankIsValid = bankIsValid
        self.channel = channel
        self.midiTimestamp = midiTimestamp
    }
}
