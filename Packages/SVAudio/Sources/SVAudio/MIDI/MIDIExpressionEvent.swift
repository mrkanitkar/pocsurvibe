import CoreMIDI
import Foundation

/// Unified expression event abstracting pitch bend, aftertouch, and mic deviation.
///
/// Normalizes MIDI hardware expression events and microphone pitch deviation into
/// a common type that the scoring pipeline can consume. All pitch-related values
/// are expressed in cents; all pressure values are normalized to 0.0-1.0.
///
/// This enum provides a scoring-friendly abstraction over the raw MIDI event types
/// (`MIDIPitchBendEvent`, `MIDIPressureEvent`) and microphone pitch results.
///
/// `Sendable` value type that safely crosses isolation boundaries.
public enum MIDIExpressionEvent: Sendable, Equatable {

    /// Channel-wide pitch bend expressed in cents.
    ///
    /// - Parameters:
    ///   - cents: Pitch deviation in cents from unbent pitch.
    ///   - channel: MIDI channel (0-15).
    ///   - timestamp: Hardware CoreMIDI timestamp, or nil.
    case channelPitchBend(cents: Double, channel: UInt8, timestamp: MIDITimeStamp?)

    /// Per-note pitch bend expressed in cents (MIDI 2.0 only).
    ///
    /// - Parameters:
    ///   - cents: Pitch deviation in cents from unbent pitch.
    ///   - noteNumber: Target MIDI note number (0-127).
    ///   - channel: MIDI channel (0-15).
    ///   - timestamp: Hardware CoreMIDI timestamp, or nil.
    case perNotePitchBend(cents: Double, noteNumber: UInt8, channel: UInt8, timestamp: MIDITimeStamp?)

    /// Polyphonic aftertouch pressure normalized to 0.0-1.0.
    ///
    /// - Parameters:
    ///   - pressure: Normalized pressure (0.0-1.0).
    ///   - noteNumber: Target MIDI note number (0-127).
    ///   - channel: MIDI channel (0-15).
    ///   - timestamp: Hardware CoreMIDI timestamp, or nil.
    case polyAftertouch(pressure: Double, noteNumber: UInt8, channel: UInt8, timestamp: MIDITimeStamp?)

    /// Channel aftertouch pressure normalized to 0.0-1.0.
    ///
    /// - Parameters:
    ///   - pressure: Normalized pressure (0.0-1.0).
    ///   - channel: MIDI channel (0-15).
    ///   - timestamp: Hardware CoreMIDI timestamp, or nil.
    case channelAftertouch(pressure: Double, channel: UInt8, timestamp: MIDITimeStamp?)

    /// Microphone pitch deviation in cents from the expected pitch.
    ///
    /// - Parameters:
    ///   - cents: Pitch deviation in cents.
    ///   - confidence: Detection confidence (0.0-1.0).
    case micPitchDeviation(cents: Double, confidence: Double)

    // MARK: - Factory Methods

    /// Create a unified expression event from a pitch bend event.
    ///
    /// Converts the raw pitch bend value to cents using the specified bend range.
    ///
    /// - Parameters:
    ///   - pitchBend: The raw MIDI pitch bend event.
    ///   - bendRangeSemitones: Bend range in semitones. Defaults to 2.0.
    /// - Returns: A channel or per-note pitch bend expression event.
    public static func from(
        _ pitchBend: MIDIPitchBendEvent,
        bendRangeSemitones: Double = 2.0
    ) -> MIDIExpressionEvent {
        let cents = pitchBend.toCents(bendRangeSemitones: bendRangeSemitones)
        if let noteNumber = pitchBend.noteNumber {
            return .perNotePitchBend(
                cents: cents,
                noteNumber: noteNumber,
                channel: pitchBend.channel,
                timestamp: pitchBend.midiTimestamp
            )
        }
        return .channelPitchBend(
            cents: cents,
            channel: pitchBend.channel,
            timestamp: pitchBend.midiTimestamp
        )
    }

    /// Create a unified expression event from a pressure event.
    ///
    /// Normalizes the 32-bit pressure value to 0.0-1.0 range.
    ///
    /// - Parameter pressureEvent: The raw MIDI pressure event.
    /// - Returns: A poly or channel aftertouch expression event.
    public static func from(_ pressureEvent: MIDIPressureEvent) -> MIDIExpressionEvent {
        let normalized = Double(pressureEvent.pressure) / Double(UInt32.max)
        if let noteNumber = pressureEvent.noteNumber {
            return .polyAftertouch(
                pressure: normalized,
                noteNumber: noteNumber,
                channel: pressureEvent.channel,
                timestamp: pressureEvent.midiTimestamp
            )
        }
        return .channelAftertouch(
            pressure: normalized,
            channel: pressureEvent.channel,
            timestamp: pressureEvent.midiTimestamp
        )
    }
}
