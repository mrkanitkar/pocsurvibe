import Foundation

/// Unified event produced by both MIDI and microphone input paths.
///
/// Abstracts the difference between MIDI keyboard input (discrete note-on/off
/// with velocity) and microphone pitch detection (continuous frequency with
/// confidence). Downstream consumers (`NoteMatchingActor`, scoring) receive
/// a single event type regardless of input source.
///
/// Carries an optional ``ProbeToken`` for end-to-end latency measurement.
public enum PerformanceEvent: Sendable {

    /// A note event from a MIDI keyboard.
    ///
    /// - Parameters:
    ///   - noteNumber: MIDI note number (0–127).
    ///   - velocity: Note velocity (1–127 for note-on, 0 for note-off).
    ///   - channel: MIDI channel (0–15).
    ///   - probeToken: Latency probe token (t0 stamped at MIDI callback).
    case midi(noteNumber: UInt8, velocity: UInt8, channel: UInt8, probeToken: ProbeToken?)

    /// A pitch detection result from microphone input.
    ///
    /// - Parameters:
    ///   - frequency: Detected frequency in Hz.
    ///   - noteName: Detected swar/note name (e.g., "Sa", "Re").
    ///   - centsOffset: Cents deviation from nearest note (-50 to +50).
    ///   - confidence: Detection confidence (0.0–1.0).
    ///   - amplitude: Signal amplitude (0.0–1.0).
    ///   - probeToken: Latency probe token (t0+t1 stamped at DSP).
    case mic(
        frequency: Double, noteName: String, centsOffset: Double,
        confidence: Double, amplitude: Double, probeToken: ProbeToken?
    )

    // MARK: - Convenience Queries

    /// Whether this event originated from a MIDI keyboard.
    public var isMIDI: Bool {
        if case .midi = self { return true }
        return false
    }

    /// Whether this event originated from microphone pitch detection.
    public var isMic: Bool {
        if case .mic = self { return true }
        return false
    }

    /// MIDI note number, or `nil` for mic events.
    public var noteNumber: UInt8? {
        if case .midi(let n, _, _, _) = self { return n }
        return nil
    }

    /// Note velocity, or `nil` for mic events.
    public var velocity: UInt8? {
        if case .midi(_, let v, _, _) = self { return v }
        return nil
    }

    /// The latency probe token carried by this event.
    public var probeToken: ProbeToken? {
        switch self {
        case .midi(_, _, _, let token): return token
        case .mic(_, _, _, _, _, let token): return token
        }
    }

    // MARK: - Factory Methods

    /// Create a ``PerformanceEvent`` from a ``MIDIInputEvent``.
    ///
    /// Transfers the probe token from the MIDI event for latency tracking.
    public static func from(_ event: MIDIInputEvent) -> PerformanceEvent {
        .midi(
            noteNumber: event.noteNumber,
            velocity: event.velocity,
            channel: event.channel,
            probeToken: event.probeToken
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
