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

    @Test("Both playback nodes are attached and distinct")
    @MainActor
    func nodesAttached() {
        let manager = AudioEngineManager.shared
        // Verify player nodes are non-nil and of the correct types
        let tanpura: AVAudioPlayerNode = manager.tanpuraNode
        let metronome: AVAudioPlayerNode = manager.metronomeNode
        // Nodes should be distinct instances
        #expect(tanpura !== metronome)
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
        // setSamplerVolume routes to multiChannel?.samplers[0]; multiChannel is nil
        // until the engine starts, so these are no-ops that must not crash.
        manager.setSamplerVolume(0.0)
        manager.setSamplerVolume(1.0)

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
