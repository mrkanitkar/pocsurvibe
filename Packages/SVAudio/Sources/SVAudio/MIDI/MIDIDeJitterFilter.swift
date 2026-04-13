import CoreMIDI
import Darwin.Mach
import Synchronization

/// Suppresses duplicate MIDI note-on events within a configurable time window.
///
/// Physical keyboards can produce mechanical switch bounce -- the same key
/// sends multiple note-on events within milliseconds. This filter coalesces
/// duplicates by tracking the last note-on timestamp per note number.
///
/// Thread-safe via `Mutex<State>` -- called from CoreMIDI's high-priority thread.
/// O(1) lookup per event using a 128-element array indexed by MIDI note number.
public final class MIDIDeJitterFilter: Sendable {

    // MARK: - Configuration

    /// Coalescence window in seconds. Note-on events for the same note arriving
    /// within this interval after a previous note-on are suppressed.
    ///
    /// Default is 20ms, which covers typical mechanical switch bounce without
    /// interfering with intentional repeated notes (trills, tremolos).
    public let windowSeconds: Double

    // MARK: - State

    /// Mutable state protected by `Mutex` for thread-safe access from
    /// CoreMIDI's high-priority callback thread.
    private let state: Mutex<State>

    /// Per-note timestamp state. Each element stores the `mach_absolute_time`
    /// of the last accepted note-on for that MIDI note number (0-127).
    private struct State: Sendable {
        /// Last accepted note-on timestamp per MIDI note (128 entries).
        /// Zero means no prior note-on has been recorded for that note.
        var lastNoteOnTick: [UInt64]

        init() {
            lastNoteOnTick = [UInt64](repeating: 0, count: 128)
        }
    }

    // MARK: - Mach Timebase

    /// Cached mach timebase info for converting ticks to nanoseconds.
    /// Computed once at init time -- `mach_timebase_info` is process-global and immutable.
    private let ticksToNanosFactor: Double

    // MARK: - Initialization

    /// Create a de-jitter filter with a configurable coalescence window.
    ///
    /// - Parameter windowSeconds: Duration in seconds within which duplicate
    ///   note-on events for the same note are suppressed. Default is 0.020 (20ms).
    public init(windowSeconds: Double = 0.020) {
        self.windowSeconds = windowSeconds
        self.state = Mutex(State())

        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        self.ticksToNanosFactor = Double(info.numer) / Double(info.denom)
    }

    // MARK: - Public Methods

    /// Determine whether a note-on event should be suppressed as switch bounce.
    ///
    /// Compares the incoming `timestamp` against the last accepted note-on for
    /// the same note number. If the time delta is less than `windowSeconds`,
    /// the event is considered a duplicate and should be dropped.
    ///
    /// Different notes within the window are NOT suppressed -- this preserves
    /// chord detection.
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0-127).
    ///   - timestamp: Hardware `MIDITimeStamp` from the event packet.
    /// - Returns: `true` if the event should be suppressed (duplicate), `false` if allowed.
    public func shouldSuppress(note: UInt8, timestamp: MIDITimeStamp) -> Bool {
        let windowNanos = UInt64(windowSeconds * 1e9)

        return state.withLock { s in
            let index = Int(note)
            let lastTick = s.lastNoteOnTick[index]

            if lastTick != 0 {
                let deltaTicks = timestamp > lastTick ? timestamp - lastTick : 0
                let deltaNanos = UInt64(Double(deltaTicks) * ticksToNanosFactor)

                if deltaNanos < windowNanos {
                    return true  // suppress duplicate
                }
            }

            // Allow this event and record its timestamp.
            s.lastNoteOnTick[index] = timestamp
            return false
        }
    }

    /// Clear all recorded timestamps, resetting the filter to its initial state.
    ///
    /// Call when MIDI sources are disconnected or the session ends.
    public func reset() {
        state.withLock { s in
            s.lastNoteOnTick = [UInt64](repeating: 0, count: 128)
        }
    }
}
