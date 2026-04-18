import CoreMIDI
import Foundation

/// Unified event produced by both MIDI and microphone input paths.
///
/// Abstracts the difference between MIDI keyboard input (discrete note-on/off
/// with velocity) and microphone pitch detection (continuous frequency with
/// confidence). Downstream consumers (`NoteMatchingActor`, scoring) receive
/// a single event type regardless of input source.
///
/// Phase 1 additions: 16-bit velocity, hardware MIDI timestamp, and expression
/// event cases (pitch bend, pressure, program change) for MIDI 2.0 support.
///
/// Carries an optional ``ProbeToken`` for end-to-end latency measurement.
public enum PerformanceEvent: Sendable {

    /// A note event from a MIDI keyboard.
    ///
    /// - Parameters:
    ///   - noteNumber: MIDI note number (0-127).
    ///   - velocity: Note velocity (1-127 for note-on, 0 for note-off).
    ///   - channel: MIDI channel (0-15).
    ///   - probeToken: Latency probe token (t0 stamped at MIDI callback).
    ///   - velocity16Bit: Full 16-bit velocity from MIDI 2.0 (0 for MIDI 1.0).
    ///   - midiTimestamp: Hardware CoreMIDI timestamp for accurate scoring.
    case midi(
        noteNumber: UInt8, velocity: UInt8, channel: UInt8,
        probeToken: ProbeToken?,
        velocity16Bit: UInt16 = 0,
        midiTimestamp: MIDITimeStamp? = nil
    )

    /// A pitch detection result from microphone input.
    ///
    /// - Parameters:
    ///   - frequency: Detected frequency in Hz.
    ///   - noteName: Detected swar/note name (e.g., "Sa", "Re").
    ///   - centsOffset: Cents deviation from nearest note (-50 to +50).
    ///   - confidence: Detection confidence (0.0-1.0).
    ///   - amplitude: Signal amplitude (0.0-1.0).
    ///   - probeToken: Latency probe token (t0+t1 stamped at DSP).
    case mic(
        frequency: Double, noteName: String, centsOffset: Double,
        confidence: Double, amplitude: Double, probeToken: ProbeToken?
    )

    /// A pitch bend event from a MIDI controller.
    ///
    /// - Parameter event: The raw MIDI pitch bend event.
    case pitchBend(event: MIDIPitchBendEvent)

    /// A pressure (aftertouch) event from a MIDI controller.
    ///
    /// - Parameter event: The raw MIDI pressure event.
    case pressure(event: MIDIPressureEvent)

    /// A program change event from a MIDI controller.
    ///
    /// - Parameter event: The raw MIDI program change event.
    case programChange(event: MIDIProgramChangeEvent)

    // MARK: - Convenience Queries

    /// Whether this event originated from a MIDI keyboard note-on/off.
    public var isMIDI: Bool {
        if case .midi = self { return true }
        return false
    }

    /// Whether this event originated from microphone pitch detection.
    public var isMic: Bool {
        if case .mic = self { return true }
        return false
    }

    /// Whether this event is a pitch bend message.
    public var isPitchBend: Bool {
        if case .pitchBend = self { return true }
        return false
    }

    /// Whether this event is a pressure (aftertouch) message.
    public var isPressure: Bool {
        if case .pressure = self { return true }
        return false
    }

    /// Whether this event is a program change message.
    public var isProgramChange: Bool {
        if case .programChange = self { return true }
        return false
    }

    /// MIDI note number, or `nil` for non-note events.
    public var noteNumber: UInt8? {
        if case .midi(let n, _, _, _, _, _) = self { return n }
        return nil
    }

    /// Note velocity (7-bit), or `nil` for non-note events.
    public var velocity: UInt8? {
        if case .midi(_, let v, _, _, _, _) = self { return v }
        return nil
    }

    /// Full 16-bit velocity from MIDI 2.0, or `nil` for non-note events.
    ///
    /// Zero when the source is MIDI 1.0 or a test double.
    public var velocity16Bit: UInt16? {
        if case .midi(_, _, _, _, let v16, _) = self { return v16 }
        return nil
    }

    /// Hardware CoreMIDI timestamp, or `nil` for non-MIDI or mic events.
    public var midiTimestamp: MIDITimeStamp? {
        if case .midi(_, _, _, _, _, let ts) = self { return ts }
        return nil
    }

    /// The latency probe token carried by this event.
    public var probeToken: ProbeToken? {
        switch self {
        case .midi(_, _, _, let token, _, _): return token
        case .mic(_, _, _, _, _, let token): return token
        case .pitchBend, .pressure, .programChange: return nil
        }
    }

    // MARK: - Factory Methods

    /// Create a ``PerformanceEvent`` from a ``MIDIInputEvent``.
    ///
    /// Transfers the probe token, 16-bit velocity, and hardware timestamp
    /// from the MIDI event for latency tracking and high-resolution scoring.
    public static func from(_ event: MIDIInputEvent) -> PerformanceEvent {
        .midi(
            noteNumber: event.noteNumber,
            velocity: event.velocity,
            channel: event.channel,
            probeToken: event.probeToken,
            velocity16Bit: event.velocity16Bit,
            midiTimestamp: event.midiTimestamp
        )
    }

    /// Create a ``PerformanceEvent`` from a ``PitchResult``.
    ///
    /// Transfers the probe token from the pitch result for latency tracking.
    public static func from(_ result: PitchResult) -> PerformanceEvent {
        .mic(
            frequency: result.frequency,
            noteName: result.noteName,
            centsOffset: result.centsOffset,
            confidence: result.confidence,
            amplitude: result.amplitude,
            probeToken: result.probeToken
        )
    }
}
