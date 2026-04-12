import Foundation
import AVFoundation
import Accelerate
import os

/// Module-level logger for YINPitchDetector (nonisolated static methods need module-level access).
private let yinLogger = Logger.survibe(category: "YINPitchDetector")

/// Fallback YIN autocorrelation pitch detector using Accelerate/vDSP.
/// Uses direct AVAudioEngine installTap for buffer access.
/// Independent of AudioKit — works with raw AVAudioEngine.
///
/// AUD-004: YIN runs on a dedicated DSP queue — the audio render thread only
/// copies samples (8KB memcpy) and dispatches to the queue. No O(n²) work
/// on the real-time thread.
@MainActor
public final class YINPitchDetector: PitchDetectorProtocol {
    private var continuation: AsyncStream<PitchResult>.Continuation?
    private var isDetecting = false

    /// Reference pitch for frequency-to-note conversion (default: A4 = 440 Hz).
    public var referencePitch: Double = 440.0

    /// YIN threshold (lower = stricter, typical range 0.1 to 0.2).
    public var threshold: Double = 0.15

    /// Current detector status for UI feedback (consistent with AudioKitPitchDetector API).
    public private(set) var status: String = "Idle"

    /// Dedicated queue for YIN DSP — keeps audio render thread clear (AUD-004).
    private let processingQueue = DispatchQueue(
        label: "com.survibe.yin-detection",
        qos: .userInteractive
    )

    public init() {}

    public func start() -> AsyncStream<PitchResult> {
        yinLogger.info("YIN pitch detector started")
        let stream = AsyncStream<PitchResult> { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            self.continuation = continuation
            self.isDetecting = true
            self.status = "Listening"

            let tapContext = TapContext(
                queue: self.processingQueue,
                continuation: continuation,
                refPitch: self.referencePitch,
                yinThreshold: self.threshold
            )

            AudioEngineManager.shared.installMicTap { buffer, _ in
                Self.handleMicTap(buffer: buffer, context: tapContext)
            }

            continuation.onTermination = { _ in
                Task { @MainActor in
                    self.isDetecting = false
                    AudioEngineManager.shared.removeMicTap()
                }
            }
        }
        return stream
    }

    /// Captures needed for mic tap dispatch to avoid exceeding parameter limits.
    private struct TapContext: Sendable {
        let queue: DispatchQueue
        let continuation: AsyncStream<PitchResult>.Continuation
        let refPitch: Double
        let yinThreshold: Double
    }

    /// Copy samples from the mic tap and dispatch YIN to the DSP queue (AUD-004).
    ///
    /// The audio render thread only performs: RMS check + Array copy + queue.async.
    /// All O(n²) YIN computation runs on `processingQueue`.
    /// CRITICAL: No logging here — audio thread callback.
    nonisolated private static func handleMicTap(
        buffer: AVAudioPCMBuffer,
        context: TapContext
    ) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Fast amplitude check on audio thread (single vDSP call, no allocation).
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        let amplitude = Double(rms)

        guard amplitude > 0.002 else {
            context.continuation.yield(silenceResult(amplitude: amplitude))
            return
        }

        // AUD-004: copy samples to [Float] and defer all YIN computation off the audio thread.
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
        let sampleRate = buffer.format.sampleRate

        context.queue.async {
            processYIN(
                samples: samples, amplitude: amplitude, sampleRate: sampleRate,
                context: context
            )
        }
    }

    /// Run YIN pitch detection on the DSP queue and yield result.
    nonisolated private static func processYIN(
        samples: [Float],
        amplitude: Double,
        sampleRate: Double,
        context: TapContext
    ) {
        let detection = detectPitchWithConfidence(
            samples: samples, sampleRate: sampleRate, threshold: context.yinThreshold
        )

        guard detection.frequency > 0,
              let (noteName, octave, cents) = try? SwarUtility.frequencyToNote(
                  detection.frequency, referencePitch: context.refPitch
              )
        else {
            context.continuation.yield(silenceResult(amplitude: amplitude))
            return
        }

        context.continuation.yield(PitchResult(
            frequency: detection.frequency, amplitude: amplitude,
            noteName: noteName, octave: octave,
            centsOffset: cents, confidence: detection.confidence
        ))
    }

    /// Create a silent/no-pitch result for the given amplitude.
    nonisolated private static func silenceResult(
        amplitude: Double
    ) -> PitchResult {
        PitchResult(
            frequency: 0, amplitude: amplitude,
            noteName: "", octave: 0,
            centsOffset: 0, confidence: 0
        )
    }

    public func stop() {
        yinLogger.info("YIN pitch detector stopped")
        isDetecting = false
        status = "Stopped"
        AudioEngineManager.shared.removeMicTap()
        continuation?.finish()
        continuation = nil
    }

    // MARK: - YIN Pitch Detection

    /// Raw detection result containing frequency and confidence.
    private struct YINDetectionResult {
        let frequency: Double
        let confidence: Double
    }

    /// YIN autocorrelation pitch detection with spectral confidence.
    ///
    /// Returns both the detected frequency and a confidence metric based on
    /// YIN's cumulative mean normalized difference function (CMNDF).
    /// Confidence = 1.0 - cmndf[bestTau], which naturally measures signal clarity.
    ///
    /// AUD-004: The O(n²) scalar difference function is replaced with vDSP
    /// operations. For each tau: d(tau) = sum_i (x[i] - x[i+tau])²
    ///   = sum(x[i]²) + sum(x[i+tau]²) - 2*sum(x[i]*x[i+tau])
    /// This is energy[0] + energy[tau_offset] - 2*xcorr[tau], computable
    /// with three vDSP calls per tau instead of halfLength scalar mults.
    nonisolated private static func detectPitchWithConfidence(
        samples: [Float],
        sampleRate: Double,
        threshold: Double
    ) -> YINDetectionResult {
        let frameCount = samples.count
        let halfLength = frameCount / 2
        guard halfLength > 0 else {
            return YINDetectionResult(frequency: 0, confidence: 0)
        }

        // Step 1: Compute difference function d(tau) using vDSP (AUD-004).
        // d(tau) = Σ(x[i] - x[i+tau])² = energy0 + energyTau - 2·xcorr(tau)
        var difference = [Float](repeating: 0, count: halfLength)
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            // Precompute energy[0] = Σ x[i]² for i in 0..<halfLength
            var energy0: Float = 0
            vDSP_dotpr(base, 1, base, 1, &energy0, vDSP_Length(halfLength))

            for tau in 0..<halfLength {
                let tauLen = vDSP_Length(halfLength - tau)
                guard tauLen > 0 else { continue }
                var xcorr: Float = 0
                var energyTau: Float = 0
                vDSP_dotpr(base, 1, base + tau, 1, &xcorr, tauLen)
                vDSP_dotpr(base + tau, 1, base + tau, 1, &energyTau, tauLen)
                difference[tau] = energy0 + energyTau - 2.0 * xcorr
            }
        }

        // Step 2: Cumulative mean normalized difference function d'(tau)
        var cumulativeNorm = [Float](repeating: 0, count: halfLength)
        cumulativeNorm[0] = 1.0
        var runningSum: Float = 0
        for tau in 1..<halfLength {
            runningSum += difference[tau]
            if runningSum > 0 {
                cumulativeNorm[tau] = difference[tau] * Float(tau) / runningSum
            } else {
                cumulativeNorm[tau] = 1.0
            }
        }

        // Step 3: Absolute threshold — find first dip below threshold
        let minTau = Int(sampleRate / 4000.0)
        for tau in minTau..<halfLength where cumulativeNorm[tau] < Float(threshold) {
            // Step 4: Parabolic interpolation for sub-sample accuracy
            let refinedTau = parabolicInterpolation(cumulativeNorm, tau: tau)
            let frequency = sampleRate / Double(refinedTau)
            if frequency > 50, frequency < 4000 {
                let confidence = SpectralConfidence.fromYIN(
                    cmndfAtBestTau: cumulativeNorm[tau]
                )
                return YINDetectionResult(
                    frequency: frequency, confidence: confidence
                )
            }
        }

        return YINDetectionResult(frequency: 0, confidence: 0)
    }

    /// Parabolic interpolation around a detected minimum for sub-sample accuracy.
    nonisolated private static func parabolicInterpolation(_ values: [Float], tau: Int) -> Double {
        guard tau > 0, tau < values.count - 1 else { return Double(tau) }

        let s0 = Double(values[tau - 1])
        let s1 = Double(values[tau])
        let s2 = Double(values[tau + 1])

        let denom = 2.0 * (2.0 * s1 - s2 - s0)
        guard abs(denom) > 1e-10 else { return Double(tau) }

        let adjustment = (s2 - s0) / denom
        return Double(tau) + adjustment
    }
}
