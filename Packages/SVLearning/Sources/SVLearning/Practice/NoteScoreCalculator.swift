import Foundation

/// Calculates individual note scores during practice mode.
///
/// Uses a weighted scoring formula: 50% pitch accuracy + 30% timing accuracy
/// + 20% duration accuracy. Each component is computed from the deviation
/// between the player's input and the expected note values, mapped to a
/// 0.0–1.0 accuracy range using the thresholds in `PracticeConstants`.
public enum NoteScoreCalculator {
    /// Calculate the score for a single note attempt.
    ///
    /// Takes raw deviation measurements and produces a `NoteScore` with
    /// composite accuracy and grade. All deviations are absolute values.
    ///
    /// When a `ragaContext` is provided:
    /// - `ragaPitchDeviationCents` is used for pitch accuracy instead of `pitchDeviationCents`
    /// - Out-of-raga notes have their pitch accuracy capped at 0.3
    ///
    /// - Parameters:
    ///   - expectedNote: The target swar note name (e.g., "Sa", "Re").
    ///   - detectedNote: The note name detected by pitch detection, if any.
    ///   - pitchDeviationCents: Absolute cents deviation from the target pitch (12ET).
    ///   - timingDeviationSeconds: Absolute timing deviation from expected onset.
    ///   - durationDeviation: Duration deviation as fraction of expected duration.
    ///   - ragaPitchDeviationCents: Cents deviation from the JI target. Used when raga context is present.
    ///   - ragaContext: Optional raga scoring context for raga-aware scoring.
    ///   - playedVelocity: MIDI velocity (0–127) of the played note. `nil` for mic input.
    ///   - expectedVelocity: Expected velocity from notation. `nil` if not specified.
    /// - Returns: A `NoteScore` with computed accuracy and grade.
    public static func score(
        expectedNote: String,
        detectedNote: String?,
        pitchDeviationCents: Double,
        timingDeviationSeconds: Double,
        durationDeviation: Double,
        ragaPitchDeviationCents: Double? = nil,
        ragaContext: RagaScoringContext? = nil,
        playedVelocity: UInt8? = nil,
        expectedVelocity: UInt8? = nil
    ) -> NoteScore {
        // Use JI cents when raga context is available, otherwise 12ET cents
        let effectivePitchCents = ragaPitchDeviationCents ?? pitchDeviationCents
        var pitchAccuracy = pitchAccuracyScore(cents: abs(effectivePitchCents))

        // Determine out-of-raga status and apply penalty
        var isOutOfRaga: Bool?
        if let ragaContext, let detectedNote {
            let noteOutOfRaga = !ragaContext.isNoteInRaga(detectedNote)
            isOutOfRaga = noteOutOfRaga
            if noteOutOfRaga {
                pitchAccuracy = min(pitchAccuracy, outOfRagaPitchAccuracyCap)
            }
        }

        let timingAccuracy = timingAccuracyScore(seconds: abs(timingDeviationSeconds))
        let durationAccuracy = durationAccuracyScore(fraction: abs(durationDeviation))

        // When both played and expected velocity are available, add dynamics scoring.
        // Weights shift to: 45% pitch + 25% timing + 15% duration + 15% dynamics.
        // Otherwise, use standard weights: 50% pitch + 30% timing + 20% duration.
        let composite: Double
        if let played = playedVelocity, let expected = expectedVelocity, expected > 0 {
            let dynamicsAccuracy = dynamicsAccuracyScore(played: played, expected: expected)
            composite = pitchAccuracy * 0.45
                + timingAccuracy * 0.25
                + durationAccuracy * 0.15
                + dynamicsAccuracy * 0.15
        } else {
            composite = pitchAccuracy * PracticeConstants.pitchWeight
                + timingAccuracy * PracticeConstants.timingWeight
                + durationAccuracy * PracticeConstants.durationWeight
        }

        let grade = NoteGrade.from(accuracy: composite)

        return NoteScore(
            grade: grade,
            accuracy: composite,
            pitchDeviationCents: pitchDeviationCents,
            timingDeviationSeconds: timingDeviationSeconds,
            durationDeviation: durationDeviation,
            expectedNote: expectedNote,
            detectedNote: detectedNote,
            isOutOfRaga: isOutOfRaga
        )
    }

    /// Maximum pitch accuracy for a note that is outside the active raga.
    /// Set to 0.3 so out-of-raga notes never score higher than "poor".
    private static let outOfRagaPitchAccuracyCap = 0.3

    /// Calculate a score when no pitch was detected (silence or below threshold).
    ///
    /// Returns a miss with zero accuracy.
    ///
    /// - Parameter expectedNote: The target swar note name.
    /// - Returns: A `NoteScore` graded as a miss.
    public static func missedNote(expectedNote: String) -> NoteScore {
        NoteScore(
            grade: .miss,
            accuracy: 0.0,
            pitchDeviationCents: 0.0,
            timingDeviationSeconds: 0.0,
            durationDeviation: 0.0,
            expectedNote: expectedNote,
            detectedNote: nil
        )
    }

    // MARK: - Private Methods

    /// Convert cents deviation to a 0.0–1.0 pitch accuracy score.
    ///
    /// Uses linear interpolation between the tolerance thresholds defined
    /// in `PracticeConstants`. Values at or below `perfectPitchCents` score 1.0,
    /// values at or above `fairPitchCents` score 0.0.
    private static func pitchAccuracyScore(cents: Double) -> Double {
        if cents <= PracticeConstants.perfectPitchCents {
            return 1.0
        } else if cents <= PracticeConstants.goodPitchCents {
            return linearInterpolate(
                value: cents,
                low: PracticeConstants.perfectPitchCents,
                high: PracticeConstants.goodPitchCents,
                outputLow: 0.9,
                outputHigh: 0.7
            )
        } else if cents <= PracticeConstants.fairPitchCents {
            return linearInterpolate(
                value: cents,
                low: PracticeConstants.goodPitchCents,
                high: PracticeConstants.fairPitchCents,
                outputLow: 0.7,
                outputHigh: 0.5
            )
        }
        return max(0.0, 0.5 - (cents - PracticeConstants.fairPitchCents) / 100.0)
    }

    /// Convert timing deviation (seconds) to a 0.0–1.0 timing accuracy score.
    private static func timingAccuracyScore(seconds: Double) -> Double {
        if seconds <= PracticeConstants.perfectTimingSeconds {
            return 1.0
        } else if seconds <= PracticeConstants.goodTimingSeconds {
            return linearInterpolate(
                value: seconds,
                low: PracticeConstants.perfectTimingSeconds,
                high: PracticeConstants.goodTimingSeconds,
                outputLow: 0.9,
                outputHigh: 0.7
            )
        } else if seconds <= PracticeConstants.fairTimingSeconds {
            return linearInterpolate(
                value: seconds,
                low: PracticeConstants.goodTimingSeconds,
                high: PracticeConstants.fairTimingSeconds,
                outputLow: 0.7,
                outputHigh: 0.5
            )
        }
        return max(0.0, 0.5 - (seconds - PracticeConstants.fairTimingSeconds) / 1.0)
    }

    /// Convert duration deviation fraction to a 0.0–1.0 duration accuracy score.
    private static func durationAccuracyScore(fraction: Double) -> Double {
        if fraction <= PracticeConstants.perfectDurationFraction {
            return 1.0
        } else if fraction <= PracticeConstants.goodDurationFraction {
            return linearInterpolate(
                value: fraction,
                low: PracticeConstants.perfectDurationFraction,
                high: PracticeConstants.goodDurationFraction,
                outputLow: 0.9,
                outputHigh: 0.7
            )
        } else if fraction <= PracticeConstants.fairDurationFraction {
            return linearInterpolate(
                value: fraction,
                low: PracticeConstants.goodDurationFraction,
                high: PracticeConstants.fairDurationFraction,
                outputLow: 0.7,
                outputHigh: 0.5
            )
        }
        return max(0.0, 0.5 - (fraction - PracticeConstants.fairDurationFraction) / 1.0)
    }

    /// Linear interpolation between two ranges.
    private static func linearInterpolate(
        value: Double,
        low: Double,
        high: Double,
        outputLow: Double,
        outputHigh: Double
    ) -> Double {
        let ratio = (value - low) / (high - low)
        return outputLow + ratio * (outputHigh - outputLow)
    }

    /// Convert velocity difference to a 0.0–1.0 dynamics accuracy score.
    ///
    /// Tolerances: within ±20 velocity units = perfect (1.0),
    /// ±40 = good (0.7), ±60 = fair (0.5). Beyond ±60 scales to 0.
    ///
    /// - Parameters:
    ///   - played: Actual MIDI velocity (0–127).
    ///   - expected: Expected MIDI velocity (1–127).
    /// - Returns: Dynamics accuracy between 0.0 and 1.0.
    private static func dynamicsAccuracyScore(played: UInt8, expected: UInt8) -> Double {
        let delta = abs(Double(played) - Double(expected))
        if delta <= 20 { return 1.0 }
        if delta <= 40 { return linearInterpolate(value: delta, low: 20, high: 40, outputLow: 1.0, outputHigh: 0.7) }
        if delta <= 60 { return linearInterpolate(value: delta, low: 40, high: 60, outputLow: 0.7, outputHigh: 0.5) }
        return max(0.0, 0.5 - (delta - 60) / 67.0)
    }
}
