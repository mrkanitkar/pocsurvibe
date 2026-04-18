import Foundation

/// Stateless voice-rejection gates for the mic pitch detector.
///
/// Layer 1: attack-slope gate. Piano attacks complete in ~3–5 ms; voice
/// attacks take 20–80 ms. Reject detections whose attack exceeded ~10 ms.
///
/// Layer 2: harmonic-vs-formant shape score — stubbed for V1. Activated
/// when the FFT autocorrelation upgrade (V2) lands and a magnitude
/// spectrum is available on the hot path.
public enum VoiceRejection {
    /// Piano attack upper bound (ms). Above this, reject as voice.
    public static let maxAttackMs: Double = 10.0

    /// Minimum peak-to-noise-floor ratio required to consider an onset
    /// present. Below this, the buffer is either silent or sustained.
    public static let onsetRatio: Float = 20.0

    /// Layer 1 — attack slope check. **Disabled in V1.**
    ///
    /// The previous implementation measured attack duration at DSP-frame
    /// granularity (2048 samples ≈ 42.6 ms at 48 kHz). Piano attacks
    /// complete in 3–5 ms, which is far below one frame, so the gate
    /// systematically rejected every real attack that spanned more than
    /// a single frame — producing `freq=0 amp=(loud)` for all struck
    /// notes while letting sustained quantization noise through. See
    /// field logs from iPad Air 4 (2026-04-17).
    ///
    /// Until attack measurement moves to the audio thread with sub-frame
    /// peak tracking (e.g. `vDSP_maxmgv` over each 512-sample
    /// sub-buffer), the gate always accepts. `RobustPitchGate`
    /// (SoundAnalysis) remains available for voice suppression.
    ///
    /// Parameters are retained for binary compatibility with existing
    /// callers.
    public static func attackSlopeGate(
        rmsHistory: [Float],
        sampleRate: Double,
        frameSize: Int
    ) -> Bool {
        _ = (rmsHistory, sampleRate, frameSize)
        return true
    }

    /// Layer 2 — harmonic-vs-formant shape score. Stubbed for V1.
    ///
    /// Will be implemented when FFT autocorrelation lands and a
    /// magnitude spectrum is available on the DSP hot path. Until then,
    /// returns 0 (always piano-like) so the gate is a no-op.
    public static func harmonicShapeScore(
        spectrum: [Float], f0: Double, sampleRate: Double
    ) -> Double {
        0.0
    }
}
