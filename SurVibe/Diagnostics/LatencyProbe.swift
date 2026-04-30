#if DEBUG
import os.signpost

/// DEBUG-only rolling-window latency probe for the Learn-a-Song pipeline.
///
/// Records ``latencyMs`` samples in a capped ring buffer of 1024 entries.
/// When the window is full the oldest sample is evicted to make room for the
/// new one. Emits an ``os_signpost`` `.event` on every recording so Instruments
/// can visualize the distribution in the Points of Interest timeline.
///
/// ## Usage
/// ```swift
/// let probe = AppLatencyProbe()
/// probe.record(latencyMs: elapsed)
/// let median = probe.p50()
/// let worstCase = probe.p99()
/// ```
///
/// - Note: This type is `@MainActor` because it mutates `samples` from SwiftUI
///   view update paths. Never call `record` from an audio-thread callback;
///   capture the timestamp there and dispatch the record call to the main actor.
@MainActor
final class AppLatencyProbe {

    // MARK: - Properties

    /// OSLog handle for os_signpost events.
    ///
    /// Uses `OSLog` (not the newer `Logger`) because `os_signpost` requires an
    /// `OSLog` object; `Logger` does not expose a compatible interface.
    private let log = OSLog(subsystem: "com.survibe", category: "Latency")

    /// Recorded latency samples in milliseconds, oldest-first.
    private var samples: [Double] = []

    /// Maximum number of samples retained in the rolling window.
    private let window = 1024

    // MARK: - Recording

    /// Records a latency sample and emits an Instruments signpost event.
    ///
    /// If the internal buffer exceeds `window` (1024) entries the oldest
    /// samples are evicted so the buffer stays at exactly `window` entries.
    ///
    /// - Parameter latencyMs: End-to-end pipeline latency in milliseconds.
    func record(latencyMs: Double) {
        samples.append(latencyMs)
        if samples.count > window {
            samples.removeFirst(samples.count - window)
        }
        os_signpost(.event, log: log, name: "LatencySample", "%{public}.2f ms", latencyMs)
    }

    // MARK: - Percentiles

    /// Returns the 50th-percentile (median) latency across the rolling window.
    ///
    /// Returns `0.0` when no samples have been recorded.
    ///
    /// - Returns: Median latency in milliseconds.
    func p50() -> Double { percentile(0.50) }

    /// Returns the 99th-percentile latency across the rolling window.
    ///
    /// Returns `0.0` when no samples have been recorded.
    ///
    /// - Returns: 99th-percentile latency in milliseconds.
    func p99() -> Double { percentile(0.99) }

    // MARK: - Private Helpers

    /// Computes an arbitrary percentile from the current sample window.
    ///
    /// Sorts all samples in ascending order and returns the value at the
    /// floor index `Int(count × p)`, capped at `count − 1`.
    ///
    /// - Parameter p: Percentile in the range [0, 1].
    /// - Returns: Percentile value in milliseconds, or `0.0` if no samples.
    private func percentile(_ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let idx = min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.down)))
        return sorted[idx]
    }
}
#endif
