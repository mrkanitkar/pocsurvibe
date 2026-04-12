import Foundation
import os.log

/// Thin wrapper over `MetronomePlayer` for practice mode integration.
///
/// Delegates all audio scheduling to `MetronomePlayer.shared` while providing
/// a clean interface for the practice view model. Manages BPM and volume
/// state for the current practice session without duplicating the
/// sample-accurate scheduling implementation.
@MainActor
public final class MetronomeEngine {
    // MARK: - Properties

    /// Whether the metronome is currently playing.
    public var isPlaying: Bool {
        MetronomePlayer.shared.isPlaying
    }

    /// Current beats per minute.
    public private(set) var bpm: Double

    /// Current volume (0.0 to 1.0).
    public private(set) var volume: Float

    private static let logger = Logger.survibe(category: "MetronomeEngine")

    // MARK: - Initialization

    /// Create a new metronome engine with the given initial settings.
    ///
    /// - Parameters:
    ///   - bpm: Initial beats per minute (default: 60).
    ///   - volume: Initial volume from 0.0 to 1.0 (default: 0.5).
    public init(bpm: Double = 60.0, volume: Float = 0.5) {
        self.bpm = bpm
        self.volume = volume
    }

    // MARK: - Public Methods

    /// Start the metronome at the configured BPM and volume.
    ///
    /// Configures `MetronomePlayer.shared` with the current BPM and volume,
    /// then starts playback. Safe to call if already playing — MetronomePlayer
    /// guards against double-start.
    public func start() {
        MetronomePlayer.shared.setBPM(bpm)
        MetronomePlayer.shared.setVolume(volume)
        MetronomePlayer.shared.start()
        Self.logger.info("Metronome started: bpm=\(self.bpm) vol=\(self.volume)")
    }

    /// Stop the metronome.
    ///
    /// Delegates to `MetronomePlayer.shared.stop()`. Safe to call
    /// if the metronome is not currently playing.
    public func stop() {
        MetronomePlayer.shared.stop()
        Self.logger.info("Metronome stopped")
    }

    /// Update the BPM. Takes effect immediately if the metronome is playing.
    ///
    /// - Parameter newBPM: New beats per minute value (1-300).
    public func updateBPM(_ newBPM: Double) {
        bpm = newBPM
        MetronomePlayer.shared.setBPM(newBPM)
        Self.logger.info("Metronome BPM updated: \(newBPM)")
    }

    /// Update the volume. Takes effect immediately.
    ///
    /// Clamps the value to the valid range [0.0, 1.0].
    ///
    /// - Parameter newVolume: New volume from 0.0 to 1.0.
    public func updateVolume(_ newVolume: Float) {
        volume = max(0.0, min(1.0, newVolume))
        MetronomePlayer.shared.setVolume(volume)
    }
}
