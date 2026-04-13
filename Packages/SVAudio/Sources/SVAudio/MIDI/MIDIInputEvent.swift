import CoreMIDI
import Foundation

/// A single MIDI note event received from a live input device.
///
/// `Sendable` value type that safely crosses isolation boundaries between
/// the CoreMIDI high-priority callback thread and the main actor.
public struct MIDIInputEvent: Sendable, Equatable {
    /// MIDI note number (0–127). Middle C (C4) = 60.
    public let noteNumber: UInt8

    /// Note velocity (1–127 for note-on, 0 means note-off).
    /// A velocity of 0 on a note-on message is equivalent to note-off.
    public let velocity: UInt8

    /// Whether this is a note-on event (true) or note-off event (false).
    public var isNoteOn: Bool { velocity > 0 }

    /// MIDI channel (0–15).
    public let channel: UInt8

    /// Hardware-precise CoreMIDI timestamp (host ticks from `mach_absolute_time`).
    ///
    /// Captured directly from the `MIDIEventPacket.timeStamp` field, which
    /// reflects the precise moment the hardware event occurred — not the time
    /// the software parsed it. Use for accurate play-along scoring by converting
    /// to seconds via `AudioConvertHostTimeToNanos` / `1e9`.
    ///
    /// `nil` only when the event was synthesised by a test double.
    public let midiTimestamp: MIDITimeStamp?

    /// System time when the event was received.
    public let timestamp: Date

    /// Latency probe token stamped at the MIDI callback entry point (t0).
    ///
    /// Carries `mach_absolute_time` timestamps through the pipeline for
    /// end-to-end latency measurement. `nil` when profiling is not active
    /// or when the event was synthesised by a test double.
    public var probeToken: ProbeToken?

    /// Create a MIDI input event.
    ///
    /// - Parameters:
    ///   - noteNumber: MIDI note number (0–127).
    ///   - velocity: Note velocity (0 = note-off, 1–127 = note-on).
    ///   - channel: MIDI channel (0–15).
    ///   - midiTimestamp: Hardware CoreMIDI timestamp. Defaults to nil.
    ///   - timestamp: Wall-clock event timestamp. Defaults to now.
    ///   - probeToken: Latency probe token. Defaults to nil.
    public init(
        noteNumber: UInt8,
        velocity: UInt8,
        channel: UInt8 = 0,
        midiTimestamp: MIDITimeStamp? = nil,
        timestamp: Date = Date(),
        probeToken: ProbeToken? = nil
    ) {
        self.noteNumber = noteNumber
        self.velocity = velocity
        self.channel = channel
        self.midiTimestamp = midiTimestamp
        self.timestamp = timestamp
        self.probeToken = probeToken
    }
}
