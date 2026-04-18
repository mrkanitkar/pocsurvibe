import Foundation

/// Reusable conversion layer for musical-time ↔ screen-position mapping.
///
/// Centralizes the beat/seconds/screen-position math that was previously
/// scattered across `NoteEvent.fromNotation()` and layout engines.
/// Uses `TempoSyncedTimeProvider` for beat↔seconds conversion.
///
/// ## Thread Safety
///
/// Immutable after initialization; `Sendable` by default.
public struct TimeToPositionMapper: Sendable {

    /// The time provider used for beat↔seconds conversions.
    private let timeProvider: TempoSyncedTimeProvider

    /// Create a mapper with a given tempo provider.
    ///
    /// - Parameter timeProvider: The provider for beat↔seconds math.
    public init(timeProvider: TempoSyncedTimeProvider = TempoSyncedTimeProvider()) {
        self.timeProvider = timeProvider
    }

    // MARK: - Beat ↔ Seconds

    /// Convert beats to wall-clock seconds at a given tempo.
    ///
    /// - Parameters:
    ///   - beats: Duration or position in beats.
    ///   - tempo: Tempo in BPM.
    /// - Returns: Equivalent seconds.
    public func beatsToSeconds(beats: Double, tempo: Double) -> Double {
        timeProvider.beatsToWall(beats: beats, tempo: tempo)
    }

    /// Convert wall-clock seconds to beats at a given tempo.
    ///
    /// - Parameters:
    ///   - seconds: Duration or position in seconds.
    ///   - tempo: Tempo in BPM.
    /// - Returns: Equivalent beats.
    public func secondsToBeats(seconds: Double, tempo: Double) -> Double {
        timeProvider.wallToBeats(seconds: seconds, tempo: tempo)
    }

    // MARK: - Beat → Screen

    /// Convert a beat position to a screen X coordinate.
    ///
    /// - Parameters:
    ///   - beats: Position in beats.
    ///   - pixelsPerBeat: Horizontal pixels per beat.
    ///   - scrollOffset: Current scroll offset in pixels.
    /// - Returns: Screen X position in points.
    public func beatsToScreenX(
        beats: Double,
        pixelsPerBeat: Double,
        scrollOffset: Double = 0
    ) -> Double {
        beats * pixelsPerBeat - scrollOffset
    }

    /// Convert a seconds position to a screen X coordinate.
    ///
    /// - Parameters:
    ///   - seconds: Position in seconds.
    ///   - tempo: Tempo in BPM.
    ///   - pixelsPerBeat: Horizontal pixels per beat.
    ///   - scrollOffset: Current scroll offset in pixels.
    /// - Returns: Screen X position in points.
    public func secondsToScreenX(
        seconds: Double,
        tempo: Double,
        pixelsPerBeat: Double,
        scrollOffset: Double = 0
    ) -> Double {
        let beats = secondsToBeats(seconds: seconds, tempo: tempo)
        return beatsToScreenX(beats: beats, pixelsPerBeat: pixelsPerBeat, scrollOffset: scrollOffset)
    }
}
