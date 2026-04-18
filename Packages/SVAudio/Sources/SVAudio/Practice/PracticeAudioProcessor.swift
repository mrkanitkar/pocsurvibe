import AVFoundation
import Accelerate
import SVCore
import Synchronization
import os.log

// File-private logger accessible from nonisolated static methods.
// Logger is Sendable so this is safe to use from any isolation context.
private let practiceAudioLogger = Logger.survibe(category: "PracticeAudioProcessor")

/// Processes microphone audio during practice mode and produces pitch detection results.
///
/// Installs a mic tap on `AudioEngineManager.shared`, runs pitch detection
/// on a dedicated DSP task, and vends results as an `AsyncStream<PitchResult>`.
///
/// Audio thread safety: the mic tap callback writes raw samples into an
/// `SPSCRingBuffer` using lock-free atomic operations — zero heap allocation,
/// zero lock acquisition on the real-time audio thread (AUD-001, AUD-002, AUD-003).
///
/// Usage:
/// ```swift
/// let processor = PracticeAudioProcessor()
/// try processor.start()
/// for await pitch in processor.pitchStream {
///     // Handle PitchResult
/// }
/// processor.stop()
/// ```
@MainActor
public final class PracticeAudioProcessor {
    // MARK: - Properties

    /// Whether the processor is currently active and producing pitch results.
    public private(set) var isActive: Bool = false

    /// Latest chord analysis result from ChromagramDSP.
    ///
    /// Updated after each DSP cycle alongside pitch detection. Available for
    /// chord completeness scoring (M7). `nil` when no chord is detected or
    /// processor is stopped.
    public private(set) var lastChordResult: ChordResult?

    /// The async stream of pitch detection results.
    ///
    /// Yields `PitchResult` values as they are detected from the microphone.
    /// The stream terminates when `stop()` is called.
    public var pitchStream: AsyncStream<PitchResult> {
        guard let stream = _pitchStream else {
            return AsyncStream { $0.finish() }
        }
        return stream
    }

    /// The async stream of polyphonic chord analysis results (MIN-21).
    ///
    /// Yields a `ChordResult` after each DSP cycle in which `ChromagramDSP`
    /// detects two or more simultaneous pitches. Single-pitch results from
    /// monophonic input are filtered out to keep the stream limited to genuine
    /// chord events — `lastChordResult` still mirrors every analysis for
    /// keyboard-highlight consumers.
    ///
    /// The stream terminates when `stop()` is called.
    public var chordStream: AsyncStream<ChordResult> {
        guard let stream = _chordStream else {
            return AsyncStream { $0.finish() }
        }
        return stream
    }

    private var _pitchStream: AsyncStream<PitchResult>?
    private var continuation: AsyncStream<PitchResult>.Continuation?

    private var _chordStream: AsyncStream<ChordResult>?
    private var _chordContinuation: AsyncStream<ChordResult>.Continuation?

    /// Lock-free SPSC ring buffer shared between the audio callback and DSP task.
    ///
    /// Producer: audio render thread via `write()` — lock-free atomic write.
    /// Consumer: DSP task via `readLatest()` — lock-free atomic read.
    /// Capacity: 8192 samples (≥4× the maximum tap buffer of 2048 frames).
    private let spscBuffer = SPSCRingBuffer(capacity: 8192)

    /// AUD-007: Signal stream to wake the DSP task immediately when new audio
    /// data arrives, eliminating the 50ms polling sleep.
    ///
    /// The tap callback yields `()` here after each `spsc.write(ptr)`.
    /// The DSP loop does `for await _ in tapSignal { process() }` instead of
    /// `while true { sleep(50ms); if hasData { process() } }`.
    ///
    /// Buffer policy `bufferingNewest(1)` ensures that if the DSP task is slow,
    /// signals are coalesced — one wakeup per accumulated batch, not N wakeups.
    private var tapSignalContinuation: AsyncStream<Void>.Continuation?
    private var tapSignal: AsyncStream<Void> = AsyncStream { _ in }

    /// Optional event logger for persisting pitch detection results to SwiftData.
    public var eventLogger: (any EventLogging)?

    /// Reference pitch for frequency-to-note conversion (A4, in Hz).
    public var referencePitch: Double = 440.0

    /// Optional lock-free ring buffer to receive a copy of all mic samples.
    ///
    /// When set, every audio frame delivered to the mic tap is also written
    /// into this buffer so callers can run FFT-based chord detection
    /// (e.g. `ChromagramDSP.analyzeChord`) on a larger, accumulated window.
    /// Set to `nil` to disable. `SPSCRingBuffer` is `Sendable` and uses
    /// lock-free atomic indices — safe to write from the audio render thread
    /// with zero allocation (AUD-001/002/003).
    public var ringBuffer: SPSCRingBuffer?

    /// Minimum RMS amplitude to consider a buffer worth analyzing.
    ///
    /// 0.005 (~0.5% of full scale) is appropriate for acoustic instruments
    /// (piano, guitar) picked up 0.5–2m from the device microphone.
    /// Lower values increase sensitivity at the cost of processing noise.
    private let silenceThreshold: Double = 0.005

    /// Minimum autocorrelation confidence for a pitch result to be yielded.
    ///
    /// 0.3 is a practical lower bound for piano notes: the fundamental
    /// autocorrelation peak can be weaker than harmonic peaks on bright-toned
    /// instruments. The caller (PlayAlongViewModel) applies its own confidence
    /// filter via PracticeConstants.confidenceThreshold.
    private let confidenceThreshold: Double = 0.3

    /// DSP processing task.
    private var dspTask: Task<Void, Never>?

    private static let logger = Logger.survibe(category: "PracticeAudioProcessor")

    // MARK: - Initialization

    /// Create a new practice audio processor.
    public init() {}

    // MARK: - Public Methods

    /// Start capturing microphone audio and producing pitch results.
    ///
    /// Ensures the audio engine is running in playAndRecord mode, installs
    /// a mic tap, and begins DSP processing on a background task.
    ///
    /// - Throws: `PracticeAudioProcessorError.micTapFailed` if the mic tap
    ///   could not be installed, or any error from `AudioEngineManager.shared.start()`.
    public func start() throws {
        guard !isActive else { return }

        // Ensure engine is in playAndRecord mode for mic access
        try AudioEngineManager.shared.start()

        // Create the AsyncStream
        let (stream, cont) = AsyncStream<PitchResult>.makeStream()
        _pitchStream = stream
        continuation = cont

        // MIN-21: Create the chord AsyncStream alongside pitchStream.
        let (chordStreamLocal, chordCont) = AsyncStream<ChordResult>.makeStream()
        _chordStream = chordStreamLocal
        _chordContinuation = chordCont

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
        let capturedRingBuffer = ringBuffer
        // AUD-011: tap callback counter uses Atomic<Int> — truly lock-free on audio thread.
        let tapCount = Atomic<Int>(0)
        let tapLogger = Self.logger

        let installed = AudioEngineManager.shared.installMicTap { [signalCont] pcmBuffer, _ in
            guard let channelData = pcmBuffer.floatChannelData?[0] else {
                #if DEBUG
                tapLogger.error("MicDiag tap: no float channel data")
                #endif
                return
            }
            let frameLength = Int(pcmBuffer.frameLength)
            guard frameLength > 0 else { return }

            // AUD-001: write raw pointer directly — no Array construction on audio thread.
            let ptr = UnsafeBufferPointer(start: channelData, count: frameLength)
            spsc.write(ptr)

            // AUD-007: Signal the DSP task that new data is available.
            // This is lock-free (AsyncStream.Continuation.yield is atomic) and
            // replaces the 50ms polling sleep in startDSPLoop().
            signalCont.yield(())

            // Also feed the optional secondary SPSC ring buffer for chord-detection
            // consumers (e.g. PlayAlongViewModel chord pipeline). Lock-free
            // pointer write — zero heap allocation on the audio thread.
            capturedRingBuffer?.write(ptr)

            // AUD-011: diagnostic logging — debug builds only.
            #if DEBUG
            let count = tapCount.wrappingAdd(1, ordering: .relaxed).newValue
            if count == 1 || count % 100 == 0 {
                let rate = pcmBuffer.format.sampleRate
                tapLogger.info(
                    "MicDiag tap: count=\(count) frames=\(frameLength) rate=\(String(format: "%.0f", rate))Hz"
                )
            }
            #endif
        }

        guard installed else {
            cont.finish()
            _pitchStream = nil
            continuation = nil
            chordCont.finish()
            _chordStream = nil
            _chordContinuation = nil
            Self.logger.error("Failed to install mic tap")
            throw PracticeAudioProcessorError.micTapFailed
        }

        isActive = true
        startDSPLoop()
        Self.logger.info("PracticeAudioProcessor started")
    }

    /// Stop capturing audio and finish the pitch stream.
    ///
    /// Cancels the DSP processing task, removes the mic tap, and terminates
    /// the pitch result stream. Safe to call if not currently active.
    public func stop() {
        guard isActive else { return }

        dspTask?.cancel()
        dspTask = nil
        AudioEngineManager.shared.removeMicTap()
        // AUD-007: Finish the tap signal stream so the DSP task's `for await` loop exits.
        tapSignalContinuation?.finish()
        tapSignalContinuation = nil
        continuation?.finish()
        continuation = nil
        _pitchStream = nil
        // MIN-21: terminate the chord stream so consumers' `for await` exits.
        _chordContinuation?.finish()
        _chordContinuation = nil
        _chordStream = nil
        lastChordResult = nil
        isActive = false
        Self.logger.info("PracticeAudioProcessor stopped")
    }

    // MARK: - Private Methods

    /// Start the DSP processing loop.
    ///
    /// AUD-007: Event-driven via `tapSignal` AsyncStream. The loop wakes
    /// immediately each time the mic tap delivers a new buffer, eliminating
    /// the 50ms polling sleep.
    ///
    /// ## Sliding Window (M4b)
    /// The tap fires on every I/O callback (~5.8ms at 256-frame buffer).
    /// `readLatest(count: 2048)` always reads the most recent 2048 samples,
    /// overlapping with previous reads. This gives pitch detection latency of
    /// ~7-8ms (1 I/O buffer + DSP) instead of waiting for a full non-overlapping
    /// 2048-frame window (~46ms).
    ///
    /// Reads the latest 2048 audio samples from the SPSC ring buffer into
    /// a pre-allocated working buffer, performs autocorrelation-based pitch
    /// detection via vDSP, and yields results to the async stream.
    private func startDSPLoop() {
        let spsc = spscBuffer
        let refPitch = referencePitch
        let silenceThresh = silenceThreshold
        let confThresh = confidenceThreshold
        let bufferSize = 2048
        let signal = tapSignal

        // Allocate the DSP work buffer once — reused on every iteration.
        let workBuf = UnsafeMutableBufferPointer<Float>.allocate(capacity: bufferSize)
        workBuf.initialize(repeating: 0.0)

        dspTask = Task { [weak self] in
            defer { workBuf.deallocate() }

            #if DEBUG
            var processedCount = 0
            var detectedCount = 0
            #endif

            // AUD-007: Wait for tap signals instead of sleeping every 50ms.
            // The stream finishes when stop() calls tapSignalContinuation.finish().
            for await _ in signal {
                guard !Task.isCancelled else { break }

                // AUD-002: read latest samples into pre-allocated buffer — zero allocation.
                let hasData = spsc.readLatest(count: bufferSize, into: workBuf)
                guard hasData else { continue }

                #if DEBUG
                processedCount += 1
                if processedCount == 1 || processedCount % 20 == 0 {
                    Self.logDSPDiagnostics(
                        workBuf, processed: processedCount,
                        detected: detectedCount, bufferSize: bufferSize
                    )
                }
                #endif

                let result = Self.detectPitch(
                    from: workBuf,
                    referencePitch: refPitch,
                    silenceThreshold: silenceThresh,
                    confidenceThreshold: confThresh
                )

                if let result {
                    #if DEBUG
                    detectedCount += 1
                    Self.logPitchDetection(result, count: detectedCount)
                    #endif
                    self?.continuation?.yield(result)
                }

                // Run chord analysis on the same sample buffer.
                let chordResult = Self.analyzeChordFromBuffer(
                    workBuf, count: bufferSize, referencePitch: refPitch
                )
                // MIN-21: yield to the chord stream only when ≥2 simultaneous
                // pitches are detected — filters single-note chromagram noise
                // produced by monophonic input. AsyncStream.Continuation is
                // Sendable, so yielding does not require an actor hop.
                if chordResult.detectedPitches.count >= 2 {
                    self?._chordContinuation?.yield(chordResult)
                }
                await MainActor.run { [weak self] in
                    self?.lastChordResult = chordResult
                }
            }
        }
    }

    /// Perform pitch detection on a pre-allocated buffer using autocorrelation.
    ///
    /// This is a `nonisolated static` method so it can be called from any
    /// isolation context without capturing `self`.
    ///
    /// - Parameters:
    ///   - buffer: Pre-allocated buffer containing audio samples.
    ///   - referencePitch: Reference pitch for A4 (Hz).
    ///   - silenceThreshold: Minimum amplitude to process.
    ///   - confidenceThreshold: Minimum confidence for results.
    /// - Returns: A `PitchResult` if pitch was detected above thresholds, nil otherwise.
    nonisolated private static func detectPitch(
        from buffer: UnsafeMutableBufferPointer<Float>,
        referencePitch: Double,
        silenceThreshold: Double,
        confidenceThreshold: Double
    ) -> PitchResult? {
        guard let base = buffer.baseAddress, !buffer.isEmpty else { return nil }
        let ptr = UnsafeBufferPointer(start: base, count: buffer.count)

        let rms = calculateRMS(ptr)
        guard rms >= silenceThreshold else { return nil }

        let sampleRate: Double = 44100.0
        let result = findBestCorrelation(samples: ptr, sampleRate: sampleRate)
        guard result.confidence >= confidenceThreshold, result.lag > 0 else { return nil }

        let frequency = sampleRate / Double(result.lag)

        guard let (noteName, octave, centsOffset) = try? SwarUtility.frequencyToNote(
            frequency, referencePitch: referencePitch
        ) else { return nil }

        return PitchResult(
            frequency: frequency, amplitude: rms,
            noteName: noteName, octave: octave,
            centsOffset: centsOffset, confidence: result.confidence
        )
    }

    /// Calculate RMS amplitude using vDSP (vectorized).
    nonisolated private static func calculateRMS(_ samples: UnsafeBufferPointer<Float>) -> Double {
        var rms: Float = 0
        guard let base = samples.baseAddress else { return 0 }
        vDSP_rmsqv(base, 1, &rms, vDSP_Length(samples.count))
        return Double(rms)
    }

    /// Calculate RMS from a mutable buffer pointer (DSP work buffer variant).
    nonisolated private static func calculateRMS(_ buffer: UnsafeMutableBufferPointer<Float>) -> Double {
        var rms: Float = 0
        guard let base = buffer.baseAddress else { return 0 }
        vDSP_rmsqv(base, 1, &rms, vDSP_Length(buffer.count))
        return Double(rms)
    }

    /// Run polyphonic chord analysis on the DSP work buffer via ChromagramDSP.
    ///
    /// Copies samples from the pre-allocated `UnsafeMutableBufferPointer` into
    /// an `[Float]` for `ChromagramDSP.analyzeChord`. The allocation is acceptable
    /// here because this runs on the DSP task, not the real-time audio thread.
    nonisolated private static func analyzeChordFromBuffer(
        _ buffer: UnsafeMutableBufferPointer<Float>,
        count: Int,
        referencePitch: Double
    ) -> ChordResult {
        ChromagramDSP.analyzeChord(
            samples: Array(buffer[0..<count]),
            sampleRate: 44100,
            referencePitch: referencePitch
        )
    }

    /// Log periodic DSP buffer diagnostics (debug builds only).
    #if DEBUG
    nonisolated private static func logDSPDiagnostics(
        _ buffer: UnsafeMutableBufferPointer<Float>,
        processed: Int, detected: Int, bufferSize: Int
    ) {
        let rmsStr = String(format: "%.4f", calculateRMS(buffer))
        practiceAudioLogger.info("MicDiag: proc=\(processed) det=\(detected) rms=\(rmsStr) fr=\(bufferSize)")
    }

    /// Log a pitch detection result (debug builds only).
    nonisolated private static func logPitchDetection(_ result: PitchResult, count: Int) {
        let freqStr = String(format: "%.1f", result.frequency)
        let confStr = String(format: "%.2f", result.confidence)
        practiceAudioLogger.info("MicDiag: \(result.noteName)\(result.octave) \(freqStr)Hz cf=\(confStr) #\(count)")
    }
    #endif

    /// Find the best autocorrelation lag using vDSP_dotpr (AUD-025).
    ///
    /// Replaces the scalar O(n²) nested loop. Uses three `vDSP_dotpr` calls per lag
    /// (cross-correlation, norm1, norm2) for vectorized normalized correlation.
    /// Total cost: O(n/2 × lags) SIMD vs O(n × lags) scalar.
    nonisolated private static func findBestCorrelation(
        samples: UnsafeBufferPointer<Float>, sampleRate: Double
    ) -> (lag: Int, confidence: Double) {
        let frameLength = samples.count
        let minLag = Int(sampleRate / 2000.0)
        let maxLag = min(Int(sampleRate / 50.0), frameLength / 2)
        guard minLag < maxLag, let base = samples.baseAddress else { return (0, 0) }

        let halfLength = frameLength / 2
        var bestCorrelation: Float = 0
        var bestLag = 0

        for lag in minLag..<maxLag {
            let compareLength = vDSP_Length(min(frameLength - lag, halfLength))
            guard compareLength > 0 else { continue }

            var correlation: Float = 0
            var norm1: Float = 0
            var norm2: Float = 0

            vDSP_dotpr(base, 1, base + lag, 1, &correlation, compareLength)
            vDSP_dotpr(base, 1, base, 1, &norm1, compareLength)
            vDSP_dotpr(base + lag, 1, base + lag, 1, &norm2, compareLength)

            let normProduct = sqrt(norm1 * norm2)
            guard normProduct > 0 else { continue }
            let normalized = correlation / normProduct

            if normalized > bestCorrelation {
                bestCorrelation = normalized
                bestLag = lag
            }
        }

        return (bestLag, Double(bestCorrelation))
    }
}

/// Errors from the practice audio processor.
public enum PracticeAudioProcessorError: SurVibeError {
    /// The microphone tap could not be installed.
    case micTapFailed

    public var domain: String { "SVAudio" }

    public var code: String {
        switch self {
        case .micTapFailed: "mic_tap_failed"
        }
    }

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .micTapFailed:
            String(localized: "Failed to install microphone tap for practice mode")
        }
    }
}
