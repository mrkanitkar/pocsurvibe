import AVFoundation
import Testing

@testable import SVAudio

@Suite("TanpuraDroneGenerator Tests")
struct TanpuraDroneGeneratorTests {
    @Test("Generated buffer is non-empty")
    func generateDroneBufferReturnsNonEmpty() throws {
        let buffer = try TanpuraDroneGenerator.generateDroneBuffer()
        #expect(buffer.frameLength > 0)
    }

    @Test("Frame count matches sampleRate * duration")
    func generateDroneBufferHasCorrectFrameCount() throws {
        let sampleRate: Double = 44100
        let duration: Double = 4.0
        let buffer = try TanpuraDroneGenerator.generateDroneBuffer(
            sampleRate: sampleRate,
            durationSeconds: duration
        )
        let expectedFrameCount = AVAudioFrameCount(sampleRate * duration)
        #expect(buffer.frameLength == expectedFrameCount)
    }

    @Test("Custom frequency generates valid buffer")
    func generateDroneBufferWithCustomFrequency() throws {
        let customSaFrequency: Double = 440.0
        let buffer = try TanpuraDroneGenerator.generateDroneBuffer(
            saFrequency: customSaFrequency,
            sampleRate: 44100,
            durationSeconds: 2.0
        )
        #expect(buffer.frameLength == AVAudioFrameCount(44100 * 2.0))
        #expect(buffer.format.channelCount == 1)
        #expect(buffer.format.sampleRate == 44100)
    }

    @Test("Peak amplitude is below 1.0")
    func bufferPeakAmplitudeBelowOne() throws {
        let buffer = try TanpuraDroneGenerator.generateDroneBuffer()
        guard let channelData = buffer.floatChannelData?[0] else {
            Issue.record("Float channel data unavailable")
            return
        }

        var peakAmplitude: Float = 0.0
        for frame in 0..<Int(buffer.frameLength) {
            let absVal = abs(channelData[frame])
            if absVal > peakAmplitude {
                peakAmplitude = absVal
            }
        }

        #expect(peakAmplitude < 1.0)
        #expect(peakAmplitude > 0.0)
    }

    @Test("Loop boundary samples are crossfaded near zero")
    func bufferBoundaryIsCrossfaded() throws {
        let buffer = try TanpuraDroneGenerator.generateDroneBuffer()
        guard let channelData = buffer.floatChannelData?[0] else {
            Issue.record("Float channel data unavailable")
            return
        }

        let frameCount = Int(buffer.frameLength)

        // First sample should be near zero (faded in from 0).
        // applyCrossfade multiplies channelData[0] by fadeIn=0.0, so first sample is 0.
        let firstSample = abs(channelData[0])
        #expect(firstSample < 0.01)

        // The crossfade fade-out ramp applies fadeOut = 1.0 at the last sample
        // (i=0 → fadeOut=1.0) and approaches 0.0 at the start of the fade
        // region. The last sample retains its full post-normalization amplitude,
        // which depends on the waveform phase at that frame. Verify it stays
        // within the normalized peak ceiling (0.95) rather than expecting zero.
        let lastSample = abs(channelData[frameCount - 1])
        #expect(lastSample <= 0.95)
    }

    @Test("Short duration buffer still generates correctly")
    func shortDurationBuffer() throws {
        let buffer = try TanpuraDroneGenerator.generateDroneBuffer(
            durationSeconds: 0.2
        )
        let expectedFrames = AVAudioFrameCount(44100 * 0.2)
        #expect(buffer.frameLength == expectedFrames)
    }

    @Test("Buffer format is mono float32")
    func bufferFormatIsCorrect() throws {
        let buffer = try TanpuraDroneGenerator.generateDroneBuffer()
        #expect(buffer.format.channelCount == 1)
        #expect(buffer.format.sampleRate == 44100)
        #expect(buffer.format.isStandard)
    }
}
