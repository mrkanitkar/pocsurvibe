import CoreMIDI
import Foundation

/// A MIDI 2.0 per-note management event received from a live input device.
///
/// Controls per-note articulation management: detaching a note from shared
/// controllers or resetting per-note controllers to default values. Used by
/// expressive MIDI controllers (MPE, MIDI 2.0) for independent note control.
///
/// `Sendable` value type that safely crosses isolation boundaries between
/// the CoreMIDI high-priority callback thread and the main actor.
public struct MIDIPerNoteManagementEvent: Sendable, Equatable {
    /// Target note number (0-127) to manage.
    public let noteNumber: UInt8

    /// Detach the note from shared (channel-level) controllers.
    ///
    /// When `true`, the note no longer responds to channel-wide pitch bend,
    /// pressure, or CC changes. It retains its current values until explicitly
    /// changed by per-note messages.
    public let detach: Bool

    /// Reset all per-note controllers to their default values.
    ///
    /// When `true`, per-note pitch bend, per-note CC, and per-note pressure
    /// are reset to their default (center/zero) values.
    public let reset: Bool

    /// MIDI channel (0-15).
    public let channel: UInt8

    /// Hardware-precise CoreMIDI timestamp (host ticks from `mach_absolute_time`).
    ///
    /// `nil` only when the event was synthesised by a test double.
    public let midiTimestamp: MIDITimeStamp?

    /// Create a MIDI per-note management event.
    ///
    /// - Parameters:
    ///   - noteNumber: Target note number (0-127).
    ///   - detach: Whether to detach from shared controllers. Defaults to false.
    ///   - reset: Whether to reset per-note controllers. Defaults to false.
    ///   - channel: MIDI channel (0-15). Defaults to 0.
    ///   - midiTimestamp: Hardware CoreMIDI timestamp. Defaults to nil.
    public init(
        noteNumber: UInt8,
        detach: Bool = false,
        reset: Bool = false,
        channel: UInt8 = 0,
        midiTimestamp: MIDITimeStamp? = nil
    ) {
        self.noteNumber = noteNumber
        self.detach = detach
        self.reset = reset
        self.channel = channel
        self.midiTimestamp = midiTimestamp
    }
}
