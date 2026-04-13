import Foundation

/// Snapshot of latency percentile statistics from a ``LatencyHistogram``.
///
/// Contains p50, p95, and p99 latency values in microseconds, along with
/// the number of probes in the current window and the time span covered.
/// Conforms to `Codable` for serialization to analytics or debug logs.
public struct LatencySummary: Sendable, Codable, Equatable {

    /// Median (50th percentile) latency in microseconds.
    public let p50Micros: UInt64

    /// 95th percentile latency in microseconds.
    public let p95Micros: UInt64

    /// 99th percentile latency in microseconds.
    public let p99Micros: UInt64

    /// Number of probes in the current histogram window.
    public let count: Int

    /// Elapsed seconds between the first and last probe in the buffer.
    public let windowDuration: TimeInterval

    /// Creates a latency summary with explicit values.
    ///
    /// - Parameters:
    ///   - p50Micros: Median latency in microseconds.
    ///   - p95Micros: 95th percentile latency in microseconds.
    ///   - p99Micros: 99th percentile latency in microseconds.
    ///   - count: Number of probes in the window.
    ///   - windowDuration: Seconds between first and last probe.
    public init(
        p50Micros: UInt64,
        p95Micros: UInt64,
        p99Micros: UInt64,
        count: Int,
        windowDuration: TimeInterval
    ) {
        self.p50Micros = p50Micros
        self.p95Micros = p95Micros
        self.p99Micros = p99Micros
        self.count = count
        self.windowDuration = windowDuration
    }
}
