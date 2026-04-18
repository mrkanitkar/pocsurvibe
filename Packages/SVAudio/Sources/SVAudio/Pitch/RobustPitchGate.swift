import Foundation

/// A gate that decides whether a detected pitch should be propagated.
///
/// Wired into `MicPitchDetector`'s DSP loop as the final filter after
/// autocorrelation + cents refinement. Implementations:
///
/// - `DefaultRobustPitchGate`: no-op (accepts all). Default when
///   "Robust pitch detection" is off.
/// - `SoundAnalysisGate`: uses Apple's `SNClassifySoundRequest.version1`
///   to suppress results during sung passages (Layer 3 — opt-in).
///
/// Future implementations may include CoreML-based pitch models behind
/// the same interface.
public protocol RobustPitchGate: Sendable {
    /// Returns true if the detection should be propagated to consumers.
    /// Called from the DSP task on every successful detection.
    func shouldAccept(frequency: Double, amplitude: Double, confidence: Double) -> Bool
}

/// No-op gate — the default when Robust mode is disabled.
public struct DefaultRobustPitchGate: RobustPitchGate {
    public init() {}
    public func shouldAccept(frequency: Double, amplitude: Double, confidence: Double) -> Bool {
        true
    }
}
