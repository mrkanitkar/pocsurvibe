import Foundation
import Synchronization

/// Collects latency measurements in a fixed-size circular buffer and computes percentiles on demand.
///
/// Thread-safe via `Mutex<HistogramState>`. Accepts completed ``ProbeToken`` values
/// and stores their end-to-end latency (microseconds) in a pre-allocated ring buffer.
/// Percentile computation (p50, p95, p99) happens only when ``summary()`` is called,
/// using a ceiling-rank method on the sorted buffer for O(n log n) performance.
///
/// ## Usage
/// ```swift
/// let histogram = LatencyHistogram()
/// histogram.record(completedToken)
/// let stats = histogram.summary()
/// print("p50: \(stats.p50Micros)us, p95: \(stats.p95Micros)us")
/// ```
public final class LatencyHistogram: Sendable {

    // MARK: - Shared Instance

    /// Shared histogram for session-wide latency aggregation.
    ///
    /// Use this for pipeline-level metrics that need a single collection point.
    /// Per-component histograms can still be created via `init(capacity:)`.
    public static let shared = LatencyHistogram()

    // MARK: - Constants

    /// Default number of probes retained in the circular buffer.
    public static let defaultCapacity = 1000

    // MARK: - Internal State

    /// Mutable state protected by Mutex for thread safety.
    private struct HistogramState {
        /// Pre-allocated buffer of latency values in microseconds.
        var buffer: [UInt64]
        /// Pre-allocated buffer of recording timestamps (mach_absolute_time).
        var timestamps: [UInt64]
        /// Maximum number of entries the buffer can hold.
        let capacity: Int
        /// Total number of entries written (may exceed capacity; modulo gives write index).
        var totalWritten: Int = 0

        /// Number of valid entries currently in the buffer.
        var count: Int {
            min(totalWritten, capacity)
        }

        /// Initialize with a given capacity, pre-allocating the buffer.
        init(capacity: Int) {
            self.capacity = capacity
            self.buffer = [UInt64](repeating: 0, count: capacity)
            self.timestamps = [UInt64](repeating: 0, count: capacity)
        }
    }

    /// Thread-safe access to all mutable histogram state.
    private let state: Mutex<HistogramState>

    // MARK: - Initialization

    /// Creates a latency histogram with the specified buffer capacity.
    ///
    /// The buffer is pre-allocated at initialization; no further heap allocations
    /// occur during ``record(_:)`` calls.
    ///
    /// - Parameter capacity: Maximum number of latency probes retained.
    ///   Oldest entries are overwritten when the buffer is full.
    ///   Defaults to ``defaultCapacity`` (1000).
    public init(capacity: Int = LatencyHistogram.defaultCapacity) {
        precondition(capacity > 0, "LatencyHistogram capacity must be positive")
        self.state = Mutex(HistogramState(capacity: capacity))
    }

    // MARK: - Recording

    /// Records the end-to-end latency from a completed probe token.
    ///
    /// Ignores incomplete tokens (missing any pipeline stage timestamp).
    /// Insertion is O(1) with no allocation after initial buffer setup.
    ///
    /// - Parameter token: A fully stamped ``ProbeToken``.
    public func record(_ token: ProbeToken) {
        guard token.isComplete, let micros = token.elapsedMicroseconds else { return }
        recordMicroseconds(micros)
    }

    /// Records a raw microsecond latency value directly into the circular buffer.
    ///
    /// Primarily for testing with synthetic data. Production code should use ``record(_:)``.
    ///
    /// - Parameter micros: Latency in microseconds.
    func recordMicroseconds(_ micros: UInt64) {
        let now = mach_absolute_time()
        state.withLock { s in
            let index = s.totalWritten % s.capacity
            s.buffer[index] = micros
            s.timestamps[index] = now
            s.totalWritten += 1
        }
    }

    // MARK: - Snapshot

    /// Snapshot of buffer contents extracted under the lock for percentile computation.
    private struct BufferSnapshot {
        var values: [UInt64]
        var firstTimestamp: UInt64
        var lastTimestamp: UInt64
    }

    // MARK: - Queries

    /// Computes a latency summary with p50, p95, and p99 percentiles.
    ///
    /// Percentile computation uses sorted-array rank lookup
    /// for O(n log n) worst-case performance. The buffer contents are copied before
    /// sorting to avoid holding the lock during computation.
    ///
    /// - Returns: A ``LatencySummary`` snapshot. Returns zero values if no probes recorded.
    public func summary() -> LatencySummary {
        let snapshot = state.withLock { s -> BufferSnapshot in
            let count = s.count
            guard count > 0 else {
                return BufferSnapshot(values: [], firstTimestamp: 0, lastTimestamp: 0)
            }

            var vals = [UInt64]()
            vals.reserveCapacity(count)

            var earliest: UInt64 = .max
            var latest: UInt64 = 0

            let slotCount = s.totalWritten <= s.capacity ? count : s.capacity
            for i in 0..<slotCount {
                vals.append(s.buffer[i])
                let ts = s.timestamps[i]
                if ts < earliest { earliest = ts }
                if ts > latest { latest = ts }
            }

            return BufferSnapshot(values: vals, firstTimestamp: earliest, lastTimestamp: latest)
        }

        guard !snapshot.values.isEmpty else {
            return LatencySummary(p50Micros: 0, p95Micros: 0, p99Micros: 0, count: 0, windowDuration: 0)
        }

        var sorted = snapshot.values
        sorted.sort()

        let count = sorted.count
        let p50 = Self.percentile(sorted: sorted, count: count, p: 0.50)
        let p95 = Self.percentile(sorted: sorted, count: count, p: 0.95)
        let p99 = Self.percentile(sorted: sorted, count: count, p: 0.99)

        let windowDuration = Self.machTicksToSeconds(from: snapshot.firstTimestamp, to: snapshot.lastTimestamp)

        return LatencySummary(
            p50Micros: p50,
            p95Micros: p95,
            p99Micros: p99,
            count: count,
            windowDuration: windowDuration
        )
    }

    // MARK: - Lifecycle

    /// Clears all recorded data from the histogram.
    public func reset() {
        state.withLock { s in
            for i in 0..<s.capacity {
                s.buffer[i] = 0
                s.timestamps[i] = 0
            }
            s.totalWritten = 0
        }
    }

    // MARK: - Private Helpers

    /// Compute the percentile value from a sorted array using the ceiling-rank method.
    nonisolated private static func percentile(sorted: [UInt64], count: Int, p: Double) -> UInt64 {
        let rank = Int((p * Double(count)).rounded(.up))
        let index = max(0, min(rank - 1, count - 1))
        return sorted[index]
    }

    /// Convert Mach absolute time tick difference to seconds.
    nonisolated private static func machTicksToSeconds(from start: UInt64, to end: UInt64) -> TimeInterval {
        guard end > start else { return 0 }
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let ticks = end - start
        let nanos = ticks * UInt64(info.numer) / UInt64(info.denom)
        return TimeInterval(nanos) / 1_000_000_000
    }
}
