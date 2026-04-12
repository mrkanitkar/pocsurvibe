import AVFoundation
import Accelerate
import Synchronization
import os

/// Module-level logger — not actor-isolated, safe to use from any context.
private let pitchLogger = Logger.survibe(category: "PitchDetector")

/// Module-level signposter for Instruments pitch detection intervals.
private let pitchSignposter = OSSignposter(subsystem: "com.survibe", category: "PitchDetection")

/// Autocorrelation-based pitch detector using Accelerate/vDSP.
///
/// Uses direct AVAudioEngine installTap for buffer access. The audio render
/// callback writes raw samples into a lock-free `SPSCRingBuffer` with zero
/// heap allocation and zero lock acquisition (AUD-001/002/003). A dedicated
/// DSP task reads from the ring buffer via signal-driven wakeup (AUD-007),
/// performs autocorrelation pitch detection, and yields results to an
/// `AsyncStream<PitchResult>`.
@MainActor
public final class AudioKitPitchDetector: PitchDetectorProtocol {
    private var continuation: AsyncStream<PitchResult>.Continuation?
    private var isDetecting = false

    /// Reference pitch for frequency-to-note conversion (default: A4 = 440 Hz).
    public var referencePitch: Double = 440.0

    /// AUD-022: Minimum detectable frequency in Hz (default: 50 Hz, below A1 = 55 Hz).
    ///
    /// Lowering this value allows detection of very deep bass pitches but
    /// increases false-positive rate at the cost of slightly higher CPU for
    /// more lag candidates in autocorrelation. Raising it (e.g. 80 Hz) reduces
    /// noise for applications limited to tenor range and above.
    public var minimumFrequency: Double = 50.0

    /// AUD-022: Maximum detectable frequency in Hz (default: 4000 Hz, above E8 = 5274 Hz
    /// but well within the piano's practical range of C8 = 4186 Hz).
    ///
    /// Raising this value allows detection of very high-pitched notes but
    /// requires more autocorrelation precision. Typical piano practice range
    /// is C2–C8 (65–4186 Hz), so 4200 Hz is a safe ceiling.
    public var maximumFrequency: Double = 4000.0

    /// Number of audio buffers received (for diagnostics).
    public private(set) var bufferCount: Int = 0

    /// Last measured amplitude (for diagnostics / live meter).
    public private(set) var lastAmplitude: Double = 0

    /// Current detector status for UI feedback.
    public private(set) var status: String = "Idle"

    /// Lock-free SPSC ring buffer shared between the audio callback and DSP task.
    ///
    /// Producer: audio render thread via `write()` — lock-free atomic write.
    /// Consumer: DSP task via `readLatest()` — lock-free atomic read.
    /// Capacity: 4096 samples (power-of-two, 2x the 2048-frame tap buffer size).
    private let spscBuffer = SPSCRingBuffer(capacity: 4096)

    /// AUD-007: Signal stream to wake the DSP task when new audio data arrives.
    ///
    /// The tap callback yields `()` after each `spscBuffer.write(ptr)`.
    /// The DSP loop does `for await _ in tapSignal { process() }` instead of
    /// polling with sleep. Buffer policy `bufferingNewest(1)` coalesces signals
    /// so the DSP task gets one wakeup per accumulated batch, not N wakeups.
    private var tapSignalContinuation: AsyncStream<Void>.Continuation?
    private var tapSignal: AsyncStream<Void> = AsyncStream { _ in }

    /// DSP processing task — runs autocorrelation on ring buffer contents.
    private var dspTask: Task<Void, Never>?

    public init() {}

    deinit {
        // Safety net: ensure the stream is terminated if this instance
        // is deallocated without an explicit stop() call.
        // Note: AudioEngineManager cleanup must happen on MainActor via Task.
        if isDetecting {
            // AUD-012: Assert in debug builds — callers should always call stop()
            // before releasing the detector to ensure clean tap removal.
            #if DEBUG
            assertionFailure("AudioKitPitchDetector deallocated while still detecting. Call stop() first.")
            #endif
            continuation?.finish()
            tapSignalContinuation?.finish()
            dspTask?.cancel()
            Task { @MainActor in
                AudioEngineManager.shared.removeMicTap()
            }
        }
    }

    public func start() -> AsyncStream<PitchResult> {
        // Stop any previous session
        stopInternal()
        bufferCount = 0
        lastAmplitude = 0
        status = "Starting..."

        let refPitch = referencePitch
        let minFreq = minimumFrequency
        let maxFreq = maximumFrequency

        // AUD-023: bufferingNewest(3) instead of (1) so a brief main-thread
        // stall does not silently drop pitch results — consumers see up to 3
        // queued results before older ones are evicted.
        let (stream, continuation) = AsyncStream<PitchResult>.makeStream(
            bufferingPolicy: .bufferingNewest(3)
        )
        self.continuation = continuation
        self.isDetecting = true
        self.status = "Installing mic tap..."

        // AUD-007: Create the signal stream before installing the tap so the
        // DSP task can begin awaiting it immediately.
        let (signal, signalCont) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        tapSignal = signal
        tapSignalContinuation = signalCont

        // Install mic tap — audio callback writes raw samples into SPSCRingBuffer.
        // AUD-001/002/003: zero heap allocation, zero lock acquisition on audio thread.
        let spsc = spscBuffer
        // AUD-011: tap callback counter uses Atomic<Int> — truly lock-free on audio thread.
        let tapCount = Atomic<Int>(0)

        AudioEngineManager.shared.installMicTap { [signalCont] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            // AUD-001: write raw pointer directly — no Array construction on audio thread.
            let ptr = UnsafeBufferPointer(start: channelData, count: frameLength)
            spsc.write(ptr)

            // AUD-007: Signal the DSP task that new data is available.
            signalCont.yield(())

            // AUD-011: diagnostic logging — debug builds only.
            #if DEBUG
            let count = tapCount.wrappingAdd(1, ordering: .relaxed).newValue
            if count == 1 || count % 50 == 0 {
                let rate = buffer.format.sampleRate
                pitchLogger.info(
                    "Tap buffer #\(count): frames=\(frameLength) rate=\(String(format: "%.0f", rate))Hz"
                )
            }
            #endif
        }

        self.status = "Listening"
        pitchLogger.info("Pitch detector started, mic tap installed")

        // Start the signal-driven DSP loop.
        startDSPLoop(
            refPitch: refPitch, minFreq: minFreq, maxFreq: maxFreq,
            continuation: continuation
        )

        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopInternal()
            }
        }

        return stream
    }

    public func stop() {
        stopInternal()
    }

    /// Internal cleanup — removes tap, cancels DSP task, and finishes streams.
    private func stopInternal() {
        guard isDetecting else { return }
        isDetecting = false
        status = "Stopped"
        dspTask?.cancel()
        dspTask = nil
        AudioEngineManager.shared.removeMicTap()
        // AUD-007: Finish the tap signal stream so the DSP task's `for await` loop exits.
        tapSignalContinuation?.finish()
        tapSignalContinuation = nil
        continuation?.finish()
        continuation = nil
        pitchLogger.info("Pitch detector stopped")
    }

    // MARK: - DSP Loop (signal-driven)

    /// Start the signal-driven DSP processing loop.
    ///
    /// AUD-007: Event-driven via `tapSignal` AsyncStream. The loop wakes
    /// immediately each time the mic tap delivers a new buffer, eliminating
    /// polling. Reads the latest 2048 audio samples from the SPSC ring buffer
    /// into a pre-allocated working buffer, performs autocorrelation-based pitch
    /// detection via vDSP, and yields results to the async stream.
    private func startDSPLoop(
        refPitch: Double,
        minFreq: Double,
        maxFreq: Double,
        continuation: AsyncStream<PitchResult>.Continuation
    ) {
        let spsc = spscBuffer
        let bufferSize = 2048
        let signal = tapSignal

        // Allocate the DSP work buffer once — reused on every iteration.
        let workBuf = UnsafeMutableBufferPointer<Float>.allocate(capacity: bufferSize)
        workBuf.initialize(repeating: 0.0)

        dspTask = Task { [weak self] in
            defer { workBuf.deallocate() }

            #if DEBUG
            var processedCount = 0
            #endif

            // AUD-007: Wait for tap signals instead of polling.
            for await _ in signal {
                guard !Task.isCancelled else { break }

                // AUD-002: read latest samples into pre-allocated buffer — zero allocation.
                let hasData = spsc.readLatest(count: bufferSize, into: workBuf)
                guard hasData else { continue }

                #if DEBUG
                processedCount += 1
                #endif

                let signpostID = pitchSignposter.makeSignpostID()
                let state = pitchSignposter.beginInterval("PitchDetection", id: signpostID)
                let result = Self.processWorkBuffer(
                    workBuf, bufferSize: bufferSize,
                    refPitch: refPitch, minFreq: minFreq, maxFreq: maxFreq
                )
                pitchSignposter.endInterval("PitchDetection", state)

                #if DEBUG
                if processedCount % 50 == 1 {
                    let ampStr = String(format: "%.6f", result?.amplitude ?? 0)
                    pitchLogger.info(
                        "DSP buffer #\(processedCount) amp=\(ampStr)"
                    )
                }
                #endif

                if let result {
                    continuation.yield(result)
                    await MainActor.run { [weak self] in
                        self?.lastAmplitude = result.amplitude
                        self?.bufferCount += 1
                    }
                } else {
                    // Yield silence result so consumers know the detector is alive.
                    let rms = Self.calculateRMSFromMutable(workBuf)
                    continuation.yield(Self.silenceResult(amplitude: rms))
                }
            }
        }
    }

    // MARK: - DSP Processing (nonisolated static — safe to call from any thread)

    /// Process audio samples from a pre-allocated work buffer and return a pitch result.
    ///
    /// Runs autocorrelation-based pitch detection with spectral confidence.
    /// Returns `nil` if the buffer is silent or no pitch is detected above threshold.
    ///
    /// - Parameters:
    ///   - workBuf: Pre-allocated buffer containing audio samples from `readLatest`.
    ///   - bufferSize: Number of valid samples in the work buffer.
    ///   - refPitch: Reference pitch for frequency-to-note conversion (Hz).
    ///   - minFreq: AUD-022: Lower frequency bound (Hz).
    ///   - maxFreq: AUD-022: Upper frequency bound (Hz).
    /// - Returns: A `PitchResult` if a pitch was detected, or `nil` for silence/no detection.
    nonisolated private static func processWorkBuffer(
        _ workBuf: UnsafeMutableBufferPointer<Float>,
        bufferSize: Int,
        refPitch: Double,
        minFreq: Double,
        maxFreq: Double
    ) -> PitchResult? {
        guard let base = workBuf.baseAddress, bufferSize > 0 else { return nil }

        let samples = UnsafeBufferPointer(start: base, count: bufferSize)
        let amplitude = calculateRMS(samples)

        guard amplitude > 0.002 else { return nil }

        let samplesArray = Array(samples)
        let detection = detectPitchWithConfidence(
            samples: samplesArray, sampleRate: 44100.0,
            minFreq: minFreq, maxFreq: maxFreq
        )

        guard detection.frequency > 0,
              let (noteName, octave, cents) = try? SwarUtility.frequencyToNote(
                  detection.frequency, referencePitch: refPitch
              )
        else { return nil }

        return PitchResult(
            frequency: detection.frequency, amplitude: amplitude,
            noteName: noteName, octave: octave,
            centsOffset: cents, confidence: detection.confidence
        )
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

    // MARK: - Pitch Detection

    /// Raw detection result containing frequency and spectral confidence.
    struct PitchDetectionResult {
        let frequency: Double
        let confidence: Double
    }

    /// Autocorrelation-based pitch detection with spectral confidence.
    ///
    /// Returns both the detected frequency and a confidence metric based on
    /// peak-to-sidelobe ratio (via `SpectralConfidence`), replacing the
    /// naive amplitude-based heuristic.
    ///
    /// - Parameters:
    ///   - samples: Audio sample buffer.
    ///   - sampleRate: Sample rate in Hz.
    ///   - minFreq: AUD-022: Lower frequency bound (Hz). Default 50 Hz.
    ///   - maxFreq: AUD-022: Upper frequency bound (Hz). Default 4000 Hz.
    nonisolated static func detectPitchWithConfidence(
        samples: [Float],
        sampleRate: Double,
        minFreq: Double = 50.0,
        maxFreq: Double = 4000.0
    ) -> PitchDetectionResult {
        let autocorrelation = computeAutocorrelation(samples)
        guard !autocorrelation.isEmpty else {
            return PitchDetectionResult(frequency: 0, confidence: 0)
        }

        let halfLength = autocorrelation.count
        let minLag = max(2, Int(sampleRate / 4000.0))
        guard minLag < halfLength else {
            return PitchDetectionResult(frequency: 0, confidence: 0)
        }

        let bestLag = findBestLag(
            autocorrelation, minLag: minLag, halfLength: halfLength
        )
        guard bestLag > 0 else {
            return PitchDetectionResult(frequency: 0, confidence: 0)
        }

        let refinedLag = parabolicInterpolation(
            autocorrelation, lag: bestLag
        )
        guard refinedLag > 0 else {
            return PitchDetectionResult(frequency: 0, confidence: 0)
        }

        let frequency = sampleRate / refinedLag
        // AUD-022: Use configurable frequency bounds instead of hardcoded 50-4000 Hz.
        guard frequency > minFreq, frequency < maxFreq else {
            return PitchDetectionResult(frequency: 0, confidence: 0)
        }

        let confidence = SpectralConfidence.compute(
            autocorrelation: autocorrelation,
            bestLag: bestLag,
            minLag: minLag
        )

        return PitchDetectionResult(frequency: frequency, confidence: confidence)
    }
}
