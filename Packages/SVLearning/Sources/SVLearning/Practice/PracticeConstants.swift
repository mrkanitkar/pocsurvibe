import Foundation

/// Namespace for practice mode constants and thresholds.
///
/// Centralizes all tuning parameters for pitch detection sensitivity,
/// timing tolerance, scoring weights, and XP calculations. All values
/// are compile-time constants to avoid scattered magic numbers.
public enum PracticeConstants {
    // MARK: - Silence Detection

    /// Minimum amplitude threshold below which a pitch result is ignored.
    ///
    /// Set to 0.005 to capture acoustic piano and other instruments played
    /// 0.5–2m from the device microphone. The pre-filter in PracticeAudioProcessor
    /// uses the same threshold so only non-trivially-loud buffers are processed.
    public static let silenceThreshold: Double = 0.005

    /// Minimum confidence threshold for a pitch detection result to be scored.
    ///
    /// Set to 0.15 to accommodate piano's complex harmonic structure where
    /// the fundamental autocorrelation peak is often weaker than harmonic peaks.
    /// At 0.3 the threshold was too strict for fast-attack piano notes whose
    /// fundamental peak decays before a full 2048-frame window completes.
    public static let confidenceThreshold: Double = 0.15

    // MARK: - Pitch Tolerance

    /// Maximum cents deviation for a perfect pitch match.
    public static let perfectPitchCents: Double = 10.0

    /// Maximum cents deviation for a good pitch match.
    public static let goodPitchCents: Double = 25.0

    /// Maximum cents deviation for a fair pitch match.
    public static let fairPitchCents: Double = 50.0

    // MARK: - Timing Tolerance

    /// Maximum timing deviation (seconds) for a perfect timing match.
    public static let perfectTimingSeconds: Double = 0.1

    /// Maximum timing deviation (seconds) for a good timing match.
    public static let goodTimingSeconds: Double = 0.25

    /// Maximum timing deviation (seconds) for a fair timing match.
    public static let fairTimingSeconds: Double = 0.5

    // MARK: - Duration Tolerance

    /// Maximum duration deviation fraction for a perfect duration match.
    public static let perfectDurationFraction: Double = 0.15

    /// Maximum duration deviation fraction for a good duration match.
    public static let goodDurationFraction: Double = 0.30

    /// Maximum duration deviation fraction for a fair duration match.
    public static let fairDurationFraction: Double = 0.50

    // MARK: - Scoring Weights

    /// Weight of pitch accuracy in the composite score (50%).
    public static let pitchWeight: Double = 0.50

    /// Weight of timing accuracy in the composite score (30%).
    public static let timingWeight: Double = 0.30

    /// Weight of duration accuracy in the composite score (20%).
    public static let durationWeight: Double = 0.20

    // MARK: - XP Calculation

    /// Base XP awarded for completing a practice session.
    public static let baseXP: Int = 10

    /// Maximum XP multiplier for perfect accuracy.
    public static let maxXPMultiplier: Double = 3.0

    /// XP bonus multiplier per difficulty level (1–5).
    public static let difficultyXPMultiplier: Double = 0.25

    // MARK: - Practice Session

    /// Default listen-first phase duration multiplier (1.0 = full song).
    public static let listenPhaseMultiplier: Double = 1.0

    /// Minimum number of notes required for a valid practice session score.
    public static let minimumNotesForScore: Int = 4

    /// Maximum number of recent scores to keep for trend analysis.
    public static let maxRecentScores: Int = 20

    // MARK: - Difficulty Scaling (m7)

    /// Scale a tolerance value by difficulty level.
    ///
    /// Higher difficulty = tighter tolerances. Level 1 (beginner) uses the base
    /// tolerance. Level 5 (master) reduces it by 60%.
    ///
    /// ```
    /// Level 1: multiplier = 1.0  (full tolerance)
    /// Level 2: multiplier = 0.85
    /// Level 3: multiplier = 0.70
    /// Level 4: multiplier = 0.55
    /// Level 5: multiplier = 0.40
    /// ```
    ///
    /// - Parameters:
    ///   - baseTolerance: The default tolerance value.
    ///   - difficultyLevel: Difficulty level (1–5, clamped).
    /// - Returns: Scaled tolerance for the given difficulty.
    public static func scaledTolerance(_ baseTolerance: Double, forDifficulty difficultyLevel: Int) -> Double {
        let level = max(1, min(5, difficultyLevel))
        let multiplier = 1.0 - Double(level - 1) * 0.15
        return baseTolerance * multiplier
    }

    /// Pitch tolerance (cents) scaled by difficulty level.
    public static func perfectPitchCents(difficulty: Int) -> Double {
        scaledTolerance(perfectPitchCents, forDifficulty: difficulty)
    }

    /// Timing tolerance (seconds) scaled by difficulty level.
    public static func perfectTimingSeconds(difficulty: Int) -> Double {
        scaledTolerance(perfectTimingSeconds, forDifficulty: difficulty)
    }

    /// Duration tolerance (fraction) scaled by difficulty level.
    public static func perfectDurationFraction(difficulty: Int) -> Double {
        scaledTolerance(perfectDurationFraction, forDifficulty: difficulty)
    }
}
