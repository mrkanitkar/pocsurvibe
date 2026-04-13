import Foundation
import SwiftData

/// Persisted MIDI event captured during a practice session.
///
/// Stores raw note-on, note-off, and control-change events with session-relative
/// timestamps for offline replay, ML training data, and practice pattern analysis.
/// Append-only per CloudKit rules — entries are never deleted or modified.
///
/// ## CloudKit Compatibility
/// - All fields have explicit default values.
/// - `type` stores the event kind as a plain String ("noteOn", "noteOff", "cc").
/// - Queryable by `sessionID` to reconstruct a complete session timeline.
@Model
final class MIDIEventEntry {
    // MARK: - Properties

    /// Practice session this event belongs to.
    var sessionID: UUID = UUID()

    /// Session-relative timestamp in seconds (0.0 = session start).
    var timestamp: Double = 0.0

    /// Event type: "noteOn", "noteOff", or "cc" (control change).
    var type: String = "noteOn"

    /// MIDI note number (0-127). Middle C (C4) = 60.
    var note: Int = 0

    /// Note velocity (0-127). 0 indicates note-off for noteOn messages.
    var velocity: Int = 0

    /// MIDI channel (0-15).
    var channel: Int = 0

    // MARK: - Initialization

    /// Create a MIDI event log entry.
    ///
    /// - Parameters:
    ///   - sessionID: UUID of the practice session this event belongs to.
    ///   - timestamp: Session-relative time in seconds.
    ///   - type: Event type string ("noteOn", "noteOff", "cc").
    ///   - note: MIDI note number (0-127).
    ///   - velocity: Note velocity (0-127).
    ///   - channel: MIDI channel (0-15).
    init(
        sessionID: UUID,
        timestamp: Double,
        type: String,
        note: Int,
        velocity: Int,
        channel: Int
    ) {
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.type = type
        self.note = note
        self.velocity = velocity
        self.channel = channel
    }
}
