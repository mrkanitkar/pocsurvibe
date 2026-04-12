import AVFoundation
import os.log

/// Thin wrapper over `TanpuraPlayer` for practice mode integration.
///
/// Delegates all audio playback to `TanpuraPlayer.shared` while providing
/// a clean interface for the practice view model. Manages Sa frequency and
/// volume state for the current practice session without duplicating the
/// buffer scheduling implementation.
///
/// Mirrors the `MetronomeEngine` pattern: stores local state, delegates
/// playback to the shared `TanpuraPlayer` singleton.
@MainActor
public final class TanpuraEngine {
    // MARK: - Properties

    /// Whether the tanpura drone is currently playing.
    public var isPlaying: Bool {
        TanpuraPlayer.shared.isPlaying
    }

    /// Current volume (0.0 to 1.0).
    public private(set) var volume: Float

    /// Current Sa reference frequency in Hz.
    public private(set) var saFrequency: Double

    private static let logger = Logger.survibe(category: "TanpuraEngine")

    // MARK: - Initialization

    /// Create a new tanpura engine with the given initial settings.
    ///
    /// - Parameters:
    ///   - saFrequency: Sa reference frequency in Hz (default: 261.63 = C4).
    ///   - volume: Initial volume from 0.0 to 1.0 (default: 0.3).
    public init(saFrequency: Double = 261.63, volume: Float = 0.3) {
        self.saFrequency = saFrequency
        self.volume = volume
    }

    // MARK: - Public Methods

    /// Start the tanpura drone at the configured frequency and volume.
    ///
    /// Generates a drone buffer via `TanpuraDroneGenerator`, loads it into
    /// `TanpuraPlayer.shared`, sets the volume, then starts playback.
    /// Safe to call if already playing -- TanpuraPlayer guards against
    /// double-start.
    ///
    /// - Throws: `AudioError.bufferCreationFailed` if drone buffer generation fails.
    public func start() throws {
        let buffer = try TanpuraDroneGenerator.generateDroneBuffer(
            saFrequency: saFrequency
        )
        TanpuraPlayer.shared.loadAudio(buffer: buffer)
        TanpuraPlayer.shared.setVolume(volume)
        TanpuraPlayer.shared.start()
        Self.logger.info(
            "Tanpura started: Sa=\(self.saFrequency, privacy: .public)Hz vol=\(self.volume, privacy: .public)"
        )
    }

    /// Stop the tanpura drone.
    ///
    /// Delegates to `TanpuraPlayer.shared.stop()`. Safe to call
    /// if the tanpura is not currently playing.
    public func stop() {
        TanpuraPlayer.shared.stop()
        Self.logger.info("Tanpura stopped")
    }

    /// Update the volume. Takes effect immediately.
    ///
    /// Clamps the value to the valid range [0.0, 1.0].
    ///
    /// - Parameter newVolume: New volume from 0.0 to 1.0.
    public func updateVolume(_ newVolume: Float) {
        volume = max(0.0, min(1.0, newVolume))
        TanpuraPlayer.shared.setVolume(volume)
    }

    /// Update the Sa reference frequency and regenerate the drone buffer.
    ///
    /// If the tanpura is currently playing, it is stopped, a new buffer is
    /// generated at the new frequency, and playback is restarted.
    ///
    /// - Parameter frequency: New Sa frequency in Hz.
    /// - Throws: `AudioError.bufferCreationFailed` if drone buffer generation fails.
    public func updateSaFrequency(_ frequency: Double) throws {
        saFrequency = frequency
        if isPlaying {
            TanpuraPlayer.shared.stop()
            let buffer = try TanpuraDroneGenerator.generateDroneBuffer(
                saFrequency: saFrequency
            )
            TanpuraPlayer.shared.loadAudio(buffer: buffer)
            TanpuraPlayer.shared.setVolume(volume)
            TanpuraPlayer.shared.start()
            Self.logger.info(
                "Tanpura restarted with new Sa=\(self.saFrequency, privacy: .public)Hz"
            )
        }
    }
}
