import Synchronization

/// Thread-safe sustain pedal state tracker for all 16 MIDI channels.
///
/// Implements standard MIDI sustain pedal (CC64) behavior:
/// - When the pedal is down and a note-off arrives, the note is "held"
///   (visually and sonically sustained) instead of being released.
/// - When the pedal is released, all held notes are released at once.
///
/// ## Thread Safety
///
/// All mutable state is consolidated into a single `Mutex<State>` struct.
/// This is necessary because sustain state is read/written from both the
/// CoreMIDI high-priority callback thread (note events, CC events) and the
/// main thread (display link queries via `MIDINoteHighlightCoordinator`).
///
/// ## Usage
///
/// ```swift
/// let sustain = SustainPedalState()
///
/// // On CC64 pedal down:
/// sustain.pedalDown(channel: 0)
///
/// // On note-off while pedal is down:
/// let released = sustain.holdNote(note: 60, channel: 0)
/// // released is empty — note is held
///
/// // On CC64 pedal up:
/// let heldNotes = sustain.pedalUp(channel: 0)
/// // heldNotes == [60] — release these notes now
/// ```
public final class SustainPedalState: Sendable {

    // MARK: - Internal State

    /// Per-channel sustain pedal state.
    struct State: Sendable {
        /// Whether the sustain pedal is currently down, per channel (0-15).
        var isDown: [Bool] = Array(repeating: false, count: 16)

        /// Notes currently held by the sustain pedal, per channel (0-15).
        /// These are notes that received note-off while the pedal was down.
        var heldNotes: [Set<Int>] = Array(repeating: [], count: 16)
    }

    /// Mutex-protected state for thread-safe access from CoreMIDI thread.
    private let state = Mutex(State())

    // MARK: - Initialization

    /// Create a new sustain pedal state tracker.
    public init() {}

    // MARK: - Pedal Control

    /// Mark the sustain pedal as pressed for a channel.
    ///
    /// While the pedal is down, subsequent `holdNote` calls will capture
    /// note-off events instead of releasing them.
    ///
    /// - Parameter channel: MIDI channel (0-15).
    public func pedalDown(channel: UInt8) {
        let ch = Int(channel & 0x0F)
        state.withLock { s in
            s.isDown[ch] = true
        }
    }

    /// Mark the sustain pedal as released for a channel.
    ///
    /// Returns all notes that were held during the sustain period so the
    /// caller can release them (fire note-off for each).
    ///
    /// - Parameter channel: MIDI channel (0-15).
    /// - Returns: Set of MIDI note numbers that should now be released.
    @discardableResult
    public func pedalUp(channel: UInt8) -> Set<Int> {
        let ch = Int(channel & 0x0F)
        return state.withLock { s in
            s.isDown[ch] = false
            let held = s.heldNotes[ch]
            s.heldNotes[ch].removeAll()
            return held
        }
    }

    // MARK: - Note Management

    /// Attempt to hold a note that received note-off while sustain is active.
    ///
    /// If the sustain pedal is currently down for the given channel, the note
    /// is added to the held set and the caller should NOT release it. If the
    /// pedal is up, this is a no-op and the caller should release normally.
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0-127).
    ///   - channel: MIDI channel (0-15).
    /// - Returns: `true` if the note was captured (pedal is down, don't release).
    ///            `false` if the pedal is up (release normally).
    @discardableResult
    public func holdNote(note: Int, channel: UInt8) -> Bool {
        let ch = Int(channel & 0x0F)
        return state.withLock { s in
            guard s.isDown[ch] else { return false }
            s.heldNotes[ch].insert(note)
            return true
        }
    }

    // MARK: - Query

    /// Check whether the sustain pedal is currently active for a channel.
    ///
    /// - Parameter channel: MIDI channel (0-15).
    /// - Returns: `true` if the sustain pedal is held down.
    public func isActive(channel: UInt8) -> Bool {
        let ch = Int(channel & 0x0F)
        return state.withLock { s in s.isDown[ch] }
    }

    /// Check whether a specific note is currently held by the sustain pedal.
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0-127).
    ///   - channel: MIDI channel (0-15).
    /// - Returns: `true` if the note is being sustained by the pedal.
    public func isNoteHeld(note: Int, channel: UInt8) -> Bool {
        let ch = Int(channel & 0x0F)
        return state.withLock { s in s.heldNotes[ch].contains(note) }
    }

    /// Return all notes currently held by the sustain pedal on a channel.
    ///
    /// - Parameter channel: MIDI channel (0-15).
    /// - Returns: Set of held MIDI note numbers.
    public func heldNotes(channel: UInt8) -> Set<Int> {
        let ch = Int(channel & 0x0F)
        return state.withLock { s in s.heldNotes[ch] }
    }

    /// Reset all sustain state across all channels.
    ///
    /// Use when stopping MIDI input or when the user disconnects a device.
    public func reset() {
        state.withLock { s in
            for ch in 0..<16 {
                s.isDown[ch] = false
                s.heldNotes[ch].removeAll()
            }
        }
    }
}
