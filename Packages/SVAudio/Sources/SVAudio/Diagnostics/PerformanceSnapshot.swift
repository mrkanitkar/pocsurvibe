import Foundation

/// Point-in-time snapshot of the audio pipeline's performance metrics.
///
/// Aggregates all diagnostic data — latency percentiles, frame drops,
/// queue depth, and event counts ��� into a single value type for logging,
/// analytics export, or UI display.
///
/// ## Usage
///
/// ```swift
/// let snapshot = PerformanceSnapshot.capture()
/// print("p95: \(snapshot.latency.p95Micros)µs, drops: \(snapshot.droppedFrames)")
/// ```
public struct PerformanceSnapshot: Sendable, Codable {

    /// Latency percentiles (p50/p95/p99) from the most recent histogram window.
    public let latency: LatencySummary

    /// Number of dropped display frames since last reset.
    public let droppedFrames: Int

    /// Number of completed latency probe measurements.
    public let probeCount: Int

    /// SPSC ring buffer fill level (0.0–1.0). Values near 1.0 mean the
    /// consumer (DSP) is falling behind the producer (audio tap).
    public let bufferFillLevel: Double

    /// Timestamp when this snapshot was captured.
    public let capturedAt: Date

    /// Create a snapshot with explicit values.
    public init(
        latency: LatencySummary,
        droppedFrames: Int,
        probeCount: Int,
        bufferFillLevel: Double,
        capturedAt: Date = Date()
    ) {
        self.latency = latency
        self.droppedFrames = droppedFrames
        self.probeCount = probeCount
        self.bufferFillLevel = bufferFillLevel
        self.capturedAt = capturedAt
    }

    /// Capture a live snapshot from the shared diagnostic singletons.
    ///
    /// Reads from `PracticeLatencyProbe.shared` and `LatencyHistogram.shared` by default.
    /// Pass a custom histogram for per-component snapshots.
    ///
    /// - Parameters:
    ///   - histogram: The latency histogram to read. Defaults to `.shared`.
    ///   - frameDropCounter: The active frame drop counter.
    ///   - bufferFillLevel: Current SPSC ring buffer fill level.
    /// - Returns: A populated snapshot.
    public static func capture(
        histogram: LatencyHistogram = .shared,
        frameDropCounter: FrameDropCounter,
        bufferFillLevel: Double = 0
    ) -> PerformanceSnapshot {
        PerformanceSnapshot(
            latency: histogram.summary(),
            droppedFrames: frameDropCounter.count,
            probeCount: PracticeLatencyProbe.shared.completedCount,
            bufferFillLevel: bufferFillLevel
        )
    }
}
