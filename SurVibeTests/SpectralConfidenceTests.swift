import Testing
@testable import SVAudio

@MainActor
struct SpectralConfidenceTests {
    // MARK: - Autocorrelation-based Confidence

    @Test func clearPeakGivesHighConfidence() {
        // Simulate autocorrelation with a strong peak at lag 200
        var autocorrelation = [Float](repeating: 0.1, count: 400)
        autocorrelation[200] = 0.95  // Strong peak
        autocorrelation[199] = 0.7
        autocorrelation[201] = 0.7

        let confidence = SpectralConfidence.compute(
            autocorrelation: autocorrelation,
            bestLag: 200,
            minLag: 10
        )
        #expect(confidence > 0.5)
    }

    @Test func flatAutocorrelationGivesLowConfidence() {
        // All values roughly equal — no clear peak
        let autocorrelation = [Float](repeating: 0.3, count: 400)

        let confidence = SpectralConfidence.compute(
            autocorrelation: autocorrelation,
            bestLag: 200,
            minLag: 10
        )
        #expect(confidence < 0.1)
    }

    @Test func emptyAutocorrelationReturnsZero() {
        let confidence = SpectralConfidence.compute(
            autocorrelation: [],
            bestLag: 0,
            minLag: 0
        )
        #expect(confidence == 0)
    }

    @Test func bestLagAtMinLagReturnsZero() {
        let autocorrelation = [Float](repeating: 0.5, count: 100)
        let confidence = SpectralConfidence.compute(
            autocorrelation: autocorrelation,
            bestLag: 10,
            minLag: 10
        )
        #expect(confidence == 0)
    }

    @Test func bestLagOutOfBoundsReturnsZero() {
        let autocorrelation = [Float](repeating: 0.5, count: 50)
        let confidence = SpectralConfidence.compute(
            autocorrelation: autocorrelation,
            bestLag: 100,
            minLag: 5
        )
        #expect(confidence == 0)
    }

    @Test func confidenceIsClamped01() {
        // Extremely prominent peak should still cap at 1.0
        var autocorrelation = [Float](repeating: 0.01, count: 400)
        autocorrelation[200] = 1.0

        let confidence = SpectralConfidence.compute(
            autocorrelation: autocorrelation,
            bestLag: 200,
            minLag: 10
        )
        #expect(confidence >= 0)
        #expect(confidence <= 1.0)
    }

    // MARK: - YIN-based Confidence

    @Test func yinPerfectPeriodicityGivesHighConfidence() {
        // CMNDF ≈ 0 means perfect periodicity
        let confidence = SpectralConfidence.fromYIN(cmndfAtBestTau: 0.02)
        #expect(confidence > 0.95)
    }

    @Test func yinNoiseGivesLowConfidence() {
        // CMNDF ≈ 1.0 means no periodicity
        let confidence = SpectralConfidence.fromYIN(cmndfAtBestTau: 0.95)
        #expect(confidence < 0.1)
    }

    @Test func yinConfidenceIsClamped() {
        // Negative CMNDF (shouldn't happen but defensive)
        let confidence = SpectralConfidence.fromYIN(cmndfAtBestTau: -0.5)
        #expect(confidence <= 1.0)
        #expect(confidence >= 0)

        // CMNDF > 1 (defensive edge case)
        let confidence2 = SpectralConfidence.fromYIN(cmndfAtBestTau: 1.5)
        #expect(confidence2 == 0)
    }

    @Test func yinThresholdBoundary() {
        // Typical YIN threshold is 0.15
        // Float(0.15) → Double conversion introduces tiny precision error
        let confidence = SpectralConfidence.fromYIN(cmndfAtBestTau: 0.15)
        #expect(abs(confidence - 0.85) < 1e-6)
    }
}
