import Foundation
import SVCore

/// Simple tempo-based time provider that converts between seconds and beats.
///
/// Uses a constant BPM for conversion. For songs with tempo changes, create a
/// `TempoMapTimeProvider` (future) that uses an array of tempo change events.
///
/// ## Thread Safety
///
/// This type is `Sendable` — all state is immutable after initialization.
/// Safe to use from any isolation context.
public struct TempoSyncedTimeProvider: MusicTimeProvider, Sendable {

    /// Default tempo in BPM, used when callers don't specify.
    public let defaultBPM: Double

    /// Create a tempo-synced time provider.
    ///
    /// - Parameter bpm: Default beats per minute. Used when caller passes 0 for tempo.
    public init(bpm: Double = 120.0) {
        self.defaultBPM = bpm
    }

    /// Convert wall-clock seconds to beats.
    ///
    /// - Parameters:
    ///   - seconds: Elapsed time in seconds.
    ///   - tempo: BPM override. If 0, uses `defaultBPM`.
    /// - Returns: Beat position.
    public func wallToBeats(seconds: Double, tempo: Double) -> Double {
        let bpm = tempo > 0 ? tempo : defaultBPM
        return MusicTime.secondsToBeats(seconds: seconds, bpm: bpm)
    }

    /// Convert beats to wall-clock seconds.
    ///
    /// - Parameters:
    ///   - beats: Beat position.
    ///   - tempo: BPM override. If 0, uses `defaultBPM`.
    /// - Returns: Elapsed seconds.
    public func beatsToWall(beats: Double, tempo: Double) -> Double {
        let bpm = tempo > 0 ? tempo : defaultBPM
        return MusicTime.beatsToSeconds(beats: beats, bpm: bpm)
    }
}
