import Foundation

/// Converts between wall-clock time (seconds) and musical time (beats).
///
/// Implementations handle tempo mapping, allowing real-time scoring to compare
/// played onset times against expected beat positions. Supports tempo changes
/// mid-song via a tempo map.
///
/// ## Usage
///
/// ```swift
/// let provider: MusicTimeProvider = TempoSyncedTimeProvider(bpm: 120)
/// let beats = provider.wallToBeats(seconds: 2.0)  // 4.0 beats
/// let wall = provider.beatsToWall(beats: 8.0)      // 4.0 seconds
/// ```
public protocol MusicTimeProvider: Sendable {
    /// Convert wall-clock seconds to beat position.
    ///
    /// - Parameters:
    ///   - seconds: Elapsed time in seconds from session start.
    ///   - tempo: Tempo in BPM. Ignored by implementations that use a tempo map.
    /// - Returns: Beat position (0-based).
    func wallToBeats(seconds: Double, tempo: Double) -> Double

    /// Convert beat position to wall-clock seconds.
    ///
    /// - Parameters:
    ///   - beats: Beat position (0-based).
    ///   - tempo: Tempo in BPM. Ignored by implementations that use a tempo map.
    /// - Returns: Elapsed time in seconds from session start.
    func beatsToWall(beats: Double, tempo: Double) -> Double
}
