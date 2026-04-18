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
public final class MicPitchDetector: PitchDetectorProtocol {
    private var continuation: AsyncStream<PitchResult>.Continuation?

    /// Whether the detector is currently active.
    ///
    /// Transitions to `true` inside `start()` once the mic tap is installed,
    /// and back to `false` on `stop()` or on tap-install failure.
    /// Exposed so coordinators (e.g. `PracticeAudioProcessor`) can detect
    /// `start()` failures without relying on empty streams.
    public private(set) var isDetecting = false

    /// Reference pitch for frequency-to-note conversion (default: A4 = 440 Hz).
    public var referencePitch: Double = 440.0

    /// Voice-rejection gate applied after pitch detection.
    ///
    /// Default: `DefaultRobustPitchGate` (no-op). Set to a `SoundAnalysisGate`
    /// instance to enable Layer 3 vocal/humming suppression. Settings UI
    /// swaps this based on the "Robust pitch detection" toggle.
    ///
    /// The gate is captured once into the DSP loop at `start()`. Mutating it
    /// during an active session has no effect until the next `stop()`/`start()`
    /// cycle — this matches the Settings-toggle UX (session restart).
    public var robustGate: any RobustPitchGate = DefaultRobustPitchGate()

    /// Capacity of the rolling RMS history maintained inside the DSP task.
    ///
    /// Kept on the type so tests and callers can reason about the window
    /// length, but the actual storage lives inside the DSP closure (no
    /// actor-isolated mutation on the hot path).
    public static let rmsHistoryCapacity = 8

    /// Minimum detectable mic-path frequency in Hz (default: 130 Hz = C3).
    ///
    /// Below C3, pitch detection latency exceeds the 25 ms product budget
    /// for playalong feedback: autocorrelation needs ~2 periods of the note
    /// (C3 period ≈ 7.7 ms; 2 periods ≈ 15.4 ms), plus I/O, DSP, and UI.
    /// Users needing bass notes must connect a MIDI keyboard. Lower this
    /// to relax the floor (accepting longer detection latency on bass).
    public var minimumFrequency: Double = 130.0

    /// Maximum detectable mic-path frequency in Hz (default: 4200 Hz).
    ///
    /// Covers the full piano range (C8 = 4186 Hz) with ~14 Hz margin.
    /// Raised from 4000 Hz per micissues.md I3. Raising further requires
    /// more autocorrelation precision and is rarely useful — piano notes
    /// above C8 are not on standard 88-key instruments.
    public var maximumFrequency: Double = 4200.0

    /// Number of audio buffers processed (for diagnostics).
    ///
    /// Backed by an atomic counter so the DSP task can increment it without
    /// bouncing onto MainActor. Readable from any isolation.
    public nonisolated var bufferCount: Int { _bufferCountBox.load() }
    private let _bufferCountBox = AtomicIntBox(initial: 0)

    /// Last measured amplitude (for diagnostics / live meter).
    ///
    /// Backed by an atomic so the DSP task can publish it without bouncing
    /// onto MainActor. Readable from any isolation.
    public nonisolated var lastAmplitude: Double { _lastAmplitudeBox.load() }
    private let _lastAmplitudeBox = AtomicDoubleBox(initial: 0)

    /// Current detector status for UI feedback.
    public private(set) var status: String = "Idle"

    /// Lock-free SPSC ring buffer shared between the audio callback and DSP task.
    ///
    /// Producer: audio render thread via `write()` — lock-free atomic write.
    /// Consumer: DSP task via `readLatest()` — lock-free atomic read.
    /// Capacity: 16384 samples — holds up to 2× the largest supported DSP
    /// window (8192 for `.precise`) so `readLatest` never starves when
    /// users pick the slowest preset.
    private let spscBuffer = SPSCRingBuffer(capacity: 16384)

    /// DSP analysis window in samples. Set before `start()`.
    ///
    /// Captured into the DSP closure on each `start()`. Maps to
    /// `LatencyPreset.realSamples`:
    /// - Ultra Fast: 1024 (~21 ms @ 48 kHz) — fastest, requires ≥A3
    /// - Fast: 2048 (~43 ms) — default, works from C3
    /// - Balanced: 4096 (~85 ms) — best noise rejection
    /// - Precise: 8192 (~170 ms) — slowest, most accurate for bass
    ///
    /// Changing this while a session is active has no effect until the
    /// next `stop()`/`start()` cycle.
    public var dspBufferSize: Int = 2048

    /// Optional secondary SPSC ring buffer that receives a copy of every
    /// mic sample delivered to the tap.
    ///
    /// Set before `start()` (e.g. by `PracticeAudioProcessor` for polyphonic
    /// chord analysis). iOS allows only one tap per input node, so callers
    /// who need a parallel FFT or chromagram pipeline must share the tap
    /// via this buffer. Cleared by `stop()`.
    public var secondaryRingBuffer: SPSCRingBuffer?

    /// Sample rate captured from the most recent tap buffer.
    ///
    /// Written by the audio render thread on every tap (lock-free),
    /// read by the DSP task and by external consumers (e.g. chord
    /// analysis) that need the real sample rate rather than a hardcoded
    /// 44100. See micissues.md I2.
    public let liveSampleRate = AtomicDoubleBox(initial: 44100.0)

    /// Lock-free `Atomic<Bool>` signal that wakes the DSP task when new
    /// audio data arrives.
    ///
    /// The mic tap stores `true` after each `spscBuffer.write(ptr)`; the
    /// DSP task `exchange(false)` each loop iteration to detect pending
    /// work. `Atomic<Bool>.store/exchange` are documented lock-free and
    /// allocation-free — contractually RT-safe on the audio render thread.
    ///
    /// Replaces the previous `AsyncStream<Void>` signal, whose `yield(())`
    /// call is not contractually RT-safe (Swift runtime gives no
    /// allocation-free / lock-free guarantee). See micissues.md I6.
    private let tapSignal = AtomicBoolBox(initial: false)

    /// Stop flag for the DSP task. Set by `stopInternal()` to break the
    /// poll loop cooperatively (alongside `Task.isCancelled`).
    private let dspStopFlag = AtomicBoolBox(initial: false)

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
                assertionFailure("MicPitchDetector deallocated while still detecting. Call stop() first.")
            #endif
            continuation?.finish()
            dspStopFlag.store(true)
            dspTask?.cancel()
            Task { @MainActor in
                AudioEngineManager.shared.removeMicTap()
            }
        }
    }

    public func start() -> AsyncStream<PitchResult> {
        // Stop any previous session
        stopInternal()
        _bufferCountBox.store(0)
        _lastAmplitudeBox.store(0)
        status = "Starting..."

        // micissues.md I1: ensure the audio engine is running in
        // playAndRecord mode before installing the mic tap. Without this,
        // installMicTap returns false silently (engine not running) and the
        // detector hangs in "Listening" state. Making the engine-start
        // failure explicit — if it throws, we finish the stream immediately.
        do {
            try AudioEngineManager.shared.start()
        } catch {
            pitchLogger.error(
                "AudioEngineManager.shared.start() failed: \(error.localizedDescription, privacy: .public)"
            )
            status = "Engine start failed"
            let (emptyStream, emptyCont) = AsyncStream<PitchResult>.makeStream()
            emptyCont.finish()
            return emptyStream
        }

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

        // Reset RT-safe signal flags before starting the DSP loop.
        tapSignal.store(false)
        dspStopFlag.store(false)

        // Install mic tap — audio callback writes raw samples into SPSCRingBuffer.
        // AUD-001/002/003: zero heap allocation, zero lock acquisition on audio thread.
        let spsc = spscBuffer
        // Capture the Sendable boxes for the @Sendable closure.
        let signalBox = tapSignal
        let rateBox = liveSampleRate
        let secondaryBuf = secondaryRingBuffer
        // Feed SoundAnalysis if the current gate is one. Capture once to avoid
        // re-evaluating `robustGate` on every tap (which is not Sendable-safe).
        let soundGate = robustGate as? SoundAnalysisGate
        // AUD-011: tap callback counter uses Atomic<Int> — truly lock-free on audio thread.
        let tapCount = Atomic<Int>(0)

        let installed = AudioEngineManager.shared.installMicTap { buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            // micissues.md I2: capture live sample rate — lock-free Atomic store.
            rateBox.store(buffer.format.sampleRate)

            // AUD-001: write raw pointer directly — no Array construction on audio thread.
            let ptr = UnsafeBufferPointer(start: channelData, count: frameLength)
            spsc.write(ptr)

            // Feed the optional secondary ring buffer (e.g. PracticeAudioProcessor
            // chord analysis). Lock-free write with the same pointer — zero alloc.
            secondaryBuf?.write(ptr)

            // Layer 3: feed the SoundAnalysisGate if one is configured.
            // SNAudioStreamAnalyzer.analyze copies and defers per Apple docs.
            soundGate?.analyze(buffer, atAudioFramePosition: 0)

            // micissues.md I6: RT-safe signal via Atomic<Bool>.store — the
            // Swift runtime guarantees this is lock-free and allocation-free.
            // Replaces the previous `AsyncStream.Continuation.yield(())`
            // which is not contractually RT-safe.
            signalBox.store(true)

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

        // micissues.md C4: previously the installMicTap return value was
        // ignored, so the detector would silently report "Listening" while
        // receiving no audio (engine not running, 0 channels, etc.).
        // Fail fast and finish the stream so callers see the error.
        guard installed else {
            pitchLogger.error(
                "installMicTap returned false — engine not running or 0 channels"
            )
            self.status = "Mic tap failed"
            continuation.finish()
            self.continuation = nil
            self.isDetecting = false
            return stream
        }

        self.status = "Listening"
        pitchLogger.info("Pitch detector started, mic tap installed")

        // Capture the current gate once — mutations during an active session
        // are intentionally not observed; the Settings UX already restarts
        // the session when the toggle changes.
        let capturedGate = robustGate

        // Clamp DSP window to a sane range the SPSC can serve.
        let capturedDSPBufferSize = max(512, min(8192, dspBufferSize))

        // Start the signal-driven DSP loop.
        startDSPLoop(
            dspBufferSize: capturedDSPBufferSize,
            refPitch: refPitch,
            minFreq: minFreq,
            maxFreq: maxFreq,
            robustGate: capturedGate,
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
        // micissues.md I6: signal the DSP poll loop to exit cooperatively.
        dspStopFlag.store(true)
        dspTask?.cancel()
        dspTask = nil
        AudioEngineManager.shared.removeMicTap()
        continuation?.finish()
        continuation = nil
        pitchLogger.info("Pitch detector stopped")
    }

    // MARK: - DSP Loop (signal-driven)

    /// Start the signal-driven DSP processing loop.
    ///
    /// micissues.md I6 / AUD-036: polls an `Atomic<Bool>` flag set by the
    /// audio-thread tap callback, yielding CPU via `Task.yield()` between
    /// checks. Replaces the previous `AsyncStream<Void>` signal whose
    /// `yield(())` call is not contractually RT-safe.
    ///
    /// Reads the latest 2048 audio samples from the SPSC ring buffer
    /// into a pre-allocated working buffer, performs autocorrelation-based
    /// pitch detection via vDSP, and yields results to the async stream.
    private func startDSPLoop(
        dspBufferSize: Int,
        refPitch: Double,
        minFreq: Double,
        maxFreq: Double,
        robustGate: any RobustPitchGate,
        continuation: AsyncStream<PitchResult>.Continuation
    ) {
        let spsc = spscBuffer
        let bufferSize = dspBufferSize
        let signalBox = tapSignal
        let stopFlag = dspStopFlag
        let rateBox = liveSampleRate
        let amplitudeBox = _lastAmplitudeBox
        let countBox = _bufferCountBox
        let historyCapacity = Self.rmsHistoryCapacity

        // Allocate the DSP work buffer once — reused on every iteration.
        let workBuf = UnsafeMutableBufferPointer<Float>.allocate(capacity: bufferSize)
        workBuf.initialize(repeating: 0.0)

        dspTask = Task(priority: .userInitiated) { [robustGate] in
            defer { workBuf.deallocate() }

            // Local rolling RMS history — owned by the DSP task, no isolation
            // hop required. Resets implicitly every `start()` (fresh closure).
            var rmsHistory: [Float] = []
            rmsHistory.reserveCapacity(historyCapacity)

            #if DEBUG
                var processedCount = 0
            #endif

            // micissues.md I6: cooperative poll + yield loop. Exits on
            // Task cancel OR dspStopFlag. Task.yield() relinquishes CPU
            // to other work between checks, so this is not a busy-wait.
            while !Task.isCancelled, !stopFlag.load() {
                // Swap signal to false and act only if it was true.
                guard signalBox.exchange(false) else {
                    await Task.yield()
                    continue
                }

                // AUD-002: read latest samples into pre-allocated buffer — zero allocation.
                let hasData = spsc.readLatest(count: bufferSize, into: workBuf)
                guard hasData else { continue }

                #if DEBUG
                    processedCount += 1
                #endif

                // Stamp t0 (input received) at DSP loop read — the earliest
                // point the mic data is actionable in software.
                var probeToken = ProbeToken()
                probeToken.stamp(.inputReceived)

                let signpostID = pitchSignposter.makeSignpostID()
                let state = pitchSignposter.beginInterval("PitchDetection", id: signpostID)
                let sampleRate = rateBox.load()
                let result = Self.processWorkBuffer(
                    workBuf,
                    bufferSize: bufferSize,
                    sampleRate: sampleRate,
                    refPitch: refPitch,
                    minFreq: minFreq,
                    maxFreq: maxFreq
                )
                pitchSignposter.endInterval("PitchDetection", state)

                // Stamp t1 (DSP complete) after pitch detection finishes.
                probeToken.stamp(.dspComplete)

                #if DEBUG
                    if processedCount % 50 == 1 {
                        let ampStr = String(format: "%.6f", result?.amplitude ?? 0)
                        pitchLogger.info(
                            "DSP buffer #\(processedCount) amp=\(ampStr)"
                        )
                    }
                #endif

                if var detected = result {
                    // Voice rejection gates. Layer 1 (attack slope) uses a
                    // short ring of recent RMS values to distinguish piano
                    // impulsive attacks from voice gradual ramps. Layer 3
                    // (optional SoundAnalysis) runs via robustGate.
                    rmsHistory.append(Float(detected.amplitude))
                    if rmsHistory.count > historyCapacity {
                        rmsHistory.removeFirst(rmsHistory.count - historyCapacity)
                    }

                    // RMS is measured over the DSP work buffer (`bufferSize`
                    // samples), so each history entry represents one such
                    // frame. Passing 256 here — as the previous revision did
                    // — under-reports attack duration 8×.
                    let attackOK = VoiceRejection.attackSlopeGate(
                        rmsHistory: rmsHistory,
                        sampleRate: sampleRate,
                        frameSize: bufferSize
                    )

                    let robustOK = robustGate.shouldAccept(
                        frequency: detected.frequency,
                        amplitude: detected.amplitude,
                        confidence: detected.confidence
                    )

                    if !attackOK || !robustOK {
                        continuation.yield(Self.silenceResult(amplitude: detected.amplitude))
                    } else {
                        detected.probeToken = probeToken
                        continuation.yield(detected)
                        amplitudeBox.store(detected.amplitude)
                        countBox.increment()
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
        sampleRate: Double,
        refPitch: Double,
        minFreq: Double,
        maxFreq: Double
    ) -> PitchResult? {
        guard let base = workBuf.baseAddress, bufferSize > 0 else { return nil }

        let samples = UnsafeBufferPointer(start: base, count: bufferSize)
        let amplitude = calculateRMS(samples)

        guard amplitude > 0.002 else { return nil }

        // micissues.md I7: use the pointer variant to avoid an ~8 KB Array
        // allocation on every DSP iteration (~170 Hz rate = 1.4 MB/s churn).
        let detection = detectPitchWithConfidenceFromPointer(
            samples: samples,
            sampleRate: sampleRate,
            minFreq: minFreq,
            maxFreq: maxFreq
        )

        guard detection.frequency > 0,
            let (noteName, octave, cents) = try? SwarUtility.frequencyToNote(
                detection.frequency,
                referencePitch: refPitch
            )
        else { return nil }

        return PitchResult(
            frequency: detection.frequency,
            amplitude: amplitude,
            noteName: noteName,
            octave: octave,
            centsOffset: cents,
            confidence: detection.confidence
        )
    }

    /// Create a silent/no-pitch result for the given amplitude.
    nonisolated private static func silenceResult(
        amplitude: Double
    ) -> PitchResult {
        PitchResult(
            frequency: 0,
            amplitude: amplitude,
            noteName: "",
            octave: 0,
            centsOffset: 0,
            confidence: 0
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
            autocorrelation,
            minLag: minLag,
            halfLength: halfLength
        )
        guard bestLag > 0 else {
            return PitchDetectionResult(frequency: 0, confidence: 0)
        }

        let refinedLag = parabolicInterpolation(
            autocorrelation,
            lag: bestLag
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

    /// Pointer-based variant of `detectPitchWithConfidence` — no Array allocation.
    ///
    /// Fixes micissues.md I7 by accepting an `UnsafeBufferPointer<Float>`
    /// directly instead of `[Float]`. Eliminates the per-iteration
    /// `Array(samples)` allocation in `processWorkBuffer` (~8 KB × ~170 Hz
    /// = ~1.4 MB/s allocation churn on the DSP task).
    nonisolated static func detectPitchWithConfidenceFromPointer(
        samples: UnsafeBufferPointer<Float>,
        sampleRate: Double,
        minFreq: Double = 50.0,
        maxFreq: Double = 4000.0
    ) -> PitchDetectionResult {
        let autocorrelation = computeAutocorrelationFromPointer(samples)
        guard !autocorrelation.isEmpty else {
            return PitchDetectionResult(frequency: 0, confidence: 0)
        }

        let halfLength = autocorrelation.count
        let minLag = max(2, Int(sampleRate / 4000.0))
        guard minLag < halfLength else {
            return PitchDetectionResult(frequency: 0, confidence: 0)
        }

        let bestLag = findBestLag(
            autocorrelation,
            minLag: minLag,
            halfLength: halfLength
        )
        guard bestLag > 0 else {
            return PitchDetectionResult(frequency: 0, confidence: 0)
        }

        let refinedLag = parabolicInterpolation(
            autocorrelation,
            lag: bestLag
        )
        guard refinedLag > 0 else {
            return PitchDetectionResult(frequency: 0, confidence: 0)
        }

        let frequency = sampleRate / refinedLag
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
