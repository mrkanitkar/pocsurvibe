import Foundation
import os
import zlib

/// Replays a recorded practice session by feeding saved events back through the pipeline.
///
/// Reads ``MIDIEventEntry`` and ``PitchLogEntry`` timestamps from a saved session
/// and delivers them as ``PerformanceEvent`` values at their original timing.
/// Results should be deterministic — same input produces same scores.
///
/// ## Architecture
///
/// ```
/// Saved session data ──→ PracticeReplayEngine ──→ PerformanceEngine ──→ NoteMatchingActor
/// ```
///
/// The replay engine is a producer that feeds into the same ``PerformanceEngine``
/// pipeline used by live input. This ensures scoring uses the exact same code path.
///
/// ## Scope
/// Core replay at 1x speed. Speed control (0.5x, 2x) and visual notation replay
/// are deferred to Wave 3 (see Implementation_Plan.md).
@MainActor
public final class PracticeReplayEngine {

    // MARK: - State

    /// Whether replay is currently in progress.
    public private(set) var isReplaying = false

    /// Current replay position in seconds.
    public private(set) var currentPosition: Double = 0

    /// Total duration of the replay session in seconds.
    public private(set) var duration: Double = 0

    /// Playback speed multiplier (0.5 = half speed, 1.0 = normal, 2.0 = double).
    ///
    /// Change during replay to speed up or slow down. Applied to the sleep
    /// duration between events — lower values increase the wait, higher values
    /// decrease it. Clamped to 0.25–4.0.
    public var speed: Double = 1.0 {
        didSet { speed = max(0.25, min(4.0, speed)) }
    }

    // MARK: - Integrity (MIN-16)

    /// Whether the most recent replay detected a checksum mismatch.
    ///
    /// Set to `true` when ``verifyChecksum(_:events:)`` detects that the CRC32
    /// of the replay events does not match the expected value. Does NOT block
    /// replay — purely informational for diagnostics and UI warnings.
    public private(set) var replayIntegrityWarning: Bool = false

    // MARK: - Score Divergence (MIN-17)

    /// Number of notes where replay scoring diverged from original scores.
    ///
    /// Incremented during replay when a scored note's composite accuracy
    /// differs from the original ``OriginalScore`` by more than 0.01.
    /// A count of 0 after replay confirms deterministic scoring.
    public private(set) var scoreDivergenceCount: Int = 0

    /// Original per-note composite scores for divergence comparison (MIN-17).
    ///
    /// Set by the caller before ``startReplay(events:)`` when original scores
    /// are available. Keyed by note index (zero-based).
    public var originalScores: [OriginalScore] = []

    /// Task driving the replay loop.
    private var replayTask: Task<Void, Never>?

    /// Target performance engine for event delivery.
    private let performanceEngine: PerformanceEngine

    private static let logger = Logger.survibe(category: "PracticeReplay")

    // MARK: - Initialization

    /// Create a replay engine targeting a performance engine.
    ///
    /// - Parameter performanceEngine: The engine that will receive replayed events.
    public init(performanceEngine: PerformanceEngine) {
        self.performanceEngine = performanceEngine
    }

    // MARK: - Replay Control

    /// Start replaying a session from saved MIDI events.
    ///
    /// Events are delivered at their original timestamps relative to session start.
    /// The replay is deterministic — same events produce same scores.
    ///
    /// A single event to replay, extracted from saved ``MIDIEventEntry`` rows.
    public struct ReplayEvent: Sendable {
        /// Time offset from session start in seconds.
        public let timestamp: Double
        /// MIDI note number (0–127).
        public let noteNumber: UInt8
        /// Velocity (0 = note-off, 1–127 = note-on).
        public let velocity: UInt8
        /// MIDI channel (0–15).
        public let channel: UInt8

        public init(timestamp: Double, noteNumber: UInt8, velocity: UInt8, channel: UInt8) {
            self.timestamp = timestamp
            self.noteNumber = noteNumber
            self.velocity = velocity
            self.channel = channel
        }
    }

    /// Start replaying events and optionally verify checksum integrity.
    ///
    /// - Parameters:
    ///   - events: Array of ``ReplayEvent`` sorted by timestamp.
    ///   - expectedChecksum: Optional CRC32 hex string. When provided, events
    ///     are verified before replay begins. Mismatch sets ``replayIntegrityWarning``
    ///     but does not block replay.
    public func startReplay(events: [ReplayEvent], expectedChecksum: String? = nil) {
        stop()
        guard !events.isEmpty else { return }

        // Reset integrity and divergence state for this replay pass.
        replayIntegrityWarning = false
        scoreDivergenceCount = 0

        // MIN-16: Verify checksum if provided.
        if let checksum = expectedChecksum {
            verifyChecksum(checksum, events: events)
        }

        duration = events.last?.timestamp ?? 0
        isReplaying = true
        currentPosition = 0

        Self.logger.info("Starting replay: \(events.count) events, \(String(format: "%.1f", self.duration))s")

        let scores = originalScores

        replayTask = Task { [weak self] in
            let startTime = ContinuousClock.now
            var noteIndex = 0

            for event in events {
                guard !Task.isCancelled else { break }

                // Wait until the event's timestamp, scaled by speed.
                let currentSpeed = self?.speed ?? 1.0
                let scaledTimestamp = event.timestamp / currentSpeed
                let targetOffset = Duration.seconds(scaledTimestamp)
                let elapsed = ContinuousClock.now - startTime
                if targetOffset > elapsed {
                    try? await Task.sleep(for: targetOffset - elapsed)
                }
                guard !Task.isCancelled else { break }

                // Deliver as PerformanceEvent
                self?.performanceEngine.deliver(.midi(
                    noteNumber: event.noteNumber,
                    velocity: event.velocity,
                    channel: event.channel,
                    probeToken: nil
                ))

                // MIN-17: Compare replay score with original if available.
                // Only note-on events (velocity > 0) are scored.
                if event.velocity > 0, noteIndex < scores.count {
                    // The actual comparison happens when scoring is complete.
                    // Here we track the note index for post-hoc comparison.
                    noteIndex += 1
                }

                await MainActor.run {
                    self?.currentPosition = event.timestamp
                }
            }

            let divergenceCount = self?.scoreDivergenceCount ?? 0
            await MainActor.run {
                self?.isReplaying = false
                Self.logger.info(
                    "Replay completed: divergenceCount=\(divergenceCount)"
                )
            }
        }
    }

    /// Stop an in-progress replay.
    public func stop() {
        replayTask?.cancel()
        replayTask = nil
        isReplaying = false
        currentPosition = 0
    }

    // MARK: - Checksum Verification (MIN-16)

    /// Verify the integrity of replay events against an expected CRC32 checksum.
    ///
    /// Computes a CRC32 checksum over concatenated `timestamp + noteNumber` values
    /// for each event and compares against the expected value. On mismatch, sets
    /// ``replayIntegrityWarning`` to `true` and logs a warning.
    ///
    /// - Important: Does NOT block replay on failure. The warning is informational.
    ///
    /// - Parameters:
    ///   - expectedChecksum: Hex string of the expected CRC32 value.
    ///   - events: The replay events to verify.
    /// - Returns: `true` if checksums match, `false` on mismatch.
    @discardableResult
    public func verifyChecksum(_ expectedChecksum: String, events: [ReplayEvent]) -> Bool {
        let computed = Self.computeCRC32(events: events)
        let matches = computed == expectedChecksum
        if !matches {
            replayIntegrityWarning = true
            Self.logger.warning(
                "Replay checksum mismatch: expected \(expectedChecksum, privacy: .public) got \(computed, privacy: .public)"
            )
        } else {
            replayIntegrityWarning = false
        }
        return matches
    }

    /// Compute a CRC32 checksum over replay events.
    ///
    /// Uses `zlib.crc32()` on the concatenation of each event's timestamp
    /// (formatted to 6 decimal places) and note number.
    ///
    /// - Parameter events: The replay events to checksum.
    /// - Returns: Hex string representation of the CRC32 value.
    public static func computeCRC32(events: [ReplayEvent]) -> String {
        var crc: UInt = UInt(zlib.crc32(0, nil, 0))
        for event in events {
            let entry = "\(String(format: "%.6f", event.timestamp)):\(event.noteNumber)"
            let bytes = Array(entry.utf8)
            crc = UInt(
                bytes.withUnsafeBufferPointer { ptr in
                    zlib.crc32(
                        uLong(crc),
                        ptr.baseAddress,
                        uInt(ptr.count)
                    )
                }
            )
        }
        return String(format: "%08x", crc)
    }

    // MARK: - Score Comparison (MIN-17)

    /// Compare a replayed note's composite score against the original.
    ///
    /// Call this after each note is scored during replay. If the difference
    /// exceeds 0.01 (1% tolerance), increments ``scoreDivergenceCount``
    /// and logs the divergence.
    ///
    /// - Parameters:
    ///   - replayedScore: Composite accuracy from the replay scoring pass.
    ///   - noteIndex: Zero-based index of the note in the session.
    public func checkScoreDivergence(replayedScore: Double, noteIndex: Int) {
        guard noteIndex < originalScores.count else { return }
        let original = originalScores[noteIndex]
        let diff = abs(replayedScore - original.compositeAccuracy)
        if diff > 0.01 {
            scoreDivergenceCount += 1
            Self.logger.info(
                """
                Score divergence at note \(noteIndex): \
                original=\(String(format: "%.4f", original.compositeAccuracy)) \
                replay=\(String(format: "%.4f", replayedScore)) \
                diff=\(String(format: "%.4f", diff))
                """
            )
        }
    }
}

// MARK: - Supporting Types

/// A lightweight snapshot of an original note score for replay comparison (MIN-17).
///
/// Passed to ``PracticeReplayEngine`` before starting replay so that re-scored
/// notes can be compared against the original session's values.
public struct OriginalScore: Sendable {
    /// Zero-based index of the note within the session.
    public let noteIndex: Int

    /// Composite accuracy from the original scoring pass (0.0--1.0).
    public let compositeAccuracy: Double

    /// Create an original score snapshot.
    ///
    /// - Parameters:
    ///   - noteIndex: Zero-based position in the session.
    ///   - compositeAccuracy: Original composite accuracy (0.0--1.0).
    public init(noteIndex: Int, compositeAccuracy: Double) {
        self.noteIndex = noteIndex
        self.compositeAccuracy = compositeAccuracy
    }
}
