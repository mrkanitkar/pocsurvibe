#if DEBUG
import Testing
@testable import SurVibe

/// Tests for the DEBUG-only ``AppLatencyProbe`` class in the app target.
///
/// Verifies percentile computation, window eviction, and edge-case
/// behaviour on empty / single-sample data sets.
struct AppLatencyProbeTests {

    // MARK: - Percentile Accuracy

    /// Records six samples and verifies p50 and p99 fall within expected ranges.
    ///
    /// With sorted samples [10, 11, 12, 13, 14, 50]:
    /// - p50: idx = Int(6 × 0.50) = 3 → sorted[3] = 13 → ≤ 13
    /// - p99: idx = Int(6 × 0.99) = 5 → sorted[5] = 50
    @Test @MainActor
    func recordsP50AndP99() {
        let probe = AppLatencyProbe()
        for ms in [10.0, 11.0, 12.0, 13.0, 14.0, 50.0] {
            probe.record(latencyMs: ms)
        }
        #expect(probe.p50() <= 13.0)
        #expect(probe.p99() == 50.0)
    }

    // MARK: - Window Eviction

    /// Verifies that recording more than 1024 samples evicts the oldest ones.
    ///
    /// Fills the window with 1.0 ms samples, then adds one 999.0 ms sample.
    /// After eviction the window holds 1023 × 1.0 ms + 1 × 999.0 ms.
    /// The p50 should remain 1.0 ms and p99 should be well below 999.0 ms.
    @Test @MainActor
    func windowEvictsOldSamples() {
        let probe = AppLatencyProbe()
        for _ in 0..<1024 {
            probe.record(latencyMs: 1.0)
        }
        probe.record(latencyMs: 999.0)

        // After eviction: 1023 × 1.0 ms at indices 0–1022, 999.0 ms at index 1023.
        // p50 index = Int(1024 × 0.50) = 512 → 1.0 ms
        // p99 index = Int(1024 × 0.99) = 1013 → 1.0 ms (< 1023 so not 999.0)
        #expect(probe.p50() == 1.0)
        #expect(probe.p99() < 999.0)
    }

    // MARK: - Edge Cases

    /// Verifies that p50 and p99 return 0.0 when no samples have been recorded.
    @Test @MainActor
    func emptyProbeReturnsZero() {
        let probe = AppLatencyProbe()
        #expect(probe.p50() == 0.0)
        #expect(probe.p99() == 0.0)
    }

    /// Verifies that with a single sample both p50 and p99 equal that sample.
    @Test @MainActor
    func singleSamplePercentile() {
        let probe = AppLatencyProbe()
        probe.record(latencyMs: 42.0)
        #expect(probe.p50() == 42.0)
        #expect(probe.p99() == 42.0)
    }
}
#endif
