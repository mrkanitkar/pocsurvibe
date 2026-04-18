import Testing
@testable import SVAudio

@Suite("AudioConfig Tests")
struct AudioConfigTests {
    @Test("Default config uses 44100 Hz sample rate")
    func testDefaultSampleRate() {
        let config = AudioConfig()
        #expect(config.sampleRate == 44100)
    }

    @Test("Default buffer size is 1024")
    func testDefaultBufferSize() {
        let config = AudioConfig()
        // Buffer was reduced from 2048 to 1024 to halve detection latency (~23ms).
        #expect(config.bufferSize == 1024)
    }

    @Test("Default latency is approximately 23ms")
    func testDefaultLatency() {
        let config = AudioConfig()
        // 1024 / 44100 * 1000 ≈ 23.22 ms
        #expect(config.latencyMs > 23.0 && config.latencyMs < 24.0)
    }

    @Test("Pitch detection config matches defaults")
    func testPitchDetectionConfig() {
        let config = AudioConfig.pitchDetection
        // Default buffer is 1024 (reduced from 2048 for lower latency).
        #expect(config.bufferSize == 1024)
        #expect(config.sampleRate == 44100)
        #expect(config.channelCount == 1)
    }
}
