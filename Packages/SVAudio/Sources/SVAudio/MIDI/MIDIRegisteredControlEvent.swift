import CoreMIDI
import Foundation

/// A MIDI 2.0 registered or assignable controller event received from a live input device.
///
/// Replaces the MIDI 1.0 RPN/NRPN CC sequence (CC99/98/6/38) with a single
/// atomic message. Includes registered, assignable, and their relative variants.
///
/// Common registered parameters:
/// - Bank 0, Index 0: Pitch Bend Sensitivity
/// - Bank 0, Index 1: Fine Tuning
/// - Bank 0, Index 2: Coarse Tuning
///
/// `Sendable` value type that safely crosses isolation boundaries between
/// the CoreMIDI high-priority callback thread and the main actor.
public struct MIDIRegisteredControlEvent: Sendable, Equatable {

    /// Type of registered/assignable controller message.
    public enum ControlType: Sendable, Equatable {
        /// Registered Parameter Number (standardized by MMA).
        case registered
        /// Assignable (Non-Registered) Parameter Number (manufacturer-defined).
        case assignable
        /// Relative Registered Parameter Number (delta change).
        case relativeRegistered
        /// Relative Assignable Parameter Number (delta change).
        case relativeAssignable
    }

    /// Parameter bank number (0-127).
    public let bank: UInt8

    /// Parameter index within the bank (0-127).
    public let index: UInt8

    /// 32-bit parameter value (absolute or relative depending on `controlType`).
    public let value: UInt32

    /// Type of controller message.
    public let controlType: ControlType

    /// MIDI channel (0-15).
    public let channel: UInt8

    /// Hardware-precise CoreMIDI timestamp (host ticks from `mach_absolute_time`).
    ///
    /// `nil` only when the event was synthesised by a test double.
    public let midiTimestamp: MIDITimeStamp?

    /// Create a MIDI registered/assignable controller event.
    ///
    /// - Parameters:
    ///   - bank: Parameter bank number (0-127).
    ///   - index: Parameter index (0-127).
    ///   - value: 32-bit parameter value.
    ///   - controlType: Message type. Defaults to `.registered`.
    ///   - channel: MIDI channel (0-15). Defaults to 0.
    ///   - midiTimestamp: Hardware CoreMIDI timestamp. Defaults to nil.
    public init(
        bank: UInt8,
        index: UInt8,
        value: UInt32,
        controlType: ControlType = .registered,
        channel: UInt8 = 0,
        midiTimestamp: MIDITimeStamp? = nil
    ) {
        self.bank = bank
        self.index = index
        self.value = value
        self.controlType = controlType
        self.channel = channel
        self.midiTimestamp = midiTimestamp
    }
}
