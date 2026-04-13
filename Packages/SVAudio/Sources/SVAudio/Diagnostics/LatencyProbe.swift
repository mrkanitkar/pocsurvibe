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
}
