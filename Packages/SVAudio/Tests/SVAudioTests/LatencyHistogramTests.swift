import Foundation
import Testing
@testable import SVAudio

struct LatencyHistogramTests {

    // MARK: - Helpers

    /// Create a complete ProbeToken with a known elapsed time.
    private func makeCompleteToken() -> ProbeToken {
        var token = ProbeToken()
        token.stamp(.inputReceived)
        token.stamp(.dspComplete)
        token.stamp(.matchComplete)
        token.stamp(.framePresented)
        return token
    }

    // MARK: - Empty Histogram

    @Test func emptyHistogramReturnsZeroSummary() {
        let histogram = LatencyHistogram()
        let summary = histogram.summary()
        #expect(summary.p50Micros == 0)
        #expect(summary.p95Micros == 0)
        #expect(summary.p99Micros == 0)
        #expect(summary.count == .zero)
        #expect(summary.windowDuration == 0)
    }

    // MARK: - Single Token

    @Test func singleTokenProducesSamePercentiles() {
        let histogram = LatencyHistogram()
        let token = makeCompleteToken()
        histogram.record(token)

        let summary = histogram.summary()
        #expect(summary.count == 1)
        #expect(summary.p50Micros == summary.p95Micros)
        #expect(summary.p95Micros == summary.p99Micros)
    }

    // MARK: - Known Distribution

    @Test func knownDistributionProducesCorrectPercentiles() {
        let histogram = LatencyHistogram(capacity: 1000)

        for micros in 1...1000 {
            histogram.recordMicroseconds(UInt64(micros))
        }

        let summary = histogram.summary()
        #expect(summary.count == 1000)
        #expect(summary.p50Micros == 500)
        #expect(summary.p95Micros == 950)
        #expect(summary.p99Micros == 990)
    }

    // MARK: - Circular Buffer Wrapping

    @Test func circularBufferRetainsOnlyLastCapacityProbes() {
        let capacity = 1000
        let histogram = LatencyHistogram(capacity: capacity)

        for micros in 1...1500 {
            histogram.recordMicroseconds(UInt64(micros))
        }

        let summary = histogram.summary()
        #expect(summary.count == capacity)
        #expect(summary.p50Micros == 1000)
        #expect(summary.p95Micros == 1450)
        #expect(summary.p99Micros == 1490)
    }

    // MARK: - Reset

    @Test func resetClearsAllData() {
        let histogram = LatencyHistogram()
        let token = makeCompleteToken()
        histogram.record(token)
        #expect(histogram.summary().count == 1)

        histogram.reset()

        let summary = histogram.summary()
        #expect(summary.count == .zero)
        #expect(summary.p50Micros == 0)
    }

    // MARK: - Thread Safety

    @Test func concurrentWritesDoNotCrash() async {
        let histogram = LatencyHistogram(capacity: 1000)

        await withTaskGroup(of: Void.self) { group in
            for i in 1...100 {
                group.addTask {
                    histogram.recordMicroseconds(UInt64(i))
                }
            }
        }

        let summary = histogram.summary()
        #expect(summary.count == 100)
    }

    // MARK: - LatencySummary Equatable

    @Test func latencySummaryEquatableConformance() {
        let a = LatencySummary(p50Micros: 100, p95Micros: 200, p99Micros: 300, count: 10, windowDuration: 1.5)
        let b = LatencySummary(p50Micros: 100, p95Micros: 200, p99Micros: 300, count: 10, windowDuration: 1.5)
        #expect(a == b)
    }

    // MARK: - LatencySummary Codable

    @Test func latencySummaryCodableRoundTrip() throws {
        let original = LatencySummary(p50Micros: 500, p95Micros: 950, p99Micros: 990, count: 1000, windowDuration: 42.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LatencySummary.self, from: data)
        #expect(original == decoded)
    }

    // MARK: - Incomplete Tokens Ignored

    @Test func incompleteTokensAreIgnored() {
        let histogram = LatencyHistogram()
        var incomplete = ProbeToken()
        incomplete.stamp(.inputReceived)
        histogram.record(incomplete)
        #expect(histogram.summary().count == .zero)
    }

    // MARK: - Window Duration

    @Test func windowDurationReflectsTimeSpan() {
        let histogram = LatencyHistogram(capacity: 1000)
        histogram.recordMicroseconds(100)
        for _ in 0..<100_000 { _ = Int.random(in: 0..<100) }
        histogram.recordMicroseconds(200)

        let summary = histogram.summary()
        #expect(summary.count == 2)
        #expect(summary.windowDuration >= 0)
    }
}
