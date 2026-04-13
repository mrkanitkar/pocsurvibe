import Foundation

/// Protocol for logging MIDI events and pitch detection results during practice sessions.
///
/// Defined in SVAudio so that `MIDIInputManager` and `PracticeAudioProcessor` can
/// call logging methods without depending on SwiftData. The concrete implementation
/// lives in the app target (`SwiftDataEventLogger`) where `@ModelActor` and
/// `@Model` types are available.
///
/// All methods are designed for high-throughput, fire-and-forget logging:
/// - `logMIDIEvent` and `logPitchDetection` accept value-type parameters only.
/// - `flush()` is async to allow batched writes to complete before session teardown.
///
/// ## Concurrency
/// Conforming types must be `Sendable`. The protocol is intended for use from
/// both the main actor (PracticeAudioProcessor) and nonisolated contexts
/// (MIDIInputManager's CoreMIDI callbacks).
public protocol EventLogging: Sendable {
    /// Log a MIDI event (note-on, note-off, or control change).
    ///
    /// Called from CoreMIDI's high-priority thread or the main actor.
    /// Implementations should buffer writes and avoid blocking the caller.
    ///
    /// - Parameters:
    ///   - sessionID: UUID of the practice session.
    ///   - timestamp: Session-relative time in seconds.
    ///   - type: Event type string ("noteOn", "noteOff", "cc").
    ///   - note: MIDI note number (0-127).
    ///   - velocity: Note velocity (0-127).
    ///   - channel: MIDI channel (0-15).
    func logMIDIEvent(
        sessionID: UUID,
        timestamp: Double,
        type: String,
        note: Int,
        velocity: Int,
        channel: Int
    )

    /// Log a pitch detection result from the microphone.
    ///
    /// Called from the main actor (PracticeAudioProcessor).
    /// Implementations should buffer writes and avoid blocking the caller.
    ///
    /// - Parameters:
    ///   - sessionID: UUID of the practice session.
    ///   - timestamp: Session-relative time in seconds.
    ///   - frequency: Detected frequency in Hz.
    ///   - confidence: Detection confidence (0.0-1.0).
    ///   - note: Detected note name (e.g., "Sa", "Re").
    func logPitchDetection(
        sessionID: UUID,
        timestamp: Double,
        frequency: Double,
        confidence: Double,
        note: String
    )

    /// Flush any buffered log entries to persistent storage.
    ///
    /// Call during session teardown to ensure all events are persisted
    /// before the session completes. Awaiting this method guarantees all
    /// buffered writes have been committed.
    func flush() async
}
