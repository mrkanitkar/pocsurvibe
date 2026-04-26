import AVFoundation
import AudioKit
import Testing

@testable import SVAudio

@Suite("MultiTrackSamplerGraph — graph topology")
@MainActor
struct MultiTrackSamplerGraphTests {

    @Test("Attaches N samplers + sub-mixer + TimePitch to engine")
    func attachesNodes() throws {
        try AudioEngineManager.shared.startForPlayback()
        let engine = AudioEngineManager.shared.engine
        let baselineNodes = countAttachedNodes(in: engine)

        let graph = try MultiTrackSamplerGraph(trackCount: 3)

        // Expect: +3 samplers, +1 sub-mixer, +1 TimePitch = +5 nodes.
        #expect(countAttachedNodes(in: engine) == baselineNodes + 5)

        graph.teardown()
        #expect(countAttachedNodes(in: engine) == baselineNodes)
    }

    @Test("Throws .tooManyTracks when N > 16")
    func capsAt16() throws {
        try AudioEngineManager.shared.startForPlayback()
        #expect(throws: PipelineError.self) {
            _ = try MultiTrackSamplerGraph(trackCount: 17)
        }
    }

    @Test("Throws .engineNotRunning when engine is stopped")
    func requiresRunningEngine() throws {
        AudioEngineManager.shared.stop()
        #expect(throws: PipelineError.self) {
            _ = try MultiTrackSamplerGraph(trackCount: 2)
        }
    }

    private func countAttachedNodes(in engine: AVAudioEngine) -> Int {
        // AVAudioEngine doesn't expose node count directly; use the
        // attachedNodes count via the private `attachedNodes` set is
        // not stable. Use mainMixer's input-bus count as a proxy.
        engine.mainMixerNode.numberOfInputs
    }
}
