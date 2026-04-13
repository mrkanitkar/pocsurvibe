import CoreMIDI
import Foundation

/// A single MIDI Control Change event received from a live input device.
///
/// Separate from `MIDIInputEvent` because CC messages represent controller
/// state (sustain pedal, modulation wheel, volume, etc.) rather than note
/// events. Keeping them as distinct types prevents consumers from
/// accidentally treating a CC as a note or vice versa.
///
/// `Sendable` value type that safely crosses isolation boundaries between
/// the CoreMIDI high-priority callback thread and the main actor.
public struct MIDIControlChangeEvent: Sendable, Equatable {
    /// MIDI controller number (0-127). Common values:
    /// - 1: Modulation wheel
    /// - 7: Channel volume
    /// - 64: Sustain pedal (damper)
    /// - 67: Soft pedal
    public let controller: UInt8

    /// Controller value (0-127).
    ///
    /// For binary controllers like sustain pedal (CC64):
    /// - Values >= 64 mean "on" (pedal down).
    /// - Values < 64 mean "off" (pedal up).
    public let value: UInt8

    /// MIDI channel (0-15).
    public let channel: UInt8

    /// Hardware-precise CoreMIDI timestamp (host ticks from `mach_absolute_time`).
    ///
    /// Captured directly from the `MIDIEventPacket.timeStamp` field.
    /// `nil` only when the event was synthesised by a test double.
    public let midiTimestamp: MIDITimeStamp?

    /// System time when the event was received.
    public let timestamp: Date

    /// Create a MIDI Control Change event.
    ///
    /// - Parameters:
    ///   - controller: MIDI controller number (0-127).
    ///   - value: Controller value (0-127).
    ///   - channel: MIDI channel (0-15).
    ///   - midiTimestamp: Hardware CoreMIDI timestamp. Defaults to nil.
    ///   - timestamp: Wall-clock event timestamp. Defaults to now.
    public init(
        controller: UInt8,
        value: UInt8,
        channel: UInt8 = 0,
        midiTimestamp: MIDITimeStamp? = nil,
        timestamp: Date = Date()
    ) {
        self.controller = controller
        self.value = value
        self.channel = channel
        self.midiTimestamp = midiTimestamp
        self.timestamp = timestamp
    }
}

// MARK: - Sustain Pedal Convenience

extension MIDIControlChangeEvent {
    /// Whether this event is a sustain pedal (CC64) message.
    public var isSustainPedal: Bool { controller == 64 }

    /// Whether the sustain pedal is pressed (value >= 64).
    ///
    /// Per MIDI specification, CC64 values >= 64 mean pedal down,
    /// values < 64 mean pedal up. This threshold applies to all
    /// binary (switch) controllers.
    public var isSustainDown: Bool { controller == 64 && value >= 64 }
}
