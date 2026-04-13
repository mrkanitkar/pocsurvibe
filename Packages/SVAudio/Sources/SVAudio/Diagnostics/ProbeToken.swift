import Foundation

/// Pipeline stage identifiers for latency measurement.
///
/// Each stage corresponds to a point in the MIDI/mic → DSP → match → render pipeline.
public enum ProbeStage: Int, Sendable {
    /// MIDI callback entry or audio tap callback.
    case inputReceived = 0
    /// DSP completion (pitch detected or MIDI event processed).
    case dspComplete = 1
    /// Note matching completes in NoteMatchingActor.
    case matchComplete = 2
    /// Frame presented via CADisplayLink in MIDINoteHighlightCoordinator.
    case framePresented = 3
}

/// Lightweight value type carrying `mach_absolute_time` timestamps through the audio pipeline.
///
/// Designed for zero-cost profiling: no heap allocations, no ARC overhead.
/// All four timestamps fit in 32 bytes (4 × UInt64) — register-friendly.
///
/// - Note: `mach_absolute_time()` is monotonic and has nanosecond-scale resolution
///   on Apple Silicon. Convert to nanoseconds via `mach_timebase_info`.
public struct ProbeToken: Sendable, Equatable {

    // MARK: - Timestamps

    /// Input received: MIDI callback or audio tap entry.
    public private(set) var t0: UInt64 = 0
    /// DSP processing complete.
    public private(set) var t1: UInt64 = 0
    /// Note matching complete.
    public private(set) var t2: UInt64 = 0
    /// Frame presented to display.
    public private(set) var t3: UInt64 = 0

    // MARK: - Initialization

    /// Creates an empty probe token with all timestamps at zero.
    public init() {}

    // MARK: - Stamping

    /// Records `mach_absolute_time()` for the given pipeline stage.
    ///
    /// - Parameter stage: The pipeline stage being completed.
    public mutating func stamp(_ stage: ProbeStage) {
        let now = mach_absolute_time()
        switch stage {
        case .inputReceived:  t0 = now
        case .dspComplete:    t1 = now
        case .matchComplete:  t2 = now
        case .framePresented: t3 = now
        }
    }

    // MARK: - Queries

    /// Whether all four stages have been stamped.
    public var isComplete: Bool {
        t0 > 0 && t1 > 0 && t2 > 0 && t3 > 0
    }

    /// End-to-end elapsed time in nanoseconds (t3 - t0), or `nil` if incomplete.
    ///
    /// Uses `mach_timebase_info` to convert Mach absolute time to nanoseconds.
    public var elapsedNanoseconds: UInt64? {
        guard isComplete else { return nil }
        let ticks = t3 - t0
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return ticks * UInt64(info.numer) / UInt64(info.denom)
    }

    /// End-to-end elapsed time in microseconds, or `nil` if incomplete.
    public var elapsedMicroseconds: UInt64? {
        guard let ns = elapsedNanoseconds else { return nil }
        return ns / 1000
    }
}
