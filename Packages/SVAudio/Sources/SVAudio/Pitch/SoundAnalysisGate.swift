import AVFoundation
import Foundation
import SoundAnalysis
import Synchronization
import os

private let soundLogger = Logger.survibe(category: "SoundAnalysisGate")

/// Observer for `SNClassifySoundRequest.version1` classification results.
///
/// Caches the latest `piano` and `singing` confidences atomically so the
/// `SoundAnalysisGate.shouldAccept` check (called on the DSP task) and
/// the classification callback (called by SoundAnalysis) can run on
/// different threads without contention.
final class SoundAnalysisGateObserver: NSObject, SNResultsObserving, Sendable {
    let pianoConfidence = AtomicDoubleBox(initial: 1.0)
    let singingConfidence = AtomicDoubleBox(initial: 0.0)

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        if let piano = classificationResult.classification(forIdentifier: "piano") {
            pianoConfidence.store(piano.confidence)
        }
        if let singing = classificationResult.classification(forIdentifier: "singing") {
            singingConfidence.store(singing.confidence)
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        soundLogger.error(
            "SoundAnalysis failed: \(error.localizedDescription, privacy: .public)"
        )
    }

    func requestDidComplete(_ request: SNRequest) {}
}

/// Layer 3 voice-rejection gate using Apple's built-in sound classifier
/// (`SNClassifySoundRequest.version1`).
///
/// The classifier runs on a rolling ~975 ms window of audio from the mic
/// tap. When it reports that the dominant sound is `singing` (confidence
/// > 0.7) with weak `piano` evidence (< 0.3), mic pitch detections are
/// suppressed — filtering out humming and singing that the DSP-only
/// gates might still pass.
///
/// The gate falls back to no-op if the classifier on the target iOS
/// version does not know about `piano` and `singing` identifiers, so the
/// feature degrades gracefully.
public final class SoundAnalysisGate: RobustPitchGate, @unchecked Sendable {
    private let observer: SoundAnalysisGateObserver
    private let analyzer: SNAudioStreamAnalyzer?
    private let isEnabled: Bool

    public init() {
        self.observer = SoundAnalysisGateObserver()
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            let hasPiano = request.knownClassifications.contains("piano")
            let hasSinging = request.knownClassifications.contains("singing")
            guard hasPiano, hasSinging else {
                soundLogger.warning(
                    "SNClassifier.version1 missing piano/singing — gate disabled"
                )
                self.analyzer = nil
                self.isEnabled = false
                return
            }

            // Audio format matches the mic tap output (44.1 kHz float32 mono).
            // If iOS negotiates a different rate at runtime, the analyzer's
            // internal resampler handles it.
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 44100,
                channels: 1,
                interleaved: false
            ) else {
                soundLogger.error("Unable to construct AVAudioFormat — gate disabled")
                self.analyzer = nil
                self.isEnabled = false
                return
            }
            let analyzer = SNAudioStreamAnalyzer(format: format)
            try analyzer.add(request, withObserver: observer)
            self.analyzer = analyzer
            self.isEnabled = true
            soundLogger.info("SoundAnalysisGate initialized")
        } catch {
            soundLogger.error(
                "SoundAnalysisGate init failed: \(error.localizedDescription, privacy: .public)"
            )
            self.analyzer = nil
            self.isEnabled = false
        }
    }

    /// Feed a buffer to the analyzer. Called from the mic tap.
    ///
    /// `SNAudioStreamAnalyzer.analyze(_:atAudioFramePosition:)` copies the
    /// buffer internally and defers its own processing off the audio
    /// thread, per Apple's SoundAnalysis documentation.
    public func analyze(_ buffer: AVAudioPCMBuffer, atAudioFramePosition position: AVAudioFramePosition) {
        analyzer?.analyze(buffer, atAudioFramePosition: position)
    }

    public func shouldAccept(frequency: Double, amplitude: Double, confidence: Double) -> Bool {
        guard isEnabled else { return true }
        let pianoConf = observer.pianoConfidence.load()
        let singingConf = observer.singingConfidence.load()
        // Reject only when singing is strongly dominant AND piano evidence
        // is weak. Mixed states default to accept so we don't over-filter.
        if singingConf > 0.7, pianoConf < 0.3 {
            return false
        }
        return true
    }
}
