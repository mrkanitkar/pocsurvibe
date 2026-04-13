import Foundation

/// Result from pitch detection containing frequency, note, and accuracy info.
public struct PitchResult: Sendable, Equatable {
    /// Detected frequency in Hz.
    public let frequency: Double

    /// Signal amplitude (0.0 to 1.0).
    public let amplitude: Double

    /// Detected note name (e.g., "Sa", "Re", "Ga").
    public let noteName: String

    /// Octave number of the detected note.
    public let octave: Int

    /// Cents offset from the nearest note (-50 to +50).
    public let centsOffset: Double

    /// Timestamp of the detection.
    public let timestamp: Date

    /// Confidence level of the detection (0.0 to 1.0).
    public let confidence: Double

    /// Whether the detected note belongs to the active raga's scale.
    /// `nil` when no raga context is active (equal temperament mode).
    public let isInRaga: Bool?

    /// Cents deviation from the just-intonation target for this raga scale degree.
    /// `nil` when no raga context is active.
    public let ragaCentsOffset: Double?

    /// Latency probe token carrying pipeline timestamps for end-to-end measurement.
    ///
    /// Stamped at audio tap entry (t0) and DSP completion (t1).
    /// `nil` when profiling is not active.
    public var probeToken: ProbeToken?

    public init(
        frequency: Double,
        amplitude: Double,
        noteName: String,
        octave: Int,
        centsOffset: Double,
        timestamp: Date = Date(),
        confidence: Double,
        isInRaga: Bool? = nil,
        ragaCentsOffset: Double? = nil,
        probeToken: ProbeToken? = nil
    ) {
        self.frequency = frequency
        self.amplitude = amplitude
        self.noteName = noteName
        self.octave = octave
        self.centsOffset = centsOffset
        self.timestamp = timestamp
        self.confidence = confidence
        self.isInRaga = isInRaga
        self.ragaCentsOffset = ragaCentsOffset
        self.probeToken = probeToken
    }
}
