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

    /// Tempo rate clamp: 0.5× to 1.5×. AVAudioUnitTimePitch supports a
    /// much wider range (1/32 to 32) but anything outside this window is
    /// not useful for practice/audition.
    public static let minRate: Float = 0.5
    public static let maxRate: Float = 1.5

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

    /// Sequentially load `bankURL` into each sampler with the matching
    /// preset from `presets`. Pauses the engine, loads, restarts. Mode 2
    /// reload — single bank resident at a time, swap latency ~N × 300 ms.
    ///
    /// - Parameters:
    ///   - bankURL: SF2 file URL.
    ///   - presets: GM program numbers, one per sampler. Length must equal
    ///              `samplers.count`.
    /// - Throws: `PipelineError.engineNotRunning` or rethrows the underlying
    ///           AudioKit `loadMelodicSoundFont` failure.
    public func loadBank(at bankURL: URL, presets: [UInt8]) throws {
        precondition(presets.count == samplers.count,
                     "presets.count (\(presets.count)) must match samplers.count (\(samplers.count))")
        guard AudioEngineManager.shared.isRunning else {
            throw PipelineError.engineNotRunning
        }

        let needsAccess = bankURL.startAccessingSecurityScopedResource()
        defer { if needsAccess { bankURL.stopAccessingSecurityScopedResource() } }

        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }

        var loadError: Error?
        for (i, sampler) in samplers.enumerated() {
            do {
                try sampler.loadMelodicSoundFont(url: bankURL, preset: Int(presets[i]))
            } catch {
                loadError = error
                let msg = error.localizedDescription
                graphLogger.error(
                    """
                    Sampler \(i, privacy: .public) loadMelodicSoundFont \
                    failed: \(msg, privacy: .public)
                    """
                )
                break
            }
        }

        if wasRunning {
            do {
                try engine.start()
            } catch {
                graphLogger.error(
                    "Engine restart after bank load failed: \(error.localizedDescription, privacy: .public)"
                )
                throw error
            }
        }

        if let loadError {
            throw loadError
        }
    }

    /// Whether the sequencer is currently playing.
    public var isPlaying: Bool { sequencer?.isPlaying ?? false }

    /// Set playback tempo as a rate multiplier. Clamped to `[minRate, maxRate]`.
    /// Pitch is preserved (TimePitch overlap-add adds ~50–100 ms latency).
    public func setTempo(rate: Float) {
        let clamped = max(Self.minRate, min(Self.maxRate, rate))
        timePitch.rate = clamped
        graphLogger.info("setTempo rate=\(clamped, privacy: .public)")
    }

    /// Start sequencer playback. Throws underlying `AVAudioSequencer` error.
    public func play() throws {
        guard let sequencer else {
            throw PipelineError.engineNotRunning
        }
        try sequencer.start()
    }

    /// Pause without resetting position.
    public func pause() {
        sequencer?.stop()
    }

    /// Stop and reset to start.
    public func stop() {
        sequencer?.stop()
        sequencer?.currentPositionInSeconds = 0
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
