import Accelerate
import Foundation

// MARK: - DSP Processing (nonisolated static — safe to call from any thread)

extension AudioKitPitchDetector {
    /// Calculate RMS amplitude from an `UnsafeBufferPointer` of audio samples.
    nonisolated static func calculateRMS(_ samples: UnsafeBufferPointer<Float>) -> Double {
        var rms: Float = 0
        guard let base = samples.baseAddress else { return 0 }
        vDSP_rmsqv(base, 1, &rms, vDSP_Length(samples.count))
        return Double(rms)
    }

    /// Calculate RMS amplitude from a mutable work buffer (DSP loop variant).
    nonisolated static func calculateRMSFromMutable(
        _ buffer: UnsafeMutableBufferPointer<Float>
    ) -> Double {
        var rms: Float = 0
        guard let base = buffer.baseAddress else { return 0 }
        vDSP_rmsqv(base, 1, &rms, vDSP_Length(buffer.count))
        return Double(rms)
    }

    /// Calculate RMS amplitude from an `Array` of audio samples.
    nonisolated static func calculateRMS(_ samples: [Float]) -> Double {
        var rms: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_rmsqv(base, 1, &rms, vDSP_Length(samples.count))
        }
        return Double(rms)
    }

    /// Compute normalized autocorrelation of audio samples via vDSP.
    nonisolated static func computeAutocorrelation(
        _ samples: [Float]
    ) -> [Float] {
        let halfLength = samples.count / 2
        guard halfLength > 2 else { return [] }

        var autocorrelation = [Float](repeating: 0, count: halfLength)

        samples.withUnsafeBufferPointer { bufPtr in
            guard let baseAddress = bufPtr.baseAddress else { return }
            for lag in 0..<halfLength {
                var sum: Float = 0
                let count = vDSP_Length(halfLength - lag)
                guard count > 0 else { continue }
                vDSP_dotpr(
                    baseAddress, 1,
                    baseAddress + lag, 1,
                    &sum, count
                )
                autocorrelation[lag] = sum
            }
        }

        guard autocorrelation[0] > 0 else { return [] }
        var invNorm: Float = 1.0 / autocorrelation[0]
        var normalized = [Float](repeating: 0, count: halfLength)
        vDSP_vsmul(
            &autocorrelation, 1, &invNorm, &normalized, 1,
            vDSP_Length(halfLength)
        )
        return normalized
    }

    /// Find the best autocorrelation lag (first peak after initial decline).
    nonisolated static func findBestLag(
        _ autocorrelation: [Float], minLag: Int, halfLength: Int
    ) -> Int {
        var bestLag = 0
        var bestVal: Float = 0
        var declining = true

        for lag in minLag..<halfLength {
            if declining, autocorrelation[lag] > autocorrelation[lag - 1] {
                declining = false
            }
            if !declining, autocorrelation[lag] > bestVal {
                bestVal = autocorrelation[lag]
                bestLag = lag
            }
            if !declining, autocorrelation[lag] < autocorrelation[lag - 1] {
                break
            }
        }
        return bestVal > 0.2 ? bestLag : 0
    }

    /// Parabolic interpolation for sub-sample pitch accuracy.
    nonisolated static func parabolicInterpolation(
        _ data: [Float], lag: Int
    ) -> Double {
        guard lag > 0, lag < data.count - 1 else { return Double(lag) }
        let s0 = Double(data[lag - 1])
        let s1 = Double(data[lag])
        let s2 = Double(data[lag + 1])
        let denom = 2.0 * (2.0 * s1 - s2 - s0)
        guard abs(denom) > 1e-10 else { return Double(lag) }
        return Double(lag) + (s2 - s0) / denom
    }
}
