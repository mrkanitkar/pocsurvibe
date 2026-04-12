import AVFoundation
import Foundation
import SVCore
import os

/// Generates a loopable tanpura drone buffer using additive synthesis.
///
/// Creates a Sa-Pa drone using harmonic-rich waveforms at the specified
/// reference frequency. The buffer is designed for seamless looping via
/// AVAudioPlayerNode's `.loops` option.
///
/// ## Synthesis Method
/// Each tone (Sa and Pa) is generated with a fundamental and second harmonic.
/// The Pa tone is tuned to the just-intonation perfect fifth (Sa x 3/2).
/// A crossfade at the loop boundary (last 50ms fades out, first 50ms fades in)
/// ensures gapless looping without audible clicks.
public enum TanpuraDroneGenerator {
    private static let logger = Logger.survibe(category: "TanpuraDrone")

    // MARK: - Constants

    /// Amplitude of Sa fundamental.
    private static let saFundamentalAmp: Float = 0.6

    /// Amplitude of Sa second harmonic.
    private static let saSecondHarmonicAmp: Float = 0.3

    /// Pa volume relative to Sa.
    private static let paRelativeVolume: Float = 0.4

    /// Just-intonation perfect fifth ratio (Sa to Pa).
    private static let perfectFifthRatio: Double = 3.0 / 2.0

    /// Crossfade duration in seconds at loop boundary.
    private static let crossfadeDuration: Double = 0.05

    // MARK: - Public Methods

    /// Generates a loopable drone buffer with Sa and Pa tones.
    ///
    /// Uses additive synthesis with fundamental + second harmonic for each tone.
    /// The Pa is tuned to a just-intonation perfect fifth above Sa (frequency x 3/2).
    /// A 50ms crossfade at the loop boundary ensures gapless looping.
    ///
    /// - Parameters:
    ///   - saFrequency: Sa reference frequency in Hz (default 261.63 = C4).
    ///   - sampleRate: Audio sample rate (default 44100).
    ///   - durationSeconds: Loop duration in seconds (default 4.0).
    /// - Returns: AVAudioPCMBuffer suitable for looped playback.
    /// - Throws: `AudioError.bufferCreationFailed` if the PCM buffer cannot be allocated.
    nonisolated public static func generateDroneBuffer(
        saFrequency: Double = 261.63,
        sampleRate: Double = 44100,
        durationSeconds: Double = 4.0
    ) throws -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else {
            throw AudioError.bufferCreationFailed(
                reason: "Failed to create mono audio format at \(sampleRate) Hz")
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioError.bufferCreationFailed(
                reason: "Failed to allocate PCM buffer for \(frameCount) frames")
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            throw AudioError.bufferCreationFailed(
                reason: "Float channel data unavailable after buffer allocation")
        }

        let paFrequency = saFrequency * perfectFifthRatio

        // Generate Sa + Pa additive synthesis
        fillDroneBuffer(
            channelData: channelData,
            frameCount: Int(frameCount),
            saFrequency: saFrequency,
            paFrequency: paFrequency,
            sampleRate: sampleRate
        )

        // Normalize peak amplitude to below 1.0
        normalizePeakAmplitude(channelData: channelData, frameCount: Int(frameCount))

        // Apply crossfade at loop boundary for gapless looping
        let crossfadeFrames = Int(sampleRate * crossfadeDuration)
        applyCrossfade(
            channelData: channelData,
            frameCount: Int(frameCount),
            crossfadeFrames: crossfadeFrames
        )

        let frames = frameCount
        logger.info(
            "Drone buffer: Sa=\(saFrequency, privacy: .public)Hz frames=\(frames, privacy: .public)"
        )

        return buffer
    }

    // MARK: - Private Methods

    /// Fill the buffer with Sa and Pa tones using additive synthesis.
    ///
    /// - Parameters:
    ///   - channelData: Pointer to the float channel data to fill.
    ///   - frameCount: Total number of frames in the buffer.
    ///   - saFrequency: Fundamental frequency of Sa in Hz.
    ///   - paFrequency: Fundamental frequency of Pa in Hz.
    ///   - sampleRate: Audio sample rate in Hz.
    nonisolated private static func fillDroneBuffer(
        channelData: UnsafeMutablePointer<Float>,
        frameCount: Int,
        saFrequency: Double,
        paFrequency: Double,
        sampleRate: Double
    ) {
        let twoPi = 2.0 * Double.pi

        for frame in 0..<frameCount {
            let time = Double(frame) / sampleRate

            // Sa: fundamental + 2nd harmonic
            let saFundamental = Float(sin(twoPi * saFrequency * time)) * saFundamentalAmp
            let saHarmonic = Float(sin(twoPi * saFrequency * 2.0 * time)) * saSecondHarmonicAmp

            // Pa: fundamental + 2nd harmonic at relative volume
            let paFundamental =
                Float(sin(twoPi * paFrequency * time)) * saFundamentalAmp * paRelativeVolume
            let paHarmonic =
                Float(sin(twoPi * paFrequency * 2.0 * time)) * saSecondHarmonicAmp
                * paRelativeVolume

            channelData[frame] = saFundamental + saHarmonic + paFundamental + paHarmonic
        }
    }

    /// Normalize the buffer so peak amplitude is below 1.0.
    ///
    /// Scans for the maximum absolute sample value and scales all samples
    /// to keep the peak at 0.95 (leaving headroom).
    ///
    /// - Parameters:
    ///   - channelData: Pointer to the float channel data.
    ///   - frameCount: Total number of frames in the buffer.
    nonisolated private static func normalizePeakAmplitude(
        channelData: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        var peakAmplitude: Float = 0.0
        for frame in 0..<frameCount {
            let absVal = abs(channelData[frame])
            if absVal > peakAmplitude {
                peakAmplitude = absVal
            }
        }

        guard peakAmplitude > 0 else { return }

        let targetPeak: Float = 0.95
        let scale = targetPeak / peakAmplitude
        for frame in 0..<frameCount {
            channelData[frame] *= scale
        }
    }

    /// Apply a crossfade at the loop boundary for gapless looping.
    ///
    /// The last `crossfadeFrames` samples fade out linearly, and the first
    /// `crossfadeFrames` samples fade in linearly. This ensures the loop
    /// point does not produce an audible click.
    ///
    /// - Parameters:
    ///   - channelData: Pointer to the float channel data.
    ///   - frameCount: Total number of frames in the buffer.
    ///   - crossfadeFrames: Number of frames over which to apply the crossfade.
    nonisolated private static func applyCrossfade(
        channelData: UnsafeMutablePointer<Float>,
        frameCount: Int,
        crossfadeFrames: Int
    ) {
        let fadeFrames = min(crossfadeFrames, frameCount / 2)
        guard fadeFrames > 0 else { return }

        for i in 0..<fadeFrames {
            let fadeIn = Float(i) / Float(fadeFrames)
            let fadeOut = 1.0 - fadeIn

            // Fade in at the start
            channelData[i] *= fadeIn

            // Fade out at the end
            channelData[frameCount - 1 - i] *= fadeOut
        }
    }
}
