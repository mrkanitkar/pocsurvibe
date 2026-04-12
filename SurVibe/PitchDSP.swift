import Accelerate
import Foundation
import SVAudio
import SVCore
import Synchronization
import os.log

/// A detected note for display in the history list.
struct DetectedNote: Identifiable {
    let id = UUID()
    let swarName: String
    let westernName: String
    let octave: Int
    let centsOffset: Double
    let frequency: Double
    let timestamp: Date
}

/// Thread-safe boolean flag using Mutex for compiler-verified Sendable.
final class AtomicFlag: Sendable {
    private let value = Mutex<Bool>(false)
    /// Whether the flag has been set. Safe from any thread via Mutex.
    nonisolated var isSet: Bool { value.withLock { $0 } }
    /// Set the flag to `true`. Safe from any thread via Mutex.
    nonisolated func set() { value.withLock { $0 = true } }
}

/// Thread-safe counter using Mutex for compiler-verified Sendable.
final class AtomicCounter: Sendable {
    private let value = Mutex<Int>(0)
    /// Atomically increment and return the new value. Safe from any thread via Mutex.
    @discardableResult
    nonisolated func increment() -> Int { value.withLock { $0 += 1; return $0 } }
}

/// Stateless DSP functions for pitch detection. Safe to call from any thread.
///
/// `nonisolated` on the enum opts out of implicit `@MainActor` isolation
/// from `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in the app target.
/// All methods use Apple Accelerate for SIMD-optimized autocorrelation.
nonisolated enum PitchDSP {
    /// Logger for DSP diagnostics -- declared here (nonisolated context) so it
    /// can be used from @Sendable mic tap closures and nonisolated static methods.
    static let logger = Logger.survibe(category: "PitchDetectionVM")

    /// Result of pitch detection with spectral confidence.
    struct DetectionResult {
        let frequency: Double
        let confidence: Double
    }

    /// Calculate RMS amplitude from audio samples using vDSP.
    ///
    /// - Parameter samples: Raw audio samples.
    /// - Returns: RMS amplitude as a Double.
    static func calculateRMS(_ samples: [Float]) -> Double {
        var rms: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_rmsqv(base, 1, &rms, vDSP_Length(samples.count))
        }
        return Double(rms)
    }

    private struct Peak { let lag: Int; let value: Float }

    /// Autocorrelation-based pitch detection using Accelerate vDSP.
    ///
    /// Computes dot products at each lag, finds peaks, applies octave correction,
    /// and refines with parabolic interpolation for sub-sample accuracy.
    /// Returns frequency only; use `detectPitchWithConfidence` for spectral confidence.
    ///
    /// - Parameters:
    ///   - samples: Raw audio samples.
    ///   - sampleRate: Audio sample rate in Hz.
    /// - Returns: Detected frequency in Hz, or 0 if no pitch found.
    static func detectPitch(samples: [Float], sampleRate: Double) -> Double {
        detectPitchWithConfidence(samples: samples, sampleRate: sampleRate).frequency
    }

    /// Pitch detection with spectral confidence using peak-to-sidelobe ratio.
    ///
    /// Returns both the detected frequency and a spectral confidence value (0.0-1.0)
    /// derived from the autocorrelation peak prominence rather than raw amplitude.
    ///
    /// - Parameters:
    ///   - samples: Raw audio samples.
    ///   - sampleRate: Audio sample rate in Hz.
    /// - Returns: A `DetectionResult` with frequency and confidence.
    static func detectPitchWithConfidence(samples: [Float], sampleRate: Double) -> DetectionResult {
        let frameCount = samples.count
        guard frameCount > 4 else { return DetectionResult(frequency: 0, confidence: 0) }
        let maxLag = frameCount / 2
        var ac = computeAutocorrelation(samples: samples, maxLag: maxLag)
        guard ac[0] > 0 else { return DetectionResult(frequency: 0, confidence: 0) }
        normalizeInPlace(&ac, maxLag: maxLag)
        let minLag = max(2, Int(sampleRate / 4000.0))
        guard minLag < maxLag else { return DetectionResult(frequency: 0, confidence: 0) }
        let peaks = findPeaks(in: ac, minLag: minLag, maxLag: maxLag)
        guard let firstPeak = peaks.first else { return DetectionResult(frequency: 0, confidence: 0) }
        let best = correctForOctaveError(firstPeak: firstPeak, allPeaks: peaks)
        guard best.value > 0.15 else { return DetectionResult(frequency: 0, confidence: 0) }
        let refined = refine(lag: best.lag, ac: ac, maxLag: maxLag)
        guard refined > 0 else { return DetectionResult(frequency: 0, confidence: 0) }
        let freq = sampleRate / refined
        guard freq > 50 && freq < 4000 else { return DetectionResult(frequency: 0, confidence: 0) }

        // Compute spectral confidence from autocorrelation peak prominence
        let confidence = SpectralConfidence.compute(
            autocorrelation: ac, bestLag: best.lag, minLag: minLag
        )
        return DetectionResult(frequency: freq, confidence: confidence)
    }

    /// Compute raw autocorrelation via vDSP dot products.
    private static func computeAutocorrelation(samples: [Float], maxLag: Int) -> [Float] {
        let n = samples.count
        var ac = [Float](repeating: 0, count: maxLag)
        samples.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for lag in 0..<maxLag {
                var sum: Float = 0
                let cnt = vDSP_Length(n - lag)
                guard cnt > 0 else { continue }
                vDSP_dotpr(base, 1, base + lag, 1, &sum, cnt)
                ac[lag] = sum
            }
        }
        return ac
    }

    /// Normalize autocorrelation in place by zero-lag energy.
    private static func normalizeInPlace(_ ac: inout [Float], maxLag: Int) {
        var inv: Float = 1.0 / ac[0]
        var norm = [Float](repeating: 0, count: maxLag)
        vDSP_vsmul(&ac, 1, &inv, &norm, 1, vDSP_Length(maxLag))
        ac = norm
    }

    /// Find all peaks above confidence threshold.
    private static func findPeaks(in ac: [Float], minLag: Int, maxLag: Int) -> [Peak] {
        var peaks: [Peak] = []
        var declining = true
        for lag in minLag..<maxLag {
            if declining && ac[lag] > ac[lag - 1] { declining = false }
            if !declining && ac[lag] < ac[lag - 1] {
                if ac[lag - 1] > 0.15 { peaks.append(Peak(lag: lag - 1, value: ac[lag - 1])) }
                declining = true
            }
        }
        return peaks
    }

    /// Correct for octave error by checking for sub-octave peak at ~2x lag.
    private static func correctForOctaveError(firstPeak: Peak, allPeaks: [Peak]) -> Peak {
        for peak in allPeaks where peak.lag != firstPeak.lag {
            let ratio = Double(peak.lag) / Double(firstPeak.lag)
            if ratio > 1.8 && ratio < 2.2 && peak.value >= firstPeak.value * 0.85 { return peak }
        }
        return firstPeak
    }

    /// Refine lag with parabolic interpolation.
    private static func refine(lag: Int, ac: [Float], maxLag: Int) -> Double {
        guard lag > 0 && lag < maxLag - 1 else { return Double(lag) }
        let s0 = Double(ac[lag - 1]), s1 = Double(ac[lag]), s2 = Double(ac[lag + 1])
        let denom = 2.0 * (2.0 * s1 - s2 - s0)
        guard abs(denom) > 1e-10 else { return Double(lag) }
        return Double(lag) + (s2 - s0) / denom
    }
}
