import Accelerate
import Foundation

// MARK: - Expression Type

/// Classification of pitch expression detected over a time window.
///
/// Used to identify ornamental techniques in Indian classical music
/// by analyzing the rolling history of cents-offset values.
public enum ExpressionType: String, Sendable {
    /// Note is stable within ±5 cents.
    case stable

    /// Periodic oscillation at 4–8 Hz, amplitude 10–50 cents.
    /// Common in Western and Indian vocal/instrumental performance.
    case vibrato

    /// Monotonic pitch drift crossing note boundaries.
    /// Indian classical technique of gliding between notes.
    case meend

    /// Wider oscillation (50–100 cents) at 1–3 Hz.
    /// Characteristic ornamental oscillation in Indian classical music.
    case gamaka

    /// No clear expression pattern detected.
    case indeterminate

    /// Localized display name for UI.
    public var displayName: String {
        switch self {
        case .stable: String(localized: "Stable", bundle: .module)
        case .vibrato: String(localized: "Vibrato", bundle: .module)
        case .meend: String(localized: "Meend", bundle: .module)
        case .gamaka: String(localized: "Gamaka", bundle: .module)
        case .indeterminate: String(localized: "Indeterminate", bundle: .module)
        }
    }
}

// MARK: - Expression Result

/// Result of pitch expression analysis over a rolling window.
///
/// Produced by `PitchExpressionAnalyzer.analyze` from a window of
/// cents-offset values (~500ms = ~22 samples at 23ms hop interval).
public struct ExpressionResult: Sendable, Equatable {
    /// Detected expression type.
    public let type: ExpressionType

    /// Standard deviation of cents offsets in the window.
    public let centsStdDev: Double

    /// Peak oscillation frequency in Hz (for vibrato/gamaka). 0 if not oscillatory.
    public let oscillationFrequencyHz: Double

    /// Peak-to-peak amplitude in cents (for vibrato/gamaka). 0 if not oscillatory.
    public let oscillationAmplitudeCents: Double

    /// Total drift in cents from first to last sample (for meend detection).
    public let totalDriftCents: Double

    public init(
        type: ExpressionType,
        centsStdDev: Double,
        oscillationFrequencyHz: Double = 0,
        oscillationAmplitudeCents: Double = 0,
        totalDriftCents: Double = 0
    ) {
        self.type = type
        self.centsStdDev = centsStdDev
        self.oscillationFrequencyHz = oscillationFrequencyHz
        self.oscillationAmplitudeCents = oscillationAmplitudeCents
        self.totalDriftCents = totalDriftCents
    }
}

// MARK: - Pitch Expression Analyzer

/// Analyzes rolling cents-offset history to detect pitch expression techniques.
///
/// All methods are `nonisolated static` — safe to call from any thread.
/// Uses Accelerate/vDSP for standard deviation and FFT-based oscillation detection.
///
/// Detection thresholds are tuned for piano and vocal Indian classical music:
/// - Stable: std dev < 5 cents (rock-solid intonation)
/// - Meend: monotonic drift > 80 cents (deliberate glide)
/// - Vibrato: 4–8 Hz oscillation, 10–50 cent amplitude
/// - Gamaka: 1–3 Hz oscillation, 50–100 cent amplitude
public enum PitchExpressionAnalyzer {
    // MARK: - Constants

    /// Minimum number of samples needed for meaningful analysis.
    private static let minimumSamples = 10

    /// Maximum standard deviation (cents) to classify as stable.
    private static let stableThreshold: Double = 5.0

    /// Minimum total drift (cents) to classify as meend.
    private static let meendDriftThreshold: Double = 80.0

    /// Minimum R² value for linear regression to classify drift as monotonic.
    private static let meendLinearityThreshold: Double = 0.7

    // MARK: - Main Analysis

    /// Analyze a rolling window of cents-offset values to detect expression.
    ///
    /// Examines the pattern of pitch variation over ~500ms to classify
    /// the performer's technique: stable pitch, vibrato, meend (glide),
    /// or gamaka (ornamental oscillation).
    ///
    /// - Parameters:
    ///   - centsHistory: Rolling window of cents-offset values (typically ~22 samples).
    ///   - hopIntervalSeconds: Time between consecutive samples (typically 0.023s).
    /// - Returns: Expression classification with supporting measurements.
    nonisolated public static func analyze(
        centsHistory: [Double],
        hopIntervalSeconds: Double
    ) -> ExpressionResult {
        guard centsHistory.count >= minimumSamples else {
            // centsStdDev: 0 with .indeterminate means insufficient data for analysis,
            // NOT that the pitch is perfectly stable. Callers should check the type first.
            return ExpressionResult(type: .indeterminate, centsStdDev: 0)
        }

        // Compute standard deviation
        let stdDev = computeStdDev(centsHistory)

        // Check for stable note
        if stdDev < stableThreshold {
            return ExpressionResult(type: .stable, centsStdDev: stdDev)
        }

        // Check for meend (monotonic drift)
        let (isMonotonic, totalDrift) = checkMonotonicDrift(centsHistory)
        if isMonotonic && abs(totalDrift) > meendDriftThreshold {
            return ExpressionResult(
                type: .meend,
                centsStdDev: stdDev,
                totalDriftCents: totalDrift
            )
        }

        // Check for oscillatory patterns (vibrato or gamaka)
        let (oscFreq, oscAmplitude) = computeOscillation(
            centsHistory: centsHistory,
            hopIntervalSeconds: hopIntervalSeconds
        )

        // Gamaka: slower (1-3 Hz), wider (50-100 cents)
        if oscFreq >= 1.0 && oscFreq <= 3.5 && oscAmplitude >= 40.0 && oscAmplitude <= 120.0 {
            return ExpressionResult(
                type: .gamaka,
                centsStdDev: stdDev,
                oscillationFrequencyHz: oscFreq,
                oscillationAmplitudeCents: oscAmplitude
            )
        }

        // Vibrato: faster (4-8 Hz), narrower (10-50 cents)
        if oscFreq >= 3.5 && oscFreq <= 9.0 && oscAmplitude >= 8.0 && oscAmplitude <= 60.0 {
            return ExpressionResult(
                type: .vibrato,
                centsStdDev: stdDev,
                oscillationFrequencyHz: oscFreq,
                oscillationAmplitudeCents: oscAmplitude
            )
        }

        return ExpressionResult(
            type: .indeterminate,
            centsStdDev: stdDev,
            oscillationFrequencyHz: oscFreq,
            oscillationAmplitudeCents: oscAmplitude,
            totalDriftCents: totalDrift
        )
    }

    // MARK: - Standard Deviation

    /// Compute standard deviation of a Double array using Accelerate.
    ///
    /// - Parameter values: Input values.
    /// - Returns: Standard deviation.
    nonisolated private static func computeStdDev(_ values: [Double]) -> Double {
        let count = values.count
        guard count > 1 else { return 0 }

        var mean: Double = 0
        vDSP_meanvD(values, 1, &mean, vDSP_Length(count))

        var deviations = [Double](repeating: 0, count: count)
        var negMean = -mean
        vDSP_vsaddD(values, 1, &negMean, &deviations, 1, vDSP_Length(count))

        var squaredDevs = [Double](repeating: 0, count: count)
        vDSP_vsqD(deviations, 1, &squaredDevs, 1, vDSP_Length(count))

        var sumSquared: Double = 0
        vDSP_sveD(squaredDevs, 1, &sumSquared, vDSP_Length(count))

        return sqrt(sumSquared / Double(count - 1))
    }

    // MARK: - Monotonic Drift Detection

    /// Check if the cents history shows a consistent linear drift.
    ///
    /// Uses simple linear regression to compute R² (coefficient of determination).
    /// If R² exceeds the threshold, the drift is considered monotonic (meend).
    ///
    /// - Parameter values: Cents-offset history.
    /// - Returns: Tuple of (isMonotonic, totalDrift in cents).
    nonisolated private static func checkMonotonicDrift(
        _ values: [Double]
    ) -> (Bool, Double) {
        let count = values.count
        guard count >= 2 else { return (false, 0) }

        let totalDrift = values[count - 1] - values[0]

        // Simple linear regression: y = mx + b
        // Compute R² to check how linear the drift is
        let xValues = (0..<count).map { Double($0) }

        var xMean: Double = 0
        vDSP_meanvD(xValues, 1, &xMean, vDSP_Length(count))
        var yMean: Double = 0
        vDSP_meanvD(values, 1, &yMean, vDSP_Length(count))

        var ssXY: Double = 0
        var ssXX: Double = 0
        var ssYY: Double = 0

        for index in 0..<count {
            let dx = xValues[index] - xMean
            let dy = values[index] - yMean
            ssXY += dx * dy
            ssXX += dx * dx
            ssYY += dy * dy
        }

        guard ssXX > 0, ssYY > 0 else { return (false, totalDrift) }

        let rSquared = (ssXY * ssXY) / (ssXX * ssYY)
        let isMonotonic = rSquared >= meendLinearityThreshold

        return (isMonotonic, totalDrift)
    }

    // MARK: - Oscillation Detection

    /// Detect the dominant oscillation frequency and amplitude in cents history.
    ///
    /// Removes the DC component (mean), then performs a DFT on the cents-offset
    /// history to find the dominant periodic component. Returns the frequency
    /// and peak-to-peak amplitude of the strongest oscillation.
    ///
    /// - Parameters:
    ///   - centsHistory: Rolling cents-offset values.
    ///   - hopIntervalSeconds: Time between samples (determines Nyquist frequency).
    /// - Returns: Tuple of (oscillation frequency in Hz, peak-to-peak amplitude in cents).
    nonisolated private static func computeOscillation(
        centsHistory: [Double],
        hopIntervalSeconds: Double
    ) -> (Double, Double) {
        let count = centsHistory.count
        guard count >= minimumSamples, hopIntervalSeconds > 0 else { return (0, 0) }

        // Remove DC (mean) to focus on oscillatory component
        var mean: Double = 0
        vDSP_meanvD(centsHistory, 1, &mean, vDSP_Length(count))
        var centered = [Double](repeating: 0, count: count)
        var negMean = -mean
        vDSP_vsaddD(centsHistory, 1, &negMean, &centered, 1, vDSP_Length(count))

        // Compute DFT magnitudes manually (small N, no need for vDSP FFT)
        let sampleRate = 1.0 / hopIntervalSeconds
        let nyquist = sampleRate / 2.0
        let freqResolution = sampleRate / Double(count)

        var bestFreq: Double = 0
        var bestMagnitude: Double = 0

        // Search frequency range 0.5 Hz to nyquist.
        //
        // When hop interval is long relative to window length (e.g. user paused
        // between pitch-bend events), `minBin` can exceed `maxBin`, which would
        // form an invalid `Range` and trap. Bail out with a zero result instead
        // — the caller treats low magnitude as "no clear oscillation".
        let minBin = max(1, Int(ceil(0.5 / freqResolution)))
        let maxBin = count / 2
        guard minBin < maxBin else { return (0, 0) }

        for bin in minBin..<maxBin {
            let frequency = Double(bin) * freqResolution
            guard frequency <= nyquist else { break }

            // DFT at this bin
            var realPart: Double = 0
            var imagPart: Double = 0
            for index in 0..<count {
                let angle = 2.0 * .pi * Double(bin) * Double(index) / Double(count)
                realPart += centered[index] * cos(angle)
                imagPart += centered[index] * sin(angle)
            }
            let magnitude = sqrt(realPart * realPart + imagPart * imagPart) / Double(count)

            if magnitude > bestMagnitude {
                bestMagnitude = magnitude
                bestFreq = frequency
            }
        }

        // Convert magnitude to peak-to-peak amplitude (magnitude × 2 for sinusoidal)
        let peakToPeak = bestMagnitude * 2.0

        return (bestFreq, peakToPeak)
    }
}
