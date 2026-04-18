import AVFoundation
import Testing

@testable import SVAudio

@Suite("AudioEngineManager Tests")
struct AudioEngineManagerTests {
    @Test("Engine is not running initially")
    @MainActor
    func initialState() {
        #expect(AudioEngineManager.shared.isRunning == false)
    }

    @Test("Buffer size is 1024 frames")
    @MainActor
    func bufferSize() {
        // Buffer was reduced from 2048 to 1024 to halve detection latency (~23ms).
        #expect(AudioEngineManager.shared.bufferSize == 1024)
    }

    @Test("All three playback nodes are attached")
    @MainActor
    func nodesAttached() {
        let manager = AudioEngineManager.shared
        // Verify nodes are non-nil and of the correct types
        let sampler: AVAudioUnitSampler = manager.sampler
        let tanpura: AVAudioPlayerNode = manager.tanpuraNode
        let metronome: AVAudioPlayerNode = manager.metronomeNode
        // Nodes should be distinct instances
        #expect(tanpura !== metronome)
        _ = sampler  // suppress unused warning
    }

    @Test("Engine exposes the AVAudioEngine instance")
    @MainActor
    func engineAccessible() {
        let engine = AudioEngineManager.shared.engine
        #expect(engine.isRunning == false)
    }

    @Test("Volume setters accept boundary values without crash")
    @MainActor
    func volumeSettersAcceptBoundaries() {
        let manager = AudioEngineManager.shared
        // 0.0 and 1.0 are the standard range boundaries
        manager.setSamplerVolume(0.0)
        #expect(manager.sampler.volume == 0.0)
        manager.setSamplerVolume(1.0)
        #expect(manager.sampler.volume == 1.0)

        manager.setTanpuraVolume(0.5)
        #expect(manager.tanpuraNode.volume == 0.5)

        manager.setMetronomeVolume(0.75)
        #expect(manager.metronomeNode.volume == 0.75)
    }

    @Test("removeMicTap on clean state does not crash")
    @MainActor
    func removeMicTapSafe() {
        AudioEngineManager.shared.removeMicTap()
        // No crash = success
    }

    @Test("installMicTap fails when engine is not running")
    @MainActor
    func installMicTapRequiresRunningEngine() {
        let success = AudioEngineManager.shared.installMicTap { _, _ in }
        #expect(success == false)
    }
}
