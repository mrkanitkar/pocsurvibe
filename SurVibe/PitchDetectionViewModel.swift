import AVFoundation
import Accelerate
import Foundation
import Observation
import SVAudio
import SVCore
import Synchronization
import os.log

/// Module-level logger for @MainActor-isolated methods of PitchDetectionViewModel.
private let vmLogger = Logger.survibe(category: "PitchDetectionVM")

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

/// ViewModel for real-time pitch detection used by the Sing and Exercise lesson steps.
///
/// Pipeline (post-MIDI-2.0 migration):
/// - Melody: `MicPitchDetector` runs autocorrelation on a lock-free `SPSCRingBuffer`
///   fed by the shared `AudioEngineManager` mic tap and yields `PitchResult` values
///   over an `AsyncStream`.
/// - Chord: a secondary `SPSCRingBuffer` (registered via `MicPitchDetector.secondaryRingBuffer`)
///   accumulates raw mic samples; a Task polls it every 50 ms and runs
///   `ChromagramDSP.analyzeChord` on the latest window.
///
/// The two paths share one mic tap (iOS allows only one tap per input node).
@MainActor
@Observable
final class PitchDetectionViewModel {
    // MARK: - Dependencies

    /// Permission provider for microphone access checks and requests.
    private let permissions: any PermissionProviding

    /// Audio engine provider for engine lifecycle (mic tap is owned by `MicPitchDetector`).
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
    var recentNotes: [DetectedNote] = {
        var a = [DetectedNote]()
        a.reserveCapacity(14)
        return a
    }()
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
    private let referencePitch: Double = 440.0
    private var centsHistory: [Double] = []
    private let centsHistoryMaxSize = 22

    /// Migrated melody detector — replaces the bespoke autocorrelation pipeline
    /// + `AudioRingBuffer` previously inlined into this view model.
    private let pitchDetector = MicPitchDetector()

    /// Secondary lock-free ring buffer that captures raw mic samples for the
    /// chord pipeline (FFT chromagram). Sized to `latencyPreset.realSamples * 2`
    /// at `startListening()` so the chord task always sees a complete window.
    private var chordRingBuffer: SPSCRingBuffer?

    /// Task consuming the melody pitch stream.
    private var melodyTask: Task<Void, Never>?

    /// Task running the FFT chord detection loop (chord/both modes).
    private var chordTask: Task<Void, Never>?

    // MARK: - Public Methods

    /// Start listening for pitch via microphone.
    func startListening() async {
        guard !isListening else { return }
        errorMessage = nil
        debugStatus = "Requesting mic permission..."
        vmLogger.info("startListening called")

        guard await requestMicPermission() else { return }

        // Connect visualization adapter to mainMixerNode (coexists with mic tap on inputNode)
        do {
            try AudioNodeAdapter.shared.connect()
        } catch {
            vmLogger.error("AudioNodeAdapter connection failed: \(error.localizedDescription, privacy: .public)")
        }

        let mode = detectionMode
        let preset = latencyPreset

        // Allocate the chord ring buffer up front when the chord pipeline is active.
        // Capacity = realSamples * 2 so reads never overlap with writes.
        if mode == .chord || mode == .both {
            let buf = SPSCRingBuffer(capacity: preset.realSamples * 2)
            chordRingBuffer = buf
            pitchDetector.secondaryRingBuffer = buf
        } else {
            chordRingBuffer = nil
            pitchDetector.secondaryRingBuffer = nil
        }
        centsHistory = []

        debugStatus = "Installing mic tap..."
        pitchDetector.referencePitch = referencePitch
        let stream = pitchDetector.start()

        // MicPitchDetector starts the engine internally; if the tap install
        // fails it finishes the stream immediately and flips `isDetecting` to
        // false. Use that as our success signal so the UI states stay honest.
        guard pitchDetector.isDetecting else {
            chordRingBuffer = nil
            pitchDetector.secondaryRingBuffer = nil
            errorMessage = String(localized: "Could not access microphone. Please check permissions and try again.")
            debugStatus = "Mic tap failed — check logs"
            vmLogger.error("MicPitchDetector failed to start (isDetecting=false)")
            return
        }

        isListening = true
        detectionCount = 0
        debugStatus = "Listening (\(mode.displayName)) — play a note"
        vmLogger.info("MicPitchDetector started, mode=\(mode.rawValue, privacy: .public)")

        melodyTask = Task { [weak self] in
            await self?.runMelodyLoop(stream: stream, mode: mode)
        }

        if mode == .chord || mode == .both, let chordBuf = chordRingBuffer {
            chordTask = Task { [weak self] in
                await self?.runChordLoop(buffer: chordBuf, realSamples: preset.realSamples)
            }
        }
    }

    /// Stop listening and tear down audio.
    func stopListening() {
        melodyTask?.cancel()
        melodyTask = nil
        chordTask?.cancel()
        chordTask = nil
        pitchDetector.stop()
        pitchDetector.secondaryRingBuffer = nil
        AudioNodeAdapter.shared.disconnect()
        audioEngine.stop()
        isListening = false

        // Reset chord detection state
        chordRingBuffer = nil
        currentChordResult = nil
        currentExpression = nil
        centsHistory = []

        debugStatus = "Stopped"
        vmLogger.info("stopListening complete")
    }

    /// URL to iOS Settings for mic permission (opened by the View via @Environment(\.openURL)).
    var settingsURL: URL? {
        permissions.settingsURL
    }
}

// MARK: - Listening Setup Helpers

extension PitchDetectionViewModel {
    /// Request microphone permission. Returns `true` if granted.
    fileprivate func requestMicPermission() async -> Bool {
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
}

// MARK: - Detection Loops

extension PitchDetectionViewModel {
    /// Consume the `MicPitchDetector` async stream and apply melody results.
    fileprivate func runMelodyLoop(
        stream: AsyncStream<PitchResult>,
        mode: DetectionMode
    ) async {
        for await result in stream {
            guard !Task.isCancelled, isListening else { return }
            let amplitude = result.amplitude
            // `MicPitchDetector` yields a silence-marker result (frequency == 0)
            // even when no note is detected so the UI keeps its liveness.
            let isSilence = result.frequency <= 0 || result.noteName.isEmpty
            applyMelodyResult(
                amplitude: amplitude,
                pitch: isSilence ? nil : result,
                mode: mode
            )
        }
    }

    /// Poll the chord ring buffer every 50 ms and run FFT chromagram analysis.
    fileprivate func runChordLoop(buffer: SPSCRingBuffer, realSamples: Int) async {
        // Pre-allocate a single read buffer reused on every iteration —
        // matches the zero-alloc contract used by `MicPitchDetector`.
        let workBuf = UnsafeMutableBufferPointer<Float>.allocate(capacity: realSamples)
        workBuf.initialize(repeating: 0)
        defer { workBuf.deallocate() }

        let refPitch = referencePitch
        // Sample rate may differ from 44100 on Bluetooth/external interfaces, but
        // the shared engine manager runs at the input node's preferred rate.
        // Use 44100 as a stable reference here — chord detection is robust to
        // small sample-rate offsets at the FFT bin granularity used.
        let sampleRate: Double = 44100
        while !Task.isCancelled, isListening {
            try? await Task.sleep(for: .milliseconds(50))
            guard buffer.readLatest(count: realSamples, into: workBuf) else { continue }
            // Copy into [Float] for the existing chord API. This allocation is
            // intentional — it runs on the DSP task, not the audio thread.
            guard let base = workBuf.baseAddress else { continue }
            let samples = Array(UnsafeBufferPointer(start: base, count: realSamples))
            let chord = ChromagramDSP.analyzeChord(
                samples: samples,
                sampleRate: sampleRate,
                referencePitch: refPitch
            )
            applyChordResult(chord)
        }
    }

    /// Apply a melody pitch result on the MainActor.
    fileprivate func applyMelodyResult(
        amplitude: Double,
        pitch: PitchResult?,
        mode: DetectionMode
    ) {
        liveAmplitude = amplitude
        if let pr = pitch {
            detectionCount += 1
            currentResult = pr
            let western = SwarUtility.westernName(for: pr.noteName)
            westernNoteName = western
            if detectionCount % 5 == 0 {
                debugStatus = "Detected: \(western)\(pr.octave) (\(Int(pr.frequency))Hz)"
            }
            appendNote(pr)
            updateExpression(cents: pr.centsOffset)
        } else if amplitude > 0.002, mode != .chord {
            debugStatus = "Sound (amp: \(String(format: "%.3f", amplitude))) — no pitch"
        }
    }

    /// Apply an FFT chord result on the MainActor.
    fileprivate func applyChordResult(_ chord: ChordResult) {
        guard !chord.detectedPitches.isEmpty else { return }
        currentChordResult = chord
        if let name = chord.chordName {
            debugStatus = "Chord: \(name.displayName)"
        }
    }

    /// Maintain the rolling cents history and recompute pitch expression.
    fileprivate func updateExpression(cents: Double) {
        centsHistory.append(cents)
        // AUD-018: removeFirst() is O(1) amortized vs O(n) Array(suffix()) copy.
        if centsHistory.count > centsHistoryMaxSize {
            centsHistory.removeFirst()
        }
        if centsHistory.count >= 10 {
            currentExpression = PitchExpressionAnalyzer.analyze(
                centsHistory: centsHistory,
                hopIntervalSeconds: 1024.0 / 44100.0
            )
        }
    }

    /// Append a detected note to the rolling history, deduplicating consecutive identical notes.
    fileprivate func appendNote(_ result: PitchResult) {
        let western = SwarUtility.westernName(for: result.noteName)
        let note = DetectedNote(
            swarName: result.noteName,
            westernName: western,
            octave: result.octave,
            centsOffset: result.centsOffset,
            frequency: result.frequency,
            timestamp: result.timestamp
        )
        if let last = recentNotes.last,
            last.swarName == note.swarName && last.octave == note.octave
        {
            recentNotes[recentNotes.count - 1] = note
            return
        }
        recentNotes.append(note)
        if recentNotes.count > maxRecentNotes {
            recentNotes = Array(recentNotes.suffix(maxRecentNotes))
        }
    }
}
