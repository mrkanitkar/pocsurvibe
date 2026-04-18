import CoreMIDI
import Foundation

/// A MIDI 2.0 per-note controller event received from a live input device.
///
/// Per-note controllers (MIDI 2.0 only) allow independent control of parameters
/// like brightness, pan, or expression on individual notes within a chord.
/// This enables expressive techniques like varying vibrato depth per note.
///
/// `Sendable` value type that safely crosses isolation boundaries between
/// the CoreMIDI high-priority callback thread and the main actor.
public struct MIDIPerNoteControlEvent: Sendable, Equatable {

    /// Whether the controller index refers to a registered or assignable parameter.
    public enum ControlType: Sendable, Equatable {
        /// Registered per-note controller (standardized meaning).
        case registered
        /// Assignable per-note controller (manufacturer-defined meaning).
        case assignable
    }

    /// Target note number (0-127) that this controller applies to.
    public let noteNumber: UInt8

    /// Controller index (0-255). Meaning depends on `controlType`.
    public let index: UInt8

    /// 32-bit controller value.
    public let value: UInt32

    /// Whether this is a registered or assignable per-note controller.
    public let controlType: ControlType

    /// MIDI channel (0-15).
    public let channel: UInt8

    /// Hardware-precise CoreMIDI timestamp (host ticks from `mach_absolute_time`).
    ///
    /// `nil` only when the event was synthesised by a test double.
    public let midiTimestamp: MIDITimeStamp?

    /// Create a MIDI per-note controller event.
    ///
    /// - Parameters:
    ///   - noteNumber: Target note number (0-127).
    ///   - index: Controller index (0-255).
    ///   - value: 32-bit controller value.
    ///   - controlType: Registered or assignable. Defaults to `.registered`.
    ///   - channel: MIDI channel (0-15). Defaults to 0.
    ///   - midiTimestamp: Hardware CoreMIDI timestamp. Defaults to nil.
    public init(
        noteNumber: UInt8,
        index: UInt8,
        value: UInt32,
        controlType: ControlType = .registered,
        channel: UInt8 = 0,
        midiTimestamp: MIDITimeStamp? = nil
    ) {
        self.noteNumber = noteNumber
        self.index = index
        self.value = value
        self.controlType = controlType
        self.channel = channel
        self.midiTimestamp = midiTimestamp
    }
}
