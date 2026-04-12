import Accelerate
import AVFoundation
import Foundation
import Observation
import SVAudio
import SVCore
import Synchronization
import os.log

/// Module-level logger for @MainActor-isolated methods of PitchDetectionViewModel.
private let vmLogger = Logger.survibe(category: "PitchDetectionVM")

/// Carries a single DSP result from the processing queue to MainActor.
private struct DSPResult: Sendable {
    let amplitude: Double
    let frequency: Double
    let noteName: String
    let westernName: String
    let octave: Int
    let cents: Double
    let confidence: Double
}

/// Weak, Sendable reference to the ViewModel for use in Task closures.
private final class WeakVM: Sendable {
    private let storage: Mutex<WeakRef>
    private struct WeakRef: Sendable { weak var vm: PitchDetectionViewModel? }
    var vm: PitchDetectionViewModel? { storage.withLock { $0.vm } }
    init(_ vm: PitchDetectionViewModel) { self.storage = Mutex(WeakRef(vm: vm)) }
}

/// Detection mode controlling which pipeline runs.
enum DetectionMode: String, CaseIterable, Sendable {
    case melody, chord, both
    /// Localized display name for UI.
    var displayName: String {
        switch self {
        case .melody: String(localized: "Melody")
        case .chord: String(localized: "Chord")
        case .both: String(localized: "Both")
        }
    }
}

/// ViewModel for real-time pitch detection in PracticeTab.
///
/// Pipeline: mic tap (audio thread) -> dspQueue (PitchDSP/ChromagramDSP) -> MainActor UI update.
/// Supports melody, chord, and both detection modes.
@MainActor
@Observable
final class PitchDetectionViewModel {
    // MARK: - Dependencies

    /// Permission provider for microphone access checks and requests.
    private let permissions: any PermissionProviding

    /// Audio engine provider for mic tap and engine lifecycle.
    private let audioEngine: any AudioEngineProviding

    // MARK: - Initialization

    /// Create a new pitch detection view model.
    ///
    /// Pass `nil` for either parameter to use the production singleton.
    ///
    /// - Parameters:
    ///   - permissions: Permission provider. Defaults to `PermissionManager.shared`.
    ///   - audioEngine: Audio engine provider. Defaults to `AudioEngineManager.shared`.
    init(
        permissions: (any PermissionProviding)? = nil,
        audioEngine: (any AudioEngineProviding)? = nil
    ) {
        self.permissions = permissions ?? PermissionManager.shared
        self.audioEngine = audioEngine ?? AudioEngineManager.shared
    }

    // MARK: - Properties

    /// Current pitch result from detector (melody mode).
    var currentResult: PitchResult?
    /// Western note name for the current detection (C, D, E, etc.).
    var westernNoteName: String = ""
    /// Whether the detector is actively listening.
    var isListening = false
    /// Error message to display.
    var errorMessage: String?
    /// Detection history for the last few notes (rolling buffer, pre-allocated).
    var recentNotes: [DetectedNote] = { var a = [DetectedNote](); a.reserveCapacity(14); return a }()
    /// Debug status string for UI feedback.
    var debugStatus: String = "Not started"
    /// Number of pitch detections received.
    var detectionCount: Int = 0
    /// Absolute MIDI note number (36-96) for keyboard highlighting.
    var activeMidiNote: Int? {
        guard let result = currentResult,
              let swar = Swar.allCases.first(where: { $0.rawValue == result.noteName })
        else { return nil }
        return 60 + (result.octave - 4) * 12 + swar.midiOffset
    }
    /// Live amplitude level (0.0 to 1.0) for visual meter.
    var liveAmplitude: Double = 0
    /// Microphone permission status.
    var micStatus: MicrophonePermissionStatus { permissions.microphoneStatus }
    /// Current detection mode.
    var detectionMode: DetectionMode = .melody
    /// Current latency preset for chord detection.
    var latencyPreset: LatencyPreset = .fast
    /// Most recent chord detection result.
    var currentChordResult: ChordResult?
    /// Current pitch expression analysis result.
    var currentExpression: ExpressionResult?
    /// Active MIDI notes for multi-key highlighting.
    var activeMidiNotes: Set<Int> {
        if detectionMode != .melody, let chord = currentChordResult, !chord.detectedPitches.isEmpty {
            return chord.activeMidiNotes
        }
        if let single = activeMidiNote { return [single] }
        return []
    }
    /// Current chord name for display (e.g., "C Major").
    var chordDisplayName: String? { currentChordResult?.chordName?.displayName }
    /// Sargam chord name for display (e.g., "Sa Major").
    var sargamChordName: String? { currentChordResult?.chordName?.sargamDisplayName }

    private let maxRecentNotes = 12
    private let dspQueue = DispatchQueue(label: "com.survibe.pitch-dsp", qos: .userInteractive)
    private let referencePitch: Double = 440.0
    private var stopFlag: AtomicFlag?
    private var ringBuffer: AudioRingBuffer?
    private var lastReadSampleCount: Int = 0
    private var centsHistory: [Double] = []
    private let centsHistoryMaxSize = 22

    // MARK: - Public Methods

    /// Start listening for pitch via microphone.
    func startListening() async {
        guard !isListening else { return }
        errorMessage = nil
        debugStatus = "Requesting mic permission..."
        vmLogger.info("startListening called")

        guard await requestMicPermission() else { return }
        guard await startEngine() else { return }

        debugStatus = "Installing mic tap..."
        isListening = true
        detectionCount = 0

        // Connect visualization adapter to mainMixerNode (coexists with mic tap on inputNode)
        do {
            try AudioNodeAdapter.shared.connect()
        } catch {
            vmLogger.error("AudioNodeAdapter connection failed: \(error.localizedDescription)")
        }

        let context = prepareTapContext()
        let tapInstalled = audioEngine.installMicTap(
            bufferSize: nil,
            handler: buildMicTapHandler(context: context)
        )

        if tapInstalled {
            debugStatus = "Listening (\(context.mode.displayName)) — play a note"
            vmLogger.info("Mic tap installed, mode=\(context.mode.rawValue), listening")
        } else {
            isListening = false
            stopFlag = nil
            ringBuffer = nil
            errorMessage = String(localized: "Could not access microphone. Please check permissions and try again.")
            debugStatus = "Mic tap failed — check logs"
            vmLogger.error("installMicTap returned false — tap not installed")
        }
    }

    /// Stop listening and tear down audio.
    func stopListening() {
        stopFlag?.set()
        stopFlag = nil
        AudioNodeAdapter.shared.disconnect()
        audioEngine.removeMicTap()
        audioEngine.stop()
        isListening = false

        // Reset chord detection state
        ringBuffer?.reset()
        ringBuffer = nil
        currentChordResult = nil
        currentExpression = nil
        centsHistory = []
        lastReadSampleCount = 0

        debugStatus = "Stopped"
        vmLogger.info("stopListening complete")
    }

    /// URL to iOS Settings for mic permission (opened by the View via @Environment(\.openURL)).
    var settingsURL: URL? {
        permissions.settingsURL
    }
}

// MARK: - Listening Setup Helpers

private extension PitchDetectionViewModel {
    /// Request microphone permission. Returns `true` if granted.
    func requestMicPermission() async -> Bool {
        permissions.updateMicrophoneStatus()
        let granted = await permissions.requestMicrophoneAccess()
        if !granted {
            permissions.updateMicrophoneStatus()
            errorMessage = String(localized: "Microphone access is needed to detect notes.")
            debugStatus = "Mic permission denied"
            vmLogger.error("Mic permission denied")
        }
        return granted
    }

    /// Start the audio engine. Returns `true` if running.
    func startEngine() async -> Bool {
        debugStatus = "Starting audio engine..."
        vmLogger.info("Mic permission granted, starting engine")

        do {
            try audioEngine.start()
        } catch {
            errorMessage = String(localized: "Could not start audio: \(error.localizedDescription)")
            debugStatus = "Engine failed: \(error.localizedDescription)"
            vmLogger.error("Engine start failed: \(error.localizedDescription)")
            return false
        }

        vmLogger.info("Engine started, isRunning=\(self.audioEngine.isRunning)")
        try? await Task.sleep(for: .milliseconds(200))

        guard audioEngine.isRunning else {
            debugStatus = "Engine stopped during setup"
            vmLogger.warning("Engine stopped during sleep — aborting")
            return false
        }
        return true
    }

    /// Captures needed for the mic tap closure, bundled to avoid multi-field capture.
    struct TapContext: Sendable {
        let mode: DetectionMode
        let refPitch: Double
        let realSamples: Int
        let queue: DispatchQueue
        let counter: AtomicCounter
        let flag: AtomicFlag
        let ringBuf: AudioRingBuffer?
        let weakRef: WeakVM
    }

    /// Prepare the ring buffer and capture context for the mic tap.
    func prepareTapContext() -> TapContext {
        let mode = detectionMode
        let preset = latencyPreset

        if mode == .chord || mode == .both {
            ringBuffer = AudioRingBuffer(capacity: preset.realSamples * 2)
            lastReadSampleCount = 0
            centsHistory = []
        }

        let flag = AtomicFlag()
        self.stopFlag = flag

        return TapContext(
            mode: mode,
            refPitch: referencePitch,
            realSamples: preset.realSamples,
            queue: dspQueue,
            counter: AtomicCounter(),
            flag: flag,
            ringBuf: ringBuffer,
            weakRef: WeakVM(self)
        )
    }

    /// Build the mic tap handler closure from a prepared context.
    func buildMicTapHandler(context: TapContext) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            guard !context.flag.isSet,
                  let channelData = buffer.floatChannelData?[0],
                  buffer.frameLength > 0 else { return }
            let frameLength = Int(buffer.frameLength)
            let sampleRate = buffer.format.sampleRate
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
            if context.mode == .chord || context.mode == .both { context.ringBuf?.write(samples) }
            let bufNum = context.counter.increment()
            if bufNum % 50 == 1 {
                PitchDSP.logger.info("Tap #\(bufNum): frames=\(frameLength) rate=\(sampleRate)")
            }
            context.queue.async {
                guard !context.flag.isSet else { return }
                Self.processDSP(samples: samples, sampleRate: sampleRate, bufNum: bufNum, context: context)
            }
        }
    }
}

private extension PitchDetectionViewModel {
    /// Run melody and/or chord DSP, then dispatch results to MainActor.
    nonisolated static func processDSP(
        samples: [Float], sampleRate: Double, bufNum: Int, context: TapContext
    ) {
        let amplitude = PitchDSP.calculateRMS(samples)
        if bufNum % 50 == 1 { PitchDSP.logger.info("Buf #\(bufNum) amp=\(String(format: "%.6f", amplitude))") }
        let melody = runMelodyPipeline(
            samples: samples, sampleRate: sampleRate,
            amplitude: amplitude, mode: context.mode, refPitch: context.refPitch)
        let chord = runChordPipeline(
            mode: context.mode, ringBuf: context.ringBuf,
            realSamples: context.realSamples, sampleRate: sampleRate, refPitch: context.refPitch)
        let weakRef = context.weakRef, mode = context.mode
        Task { @MainActor in
            guard let vm = weakRef.vm, vm.isListening else { return }
            vm.applyResults(amplitude: amplitude, melodyResult: melody,
                            chordDetection: chord, centsForExpression: melody?.cents, mode: mode)
        }
    }

    /// Autocorrelation melody detection. Returns nil if below threshold.
    nonisolated static func runMelodyPipeline(
        samples: [Float], sampleRate: Double,
        amplitude: Double, mode: DetectionMode, refPitch: Double
    ) -> DSPResult? {
        guard mode == .melody || mode == .both, amplitude > 0.002 else { return nil }
        let detection = PitchDSP.detectPitchWithConfidence(samples: samples, sampleRate: sampleRate)
        guard detection.frequency > 0,
              let (name, oct, cents) = try? SwarUtility.frequencyToNote(
                  detection.frequency, referencePitch: refPitch)
        else { return nil }
        return DSPResult(amplitude: amplitude, frequency: detection.frequency, noteName: name,
                         westernName: SwarUtility.westernName(for: name),
                         octave: oct, cents: cents, confidence: detection.confidence)
    }

    /// FFT chromagram chord detection. Returns nil if not in chord mode.
    nonisolated static func runChordPipeline(
        mode: DetectionMode, ringBuf: AudioRingBuffer?,
        realSamples: Int, sampleRate: Double, refPitch: Double
    ) -> ChordResult? {
        guard mode == .chord || mode == .both,
              let ringBuf, let fftSamples = ringBuf.read(count: realSamples) else { return nil }
        return ChromagramDSP.analyzeChord(samples: fftSamples, sampleRate: sampleRate, referencePitch: refPitch)
    }

    /// Apply DSP results to ViewModel state on MainActor.
    func applyResults(
        amplitude: Double, melodyResult: DSPResult?,
        chordDetection: ChordResult?, centsForExpression: Double?, mode: DetectionMode
    ) {
        liveAmplitude = amplitude
        if let r = melodyResult {
            let pr = PitchResult(frequency: r.frequency, amplitude: r.amplitude,
                                 noteName: r.noteName, octave: r.octave,
                                 centsOffset: r.cents, confidence: r.confidence)
            detectionCount += 1
            currentResult = pr
            westernNoteName = r.westernName
            if detectionCount % 5 == 0 {
                debugStatus = "Detected: \(r.westernName)\(r.octave) (\(Int(r.frequency))Hz)"
            }
            appendNote(pr)
        } else if amplitude > 0.002 && mode != .chord {
            debugStatus = "Sound (amp: \(String(format: "%.3f", amplitude))) — no pitch"
        }
        if let chord = chordDetection {
            currentChordResult = chord
            if let name = chord.chordName { debugStatus = "Chord: \(name.displayName)" }
        }
        if let cents = centsForExpression {
            centsHistory.append(cents)
            // AUD-018: removeFirst() is O(1) amortized vs O(n) Array(suffix()) copy.
            if centsHistory.count > centsHistoryMaxSize {
                centsHistory.removeFirst()
            }
            if centsHistory.count >= 10 {
                currentExpression = PitchExpressionAnalyzer.analyze(
                    centsHistory: centsHistory, hopIntervalSeconds: 1024.0 / 44100.0)
            }
        }
    }

    /// Append a detected note to the rolling history, deduplicating consecutive identical notes.
    func appendNote(_ result: PitchResult) {
        let western = SwarUtility.westernName(for: result.noteName)
        let note = DetectedNote(swarName: result.noteName, westernName: western,
                                octave: result.octave, centsOffset: result.centsOffset,
                                frequency: result.frequency, timestamp: result.timestamp)
        if let last = recentNotes.last,
           last.swarName == note.swarName && last.octave == note.octave {
            recentNotes[recentNotes.count - 1] = note
            return
        }
        recentNotes.append(note)
        if recentNotes.count > maxRecentNotes {
            recentNotes = Array(recentNotes.suffix(maxRecentNotes))
        }
    }
}

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
private final class AtomicFlag: Sendable {
    private let value = Mutex<Bool>(false)
    // nonisolated: Mutex.withLock is itself nonisolated; safe from any thread.
    nonisolated var isSet: Bool { value.withLock { $0 } }
    nonisolated func set() { value.withLock { $0 = true } }
}

/// Thread-safe counter using Mutex for compiler-verified Sendable.
private final class AtomicCounter: Sendable {
    private let value = Mutex<Int>(0)
    @discardableResult
    // nonisolated: Mutex.withLock is itself nonisolated; safe from any thread.
    nonisolated func increment() -> Int { value.withLock { $0 += 1; return $0 } }
}

/// Stateless DSP functions for pitch detection. Safe to call from any thread.
/// `nonisolated` on the enum opts out of implicit `@MainActor` isolation
/// from `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in the app target.
nonisolated enum PitchDSP {
    /// Logger for DSP diagnostics — declared here (nonisolated context) so it
    /// can be used from @Sendable mic tap closures and nonisolated static methods.
    static let logger = Logger.survibe(category: "PitchDetectionVM")

    /// Result of pitch detection with spectral confidence.
    struct DetectionResult {
        let frequency: Double
        let confidence: Double
    }

    /// Calculate RMS amplitude from audio samples.
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
    static func detectPitch(samples: [Float], sampleRate: Double) -> Double {
        detectPitchWithConfidence(samples: samples, sampleRate: sampleRate).frequency
    }

    /// Pitch detection with spectral confidence using peak-to-sidelobe ratio.
    ///
    /// Returns both the detected frequency and a spectral confidence value (0.0–1.0)
    /// derived from the autocorrelation peak prominence rather than raw amplitude.
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
