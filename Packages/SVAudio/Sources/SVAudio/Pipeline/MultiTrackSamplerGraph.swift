import AVFoundation
import AudioKit
import Foundation
import os

private let graphLogger = Logger.survibe(category: "MultiTrackSamplerGraph")

/// Multi-channel sampler graph for the audition `.mxl` pipeline.
///
/// Topology:
/// ```
/// MIDISampler[0]  ─┐
/// MIDISampler[1]  ─┼──▶ AuditionSubMixer ──▶ TimePitch ──▶ engine.mainMixerNode
/// MIDISampler[N-1]─┘
/// ```
///
/// The sub-mixer isolates audition processing from the rest of the
/// app's audio (tanpura, metronome, production sampler, mic).
/// The TimePitch node lets us scale tempo (rate 0.5–1.5×) without
/// pitch shifting.
@MainActor
public final class MultiTrackSamplerGraph {

    /// MIDI hard cap — 16 channels per port; full orchestral scores
    /// exceed this and require sub-mixing (out of POC scope).
    public static let maxTracks = 16

    public let samplers: [MIDISampler]
    public let subMixer: AVAudioMixerNode
    public let timePitch: AVAudioUnitTimePitch

    private let engine: AVAudioEngine

    /// Build the graph and attach it to `AudioEngineManager.shared.engine`.
    ///
    /// - Parameter trackCount: Number of samplers to create (1 ... 16).
    /// - Throws: `.tooManyTracks` if `trackCount > 16`,
    ///           `.engineNotRunning` if the shared engine is stopped.
    public init(trackCount: Int) throws {
        guard trackCount >= 1, trackCount <= Self.maxTracks else {
            throw PipelineError.tooManyTracks(found: trackCount, max: Self.maxTracks)
        }
        guard AudioEngineManager.shared.isRunning else {
            throw PipelineError.engineNotRunning
        }
        self.engine = AudioEngineManager.shared.engine

        // Build samplers
        var samplers: [MIDISampler] = []
        for i in 0..<trackCount {
            let sampler = MIDISampler(name: "AuditionPipeline_\(i)")
            engine.attach(sampler.avAudioNode)
            samplers.append(sampler)
        }
        self.samplers = samplers

        // Build sub-mixer + TimePitch
        let subMixer = AVAudioMixerNode()
        let timePitch = AVAudioUnitTimePitch()
        engine.attach(subMixer)
        engine.attach(timePitch)
        self.subMixer = subMixer
        self.timePitch = timePitch

        // Wire: each sampler → sub-mixer → timePitch → mainMixer
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        for sampler in samplers {
            engine.connect(sampler.avAudioNode, to: subMixer, format: format)
        }
        engine.connect(subMixer, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)

        graphLogger.info("Attached \(trackCount, privacy: .public) samplers + sub-mixer + TimePitch")
    }

    /// Detach all pipeline nodes from the shared engine. Idempotent.
    public func teardown() {
        engine.disconnectNodeOutput(timePitch)
        engine.disconnectNodeOutput(subMixer)
        for sampler in samplers {
            engine.disconnectNodeOutput(sampler.avAudioNode)
        }
        engine.detach(timePitch)
        engine.detach(subMixer)
        for sampler in samplers {
            engine.detach(sampler.avAudioNode)
        }
        graphLogger.info("Detached pipeline nodes")
    }

    deinit {
        // teardown() must be called explicitly on @MainActor; the deinit
        // cannot safely touch @MainActor state. The audition section view
        // owns the lifecycle and calls teardown() in onDisappear.
    }
}
