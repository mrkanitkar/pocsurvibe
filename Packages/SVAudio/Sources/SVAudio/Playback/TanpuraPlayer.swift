import AVFoundation
import os

/// Tanpura drone player using AVAudioPlayerNode with looped buffer playback.
/// Uses AudioEngineManager's tanpura node.
@MainActor
public final class TanpuraPlayer {
    public static let shared = TanpuraPlayer()
    private static let logger = Logger.survibe(category: "TanpuraPlayer")

    /// Reference to the engine's tanpura player node.
    private var playerNode: AVAudioPlayerNode {
        AudioEngineManager.shared.tanpuraNode
    }

    /// Whether the tanpura is currently playing.
    public private(set) var isPlaying: Bool = false

    /// Pre-loaded audio buffer for gapless looping.
    private var loopBuffer: AVAudioPCMBuffer?

    private init() {}

    /// Load a tanpura audio file for drone playback.
    /// Pre-loads into an AVAudioPCMBuffer for gapless looping.
    /// - Parameter url: URL to the tanpura audio file (.wav, .aif, .m4a)
    public func loadAudio(at url: URL) throws {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let frameCount = AVAudioFrameCount(audioFile.length)
            let format = audioFile.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                throw NSError(
                    domain: "TanpuraPlayer", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create PCM buffer"]
                )
            }
            try audioFile.read(into: buffer)
            loopBuffer = buffer
            Self.logger.info("Tanpura audio loaded: \(url.lastPathComponent, privacy: .public)")
        } catch {
            Self.logger.error("Tanpura audio load failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Loads a pre-generated audio buffer for looped playback.
    ///
    /// Use this to load a synthesized drone buffer (e.g., from
    /// `TanpuraDroneGenerator`) instead of loading from a file URL.
    ///
    /// - Parameter buffer: PCM buffer to loop. Must be in a format
    ///   compatible with the tanpura player node.
    public func loadAudio(buffer: AVAudioPCMBuffer) {
        loopBuffer = buffer
        Self.logger.info("Tanpura buffer loaded: \(buffer.frameLength, privacy: .public) frames")
    }

    /// Start the tanpura drone with gapless looped playback.
    public func start() {
        guard let loopBuffer else {
            Self.logger.debug("Tanpura start skipped: buffer not loaded")
            return
        }
        guard !isPlaying else {
            Self.logger.debug("Tanpura start skipped: already playing")
            return
        }

        // Schedule buffer with .loops for gapless playback at engine level
        playerNode.scheduleBuffer(loopBuffer, at: nil, options: .loops)
        playerNode.play()
        isPlaying = true
        Self.logger.info("Tanpura drone started")
    }

    /// Stop the tanpura drone.
    public func stop() {
        playerNode.stop()
        isPlaying = false
        Self.logger.info("Tanpura drone stopped")
    }

    /// Set the volume of the tanpura (0.0 to 1.0).
    public func setVolume(_ volume: Float) {
        AudioEngineManager.shared.setTanpuraVolume(volume)
    }
}
