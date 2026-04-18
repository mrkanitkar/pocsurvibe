import Foundation
import os
import Synchronization

/// Collects completed `ProbeToken` values for latency measurement.
///
/// Thread-safe via `Mutex<State>`. Records only complete tokens (all 4 stages stamped).
/// Uses `OSSignposter` for Instruments integration — zero-cost in non-profiling builds.
///
/// ## Usage
/// ```swift
/// var token = ProbeToken()
/// token.stamp(.inputReceived)   // at MIDI callback
/// token.stamp(.dspComplete)     // after pitch detection
/// token.stamp(.matchComplete)   // after note matching
/// token.stamp(.framePresented)  // at CADisplayLink
/// LatencyProbe.shared.record(token)
/// ```
public final class LatencyProbe: Sendable {

    // MARK: - Singleton

    /// Shared instance for pipeline-wide latency collection.
    public static let shared = LatencyProbe()

    // MARK: - State

    private struct State {
        var completedCount: Int = 0
        var lastElapsedMicros: UInt64 = 0
    }

    private let state = Mutex(State())

    // MARK: - Signposter

    /// OSSignposter for Instruments integration.
    ///
    /// Intervals are compiled to no-ops when not profiling (zero runtime cost).
    private static let signposter = OSSignposter(
        subsystem: "com.survibe",
        category: "LatencyProbe"
    )

    // MARK: - Initialization

    private init() {}

    // MARK: - Recording

    /// Records a completed probe token.
    ///
    /// Ignores incomplete tokens (missing any stage timestamp).
    /// Emits an OSSignposter event for Instruments visibility.
    ///
    /// - Parameter token: A fully stamped `ProbeToken`.
    public func record(_ token: ProbeToken) {
        guard token.isComplete else { return }

        let micros = token.elapsedMicroseconds ?? 0

        state.withLock { s in
            s.completedCount += 1
            s.lastElapsedMicros = micros
        }

        // OSSignposter event — zero-cost when not profiling.
        Self.signposter.emitEvent("PipelineLatency", "\(micros)µs")
    }

    // MARK: - Queries

    /// Number of complete probe tokens recorded since last reset.
    public var completedCount: Int {
        state.withLock { $0.completedCount }
    }

    /// Most recent end-to-end latency in microseconds.
    public var lastElapsedMicroseconds: UInt64 {
        state.withLock { $0.lastElapsedMicros }
    }

    // MARK: - Lifecycle

    /// Resets all counters. Call at session start.
    public func reset() {
        state.withLock { s in
            s.completedCount = 0
            s.lastElapsedMicros = 0
        }
    }

    // MARK: - Per-Stage Breakdown

    /// Cached mach timebase info for tick-to-nanosecond conversion.
    private static let cachedTimebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Per-stage latency breakdown from a completed probe token.
    public struct StageSummary: Sendable {
        /// Input received to DSP complete (microseconds).
        public let inputToDSP: UInt64
        /// DSP complete to match complete (microseconds).
        public let dspToMatch: UInt64
        /// Match complete to frame presented (microseconds).
        public let matchToFrame: UInt64
        /// Total end-to-end (microseconds).
        public let total: UInt64
    }

    /// Extract per-stage latency from a completed probe token.
    ///
    /// Converts mach absolute time deltas between each pipeline stage into
    /// microseconds using the cached timebase info. Returns nil if the token
    /// is incomplete (missing any stage timestamp).
    ///
    /// - Parameter token: A probe token with all stages stamped.
    /// - Returns: Stage breakdown in microseconds, or nil if incomplete.
    public static func stageSummary(from token: ProbeToken) -> StageSummary? {
        guard token.isComplete else { return nil }
        let info = Self.cachedTimebaseInfo

        return StageSummary(
            inputToDSP: (token.t1 - token.t0) * UInt64(info.numer) / UInt64(info.denom) / 1000,
            dspToMatch: (token.t2 - token.t1) * UInt64(info.numer) / UInt64(info.denom) / 1000,
            matchToFrame: (token.t3 - token.t2) * UInt64(info.numer) / UInt64(info.denom) / 1000,
            total: (token.t3 - token.t0) * UInt64(info.numer) / UInt64(info.denom) / 1000
        )
    }
}
