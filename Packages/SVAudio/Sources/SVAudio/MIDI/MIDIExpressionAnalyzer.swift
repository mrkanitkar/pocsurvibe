import CoreMIDI
import Foundation
import Synchronization

/// Converts MIDI pitch bend and aftertouch events into expression classifications.
///
/// Maintains a rolling window of cents-offset values and feeds them to
/// `PitchExpressionAnalyzer.analyze()` to detect gamaka, meend, vibrato,
/// and stable pitch. Thread-safe via `Mutex<State>` for CoreMIDI thread access.
///
/// ## Usage
///
/// ```swift
/// let analyzer = MIDIExpressionAnalyzer()
/// midiInput.onPitchBendEvent = { pbEvent in
///     if let result = analyzer.process(pbEvent) {
///         // result.type == .gamaka, .meend, .vibrato, or .stable
///     }
/// }
/// ```
public final class MIDIExpressionAnalyzer: Sendable {

    // MARK: - State

    /// Mutable state protected by Mutex for CoreMIDI thread access.
    struct AnalyzerState: Sendable {
        var centsHistory: [Double] = []
        var lastTimestampNanos: UInt64 = 0
        var bendRangeSemitones: Double = 2.0
        let windowSize: Int = 22 // ~500ms at ~23ms hop interval
    }

    private let state = Mutex<AnalyzerState>(AnalyzerState())

    // MARK: - Initialization

    /// Create a new expression analyzer.
    ///
    /// - Parameter bendRangeSemitones: Initial pitch bend range in semitones.
    ///   Default is ±2 per MIDI spec. Updated automatically when device reports
    ///   its range via RPN 0 (Phase 5).
    public init(bendRangeSemitones: Double = 2.0) {
        state.withLock { $0.bendRangeSemitones = bendRangeSemitones }
    }

    // MARK: - Public Methods

    /// Process a pitch bend event and return an expression classification.
    ///
    /// Converts the bend value to cents offset using the configured bend range,
    /// appends to the rolling window, and runs expression analysis when enough
    /// samples are accumulated (minimum 10).
    ///
    /// - Parameter event: Pitch bend event from CoreMIDI.
    /// - Returns: Expression result, or nil if insufficient samples.
    public func process(_ event: MIDIPitchBendEvent) -> ExpressionResult? {
        state.withLock { s in
            let cents = event.toCents(bendRangeSemitones: s.bendRangeSemitones)
            let hopInterval = computeHopInterval(
                currentNanos: timestampToNanos(event.midiTimestamp),
                previousNanos: s.lastTimestampNanos
            )
            s.lastTimestampNanos = timestampToNanos(event.midiTimestamp)

            s.centsHistory.append(cents)
            if s.centsHistory.count > s.windowSize {
                s.centsHistory.removeFirst()
            }
            guard s.centsHistory.count >= 10 else { return nil }

            return PitchExpressionAnalyzer.analyze(
                centsHistory: s.centsHistory,
                hopIntervalSeconds: hopInterval
            )
        }
    }

    /// Process an aftertouch/pressure event and return an expression classification.
    ///
    /// Converts pressure to a 0-100 "cents-equivalent" scale for oscillation
    /// detection. Aftertouch oscillation at 1-3 Hz maps to gamaka-like expression.
    ///
    /// - Parameter event: Pressure event from CoreMIDI.
    /// - Returns: Expression result, or nil if insufficient samples.
    public func process(_ event: MIDIPressureEvent) -> ExpressionResult? {
        state.withLock { s in
            // Normalize pressure to 0-100 scale (cents-equivalent)
            let normalized: Double
            if event.pressure > 0 {
                normalized = Double(event.pressure) / Double(UInt32.max) * 100.0
            } else {
                normalized = Double(event.pressure7Bit) / 127.0 * 100.0
            }
            let hopInterval = computeHopInterval(
                currentNanos: timestampToNanos(event.midiTimestamp),
                previousNanos: s.lastTimestampNanos
            )
            s.lastTimestampNanos = timestampToNanos(event.midiTimestamp)

            s.centsHistory.append(normalized)
            if s.centsHistory.count > s.windowSize {
                s.centsHistory.removeFirst()
            }
            guard s.centsHistory.count >= 10 else { return nil }

            return PitchExpressionAnalyzer.analyze(
                centsHistory: s.centsHistory,
                hopIntervalSeconds: hopInterval
            )
        }
    }

    /// Process an incoming Registered Controller (RPN) event to detect pitch bend range.
    ///
    /// When the device reports RPN 0 (Pitch Bend Sensitivity), automatically
    /// updates the bend range used for cents conversion.
    ///
    /// - Parameter event: Registered control event from the parser.
    public func processRegisteredControl(_ event: MIDIRegisteredControlEvent) {
        // RPN 0: bank=0, index=0 = Pitch Bend Sensitivity
        guard event.controlType == .registered,
              event.bank == 0,
              event.index == 0 else { return }

        // Value is in semitones (MSB of the 32-bit value)
        let semitones = Double(event.value >> 25) // Top 7 bits = semitones
        if semitones > 0, semitones <= 48 {
            setBendRange(semitones: semitones)
        }
    }

    /// Update the pitch bend range used for cents conversion.
    ///
    /// Called when MIDI-CI or RPN 0 reports the device's actual bend range.
    ///
    /// - Parameter semitones: New bend range in semitones (e.g., 12 for ±12).
    public func setBendRange(semitones: Double) {
        state.withLock { $0.bendRangeSemitones = semitones }
    }

    /// Clear the rolling history. Call when switching sessions or devices.
    public func reset() {
        state.withLock { s in
            s.centsHistory.removeAll()
            s.lastTimestampNanos = 0
        }
    }

    // MARK: - Private Helpers

    /// Convert a CoreMIDI timestamp to nanoseconds.
    nonisolated private func timestampToNanos(_ timestamp: MIDITimeStamp?) -> UInt64 {
        guard let timestamp, timestamp > 0 else { return 0 }
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return timestamp * UInt64(info.numer) / UInt64(info.denom)
    }

    /// Compute hop interval between consecutive events.
    ///
    /// Clamped to `[0.002, 0.1]` seconds so a long pause between events can't
    /// drive the downstream DFT's minimum bin above its maximum (which would
    /// form an invalid `Range` and trap). Pitch-bend is at most ~1 kHz of
    /// resolution and at least a few milliseconds between events in practice.
    nonisolated private func computeHopInterval(
        currentNanos: UInt64,
        previousNanos: UInt64
    ) -> Double {
        guard previousNanos > 0, currentNanos > previousNanos else {
            return 0.023 // Default ~23ms hop interval
        }
        let raw = Double(currentNanos - previousNanos) / 1_000_000_000.0
        return min(max(raw, 0.002), 0.100)
    }
}
