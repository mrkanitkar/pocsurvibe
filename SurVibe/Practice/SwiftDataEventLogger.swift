import Foundation
import SVAudio
import SVCore
import SwiftData
import os.log

/// SwiftData-backed implementation of `EventLogging` for persisting MIDI events
/// and pitch detection results during practice sessions.
///
/// Uses `@ModelActor` (Apple's official pattern) to perform all SwiftData writes
/// on a dedicated background model context, avoiding main-thread blocking during
/// high-throughput event logging.
///
/// ## Architecture
/// - Callers (`MIDIInputManager`, `PracticeAudioProcessor`) call fire-and-forget
///   `logMIDIEvent` / `logPitchDetection` methods synchronously.
/// - Each call enqueues a `Task` to insert the model object on the actor's context.
/// - `flush()` saves any pending changes and should be called at session teardown.
///
/// ## Thread Safety
/// `@ModelActor` provides its own serial executor backed by the model context,
/// ensuring all SwiftData operations are serialized without manual locking.
@ModelActor
final actor SwiftDataEventLogger: EventLogging {
    // MARK: - Properties

    private static let logger = Logger.survibe(category: "EventLogger")

    // MARK: - EventLogging Conformance

    /// Log a MIDI event by inserting a `MIDIEventEntry` into SwiftData.
    ///
    /// Enqueues the insert on this actor's serial executor. Non-blocking for callers.
    ///
    /// - Parameters:
    ///   - sessionID: UUID of the practice session.
    ///   - timestamp: Session-relative time in seconds.
    ///   - type: Event type string ("noteOn", "noteOff", "cc").
    ///   - note: MIDI note number (0-127).
    ///   - velocity: Note velocity (0-127).
    ///   - channel: MIDI channel (0-15).
    nonisolated func logMIDIEvent(
        sessionID: UUID,
        timestamp: Double,
        type: String,
        note: Int,
        velocity: Int,
        channel: Int
    ) {
        Task {
            await insertMIDIEvent(
                sessionID: sessionID,
                timestamp: timestamp,
                type: type,
                note: note,
                velocity: velocity,
                channel: channel
            )
        }
    }

    /// Log a pitch detection result by inserting a `PitchLogEntry` into SwiftData.
    ///
    /// Enqueues the insert on this actor's serial executor. Non-blocking for callers.
    ///
    /// - Parameters:
    ///   - sessionID: UUID of the practice session.
    ///   - timestamp: Session-relative time in seconds.
    ///   - frequency: Detected frequency in Hz.
    ///   - confidence: Detection confidence (0.0-1.0).
    ///   - note: Detected note name (e.g., "Sa", "Re").
    nonisolated func logPitchDetection(
        sessionID: UUID,
        timestamp: Double,
        frequency: Double,
        confidence: Double,
        note: String
    ) {
        Task {
            await insertPitchLog(
                sessionID: sessionID,
                timestamp: timestamp,
                frequency: frequency,
                confidence: confidence,
                note: note
            )
        }
    }

    /// Flush all buffered writes to the persistent store.
    ///
    /// Saves the model context explicitly to ensure all inserted entries are
    /// committed before the session completes.
    func flush() async {
        do {
            try modelContext.save()
            Self.logger.info("EventLogger flushed successfully")
        } catch {
            Self.logger.error("EventLogger flush failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    /// Insert a MIDI event entry into the model context.
    private func insertMIDIEvent(
        sessionID: UUID,
        timestamp: Double,
        type: String,
        note: Int,
        velocity: Int,
        channel: Int
    ) {
        let entry = MIDIEventEntry(
            sessionID: sessionID,
            timestamp: timestamp,
            type: type,
            note: note,
            velocity: velocity,
            channel: channel
        )
        modelContext.insert(entry)
    }

    /// Insert a pitch log entry into the model context.
    private func insertPitchLog(
        sessionID: UUID,
        timestamp: Double,
        frequency: Double,
        confidence: Double,
        note: String
    ) {
        let entry = PitchLogEntry(
            sessionID: sessionID,
            timestamp: timestamp,
            frequency: frequency,
            confidence: confidence,
            note: note
        )
        modelContext.insert(entry)
    }
}
