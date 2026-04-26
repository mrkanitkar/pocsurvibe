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

    /// The sequencer that drives the samplers. nil until `loadMIDI(_:)` is called.
    public private(set) var sequencer: AVAudioSequencer?

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

    /// Load `RenderedMIDI` into a fresh `AVAudioSequencer` and route each
    /// track to the matching sampler by **track index** (not by MIDI channel,
    /// because `destinationMIDIEndpoint` does not channel-filter — all events
    /// on a track flow to the assigned destination regardless of channel byte).
    ///
    /// - Parameter rendered: Output of `VerovioBridge.render(...)`.
    /// - Throws: `PipelineError.engineNotRunning` if the shared engine stopped.
    ///           Underlying `AVAudioSequencer` errors on malformed MIDI bytes.
    public func loadMIDI(_ rendered: RenderedMIDI) throws {
        guard AudioEngineManager.shared.isRunning else {
            throw PipelineError.engineNotRunning
        }
        let seq = AVAudioSequencer(audioEngine: engine)
        try seq.load(from: rendered.data, options: [])

        let trackCount = min(seq.tracks.count, samplers.count)
        for i in 0..<trackCount {
            seq.tracks[i].destinationMIDIEndpoint = samplers[i].midiIn
        }
        self.sequencer = seq
        let seqTracks = seq.tracks.count
        let samplerCount = self.samplers.count
        graphLogger.info(
            """
            Loaded MIDI: seq tracks=\(seqTracks, privacy: .public) \
            samplers=\(samplerCount, privacy: .public) \
            routed=\(trackCount, privacy: .public)
            """
        )
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
