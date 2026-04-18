import CoreMIDI
import Foundation
import Observation
import os

/// Orchestrates a tap-along calibration session to measure MIDI input latency.
///
/// Plays a metronome at 100 BPM and records the delta between expected beat
/// times and actual MIDI note-on hardware timestamps. After collecting 16 taps,
/// removes outliers (>2 standard deviations) and computes the median offset.
@Observable
@MainActor
public final class LatencyCalibrator {

    // MARK: - State

    /// Calibration session state.
    public enum State: Sendable, Equatable {
        case idle
        case calibrating(tapsCollected: Int, total: Int)
        case complete(result: CalibrationResult)
        case error(message: String)
    }

    /// Current calibration state. Observable for UI binding.
    public private(set) var state: State = .idle

    // MARK: - Configuration

    /// Number of taps to collect before computing result.
    public let targetTaps: Int = 16

    /// Metronome tempo in BPM for calibration.
    public let calibrationBPM: Double = 100.0

    // MARK: - Private State

    /// Create a new latency calibrator.
    public init() {}

    private var tapDeltas: [Double] = []
    private var expectedBeatTimesNanos: [UInt64] = []
    private var currentBeatIndex: Int = 0
    private var sessionStartNanos: UInt64 = 0
    private var isRunning: Bool = false

    private static let logger = Logger.survibe(category: "LatencyCalibrator")

    /// Cached timebase info for mach tick conversion.
    nonisolated private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    // MARK: - Public Methods

    /// Record a tap from MIDI input during calibration.
    public func recordTap(midiTimestamp: MIDITimeStamp?) {
        guard isRunning, currentBeatIndex < expectedBeatTimesNanos.count else { return }

        let tapNanos: UInt64
        if let ts = midiTimestamp, ts > 0 {
            tapNanos = Self.hostTicksToNanos(ts)
        } else {
            tapNanos = Self.hostTicksToNanos(mach_absolute_time())
        }

        let expectedNanos = expectedBeatTimesNanos[currentBeatIndex]
        let deltaSeconds = Double(Int64(tapNanos) - Int64(expectedNanos)) / 1_000_000_000.0

        tapDeltas.append(deltaSeconds)
        currentBeatIndex += 1

        let collected = tapDeltas.count
        state = .calibrating(tapsCollected: collected, total: targetTaps)

        let deltaMs = deltaSeconds * 1000
        Self.logger.debug("Tap \(collected)/\(self.targetTaps): delta = \(deltaMs, format: .fixed(precision: 1))ms")

        if collected >= targetTaps {
            finishCalibration()
        }
    }

    /// Reset the calibrator to idle state.
    public func reset() {
        tapDeltas.removeAll()
        expectedBeatTimesNanos.removeAll()
        currentBeatIndex = 0
        isRunning = false
        state = .idle
    }

    /// Prepare calibration session with beat times.
    public func prepare() {
        tapDeltas.removeAll()
        currentBeatIndex = 0
        sessionStartNanos = Self.hostTicksToNanos(mach_absolute_time())

        let beatIntervalNanos = UInt64(60.0 / calibrationBPM * 1_000_000_000.0)
        expectedBeatTimesNanos = (0..<targetTaps).map { i in
            sessionStartNanos + UInt64(i) * beatIntervalNanos
        }

        isRunning = true
        state = .calibrating(tapsCollected: 0, total: targetTaps)
    }

    // MARK: - Private Methods

    private func finishCalibration() {
        isRunning = false

        guard tapDeltas.count >= 8 else {
            state = .error(message: "Insufficient taps collected")
            return
        }

        let mean = tapDeltas.reduce(0, +) / Double(tapDeltas.count)
        let variance = tapDeltas.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(tapDeltas.count - 1)
        let stdDev = sqrt(variance)

        let filtered = tapDeltas.filter { abs($0 - mean) <= 2.0 * stdDev }

        guard filtered.count >= 6 else {
            state = .error(message: "Too many outlier taps. Please try again with steadier tapping.")
            return
        }

        let sorted = filtered.sorted()
        let median: Double
        if sorted.count % 2 == 0 {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        } else {
            median = sorted[sorted.count / 2]
        }

        let filteredMean = filtered.reduce(0, +) / Double(filtered.count)
        let squaredDiffs = filtered.map { ($0 - filteredMean) * ($0 - filteredMean) }
        let filteredVariance = squaredDiffs.reduce(0, +) / Double(filtered.count - 1)
        let filteredStdDev = sqrt(filteredVariance)

        let result = CalibrationResult(
            medianOffsetSeconds: median,
            standardDeviationSeconds: filteredStdDev,
            sampleCount: filtered.count
        )

        state = .complete(result: result)
        let medianMs = median * 1000
        let stdDevMs = filteredStdDev * 1000
        let sampleN = filtered.count
        Self.logger.info(
            // swiftlint:disable:next line_length
            "Calibration complete: median=\(medianMs, format: .fixed(precision: 1))ms, σ=\(stdDevMs, format: .fixed(precision: 1))ms, samples=\(sampleN)"
        )
    }

    /// Convert CoreMIDI host ticks to nanoseconds using cached timebase.
    nonisolated private static func hostTicksToNanos(_ ticks: UInt64) -> UInt64 {
        ticks * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
    }
}
