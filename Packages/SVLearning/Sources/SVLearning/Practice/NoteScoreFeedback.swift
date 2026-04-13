import Foundation

/// Specific feedback classification for a single scored note.
///
/// Generated alongside each ``NoteScore`` to give the user actionable
/// per-note feedback. Each note gets exactly one primary classification
/// based on the most significant deviation from expected performance.
///
/// Stored with ``NoteScoreEntry`` for post-session drill-down review.
public enum NoteScoreFeedback: Sendable, Equatable, Codable {
    /// Note played correctly — pitch, timing, and duration all within thresholds.
    case correct

    /// Wrong pitch — expected one note, detected another.
    case wrongNote(expected: String, played: String)

    /// Played too early relative to expected onset.
    case early(deltaMs: Int)

    /// Played too late relative to expected onset.
    case late(deltaMs: Int)

    /// Held too short relative to expected duration.
    case tooShort(ratio: Double)

    /// Held too long relative to expected duration.
    case tooLong(ratio: Double)

    /// Played too softly (velocity below expected).
    case tooSoft(delta: Int)

    /// Played too loudly (velocity above expected).
    case tooLoud(delta: Int)

    // MARK: - Factory

    /// Generate feedback from a note score and its expected/played values.
    ///
    /// Classifies based on the largest deviation. Priority order:
    /// wrong note > timing > duration > dynamics.
    ///
    /// - Parameters:
    ///   - expectedNote: Expected swar name.
    ///   - detectedNote: Detected swar name (nil if unrecognized).
    ///   - timingDeviationSeconds: Onset deviation in seconds (positive = late).
    ///   - durationDeviation: Duration ratio (positive = too long, negative = too short).
    ///   - velocityDelta: Played - expected velocity (positive = too loud).
    ///   - pitchAccuracy: Pitch accuracy score (0.0–1.0).
    /// - Returns: The most relevant feedback classification.
    public static func classify(
        expectedNote: String,
        detectedNote: String?,
        timingDeviationSeconds: Double,
        durationDeviation: Double,
        velocityDelta: Int? = nil,
        pitchAccuracy: Double
    ) -> NoteScoreFeedback {
        // Wrong note is highest priority
        if pitchAccuracy < 0.5, let detected = detectedNote, detected != expectedNote {
            return .wrongNote(expected: expectedNote, played: detected)
        }

        let timingMs = Int(timingDeviationSeconds * 1000)

        // Timing issues (> 100ms)
        if abs(timingMs) > 100 {
            return timingDeviationSeconds > 0 ? .late(deltaMs: timingMs) : .early(deltaMs: abs(timingMs))
        }

        // Duration issues (> 30% off)
        if abs(durationDeviation) > 0.3 {
            return durationDeviation > 0 ? .tooLong(ratio: durationDeviation) : .tooShort(ratio: abs(durationDeviation))
        }

        // Dynamics issues
        if let delta = velocityDelta, abs(delta) > 20 {
            return delta > 0 ? .tooLoud(delta: delta) : .tooSoft(delta: abs(delta))
        }

        return .correct
    }
}
