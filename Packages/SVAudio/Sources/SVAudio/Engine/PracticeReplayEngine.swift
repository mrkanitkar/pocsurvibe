import Foundation
import os

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

    /// - Parameter events: Array of ``ReplayEvent`` sorted by timestamp.
    public func startReplay(events: [ReplayEvent]) {
        stop()
        guard !events.isEmpty else { return }

        duration = events.last?.timestamp ?? 0
        isReplaying = true
        currentPosition = 0

        Self.logger.info("Starting replay: \(events.count) events, \(String(format: "%.1f", self.duration))s")

        replayTask = Task { [weak self] in
            let startTime = ContinuousClock.now

            for event in events {
                guard !Task.isCancelled else { break }

                // Wait until the event's timestamp
                let targetOffset = Duration.seconds(event.timestamp)
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

                await MainActor.run {
                    self?.currentPosition = event.timestamp
                }
            }

            await MainActor.run {
                self?.isReplaying = false
                Self.logger.info("Replay completed")
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
}
