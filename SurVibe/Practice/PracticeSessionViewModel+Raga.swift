import Foundation
import SVAudio
import SVCore
import SVLearning
import os.log

// MARK: - Raga Context Methods

extension PracticeSessionViewModel {
    /// Enrich a pitch result with raga-aware mapping when available.
    ///
    /// When a `RagaAwareMapper` is configured, re-maps the detected frequency
    /// to get JI cents offset and in-raga status. Falls through to the
    /// original pitch result when no mapper is available.
    ///
    /// - Parameter pitch: The raw pitch result from the audio processor.
    /// - Returns: Enriched pitch result with `isInRaga` and `ragaCentsOffset`.
    func enrichPitchWithRagaContext(_ pitch: PitchResult) -> PitchResult {
        guard let mapper = ragaMapper else { return pitch }
        do {
            // referencePitch is A4 (440 Hz), matching the audio processor's convention
            let mapping = try mapper.mapFrequency(pitch.frequency, referencePitch: 440.0)
            return PitchResult(
                frequency: pitch.frequency,
                amplitude: pitch.amplitude,
                noteName: mapping.noteName,
                octave: mapping.octave,
                centsOffset: pitch.centsOffset,
                confidence: pitch.confidence,
                isInRaga: mapping.isInRaga,
                ragaCentsOffset: mapping.ragaCentsOffset
            )
        } catch {
            return pitch
        }
    }

    /// Configure raga-aware scoring context from the song's raga name.
    ///
    /// When a valid raga name is provided, creates a `RagaScoringContext` for
    /// score penalties and a `RagaAwareMapper` for JI note snapping.
    /// When raga name is empty or unknown, clears both to fall back to 12ET.
    ///
    /// - Parameter ragaName: The raga name from the song, or empty string.
    func configureRagaContext(ragaName: String) {
        guard !ragaName.isEmpty else {
            ragaScoringContext = nil
            ragaMapper = nil
            return
        }

        ragaScoringContext = RagaScoringContext.from(ragaName: ragaName)
        if let ragaContext = RagaTuningProvider.context(for: ragaName) {
            ragaMapper = RagaAwareMapper(ragaContext: ragaContext)
            Self.logger.info(
                "Raga context configured: \(ragaName, privacy: .public) (\(ragaContext.scaleDegrees.count) degrees)"
            )
        } else {
            ragaMapper = nil
            Self.logger.info(
                "Unknown raga '\(ragaName, privacy: .public)' -- using equal temperament"
            )
        }
    }
}
