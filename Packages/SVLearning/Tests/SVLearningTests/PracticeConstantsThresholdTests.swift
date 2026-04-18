import Testing

@testable import SVLearning

/// Regression tests asserting the consumer-side `silenceThreshold` does not
/// exceed the producer-side gate in `MicPitchDetector.processWorkBuffer`
/// (`amplitude > 0.002`).
///
/// Prior to the fix for `micissues.md` I4, the consumer threshold was 0.005
/// while the producer gated at 0.002, so valid detections with amplitudes in
/// 0.003–0.005 (typical of iPad built-in mics in `.measurement` mode) were
/// silently discarded after the DSP had already confirmed them.
struct PracticeConstantsThresholdTests {

    /// The producer-side amplitude gate in `MicPitchDetector.processWorkBuffer`.
    /// Kept as a mirror here so the assertion stays inside SVLearning and does
    /// not require a test-time dependency on SVAudio internals.
    private static let producerAmplitudeGate: Double = 0.002

    @Test
    func silenceThresholdDoesNotExceedProducerGate() {
        #expect(PracticeConstants.silenceThreshold <= Self.producerAmplitudeGate)
    }

    @Test
    func confidenceThresholdIsAtMostPointOneFive() {
        // Matches the redesign spec: single authoritative confidence threshold
        // lives in PracticeConstants and equals the producer-side target.
        #expect(PracticeConstants.confidenceThreshold <= 0.15)
    }
}
