import AVFoundation
import AudioKit
import Foundation
import os

private let appleEngineLogger = Logger.survibe(category: "AppleAVSamplerEngine")

/// `AuditionEngine` adapter around the existing `MultiTrackSamplerGraph`.
/// Preserves the graph unchanged; this wrapper just translates the protocol's
/// call shape into the graph's existing methods. The graph already owns its
/// own samplers, sub-mixer, sequencer, and CoreMIDI routing — we delegate.
@MainActor
public final class AppleAVSamplerEngine: AuditionEngine {

    /// Picker label sourced from `EngineKind.apple.displayName`.
    public var displayName: String { EngineKind.apple.displayName }

    /// The `subMixer` of the underlying graph once `setup` has run; otherwise
    /// a placeholder mixer so callers can bind to a stable node.
    public var output: AVAudioNode { graph?.subMixer ?? placeholderMixer }

    /// Whether the underlying graph's sequencer is currently producing audio.
    public var isPlaying: Bool { graph?.isPlaying ?? false }

    /// Wall-clock duration of the loaded sequence (longest non-empty track).
    public var sequenceDuration: TimeInterval {
        guard let tracks = graph?.sequencer?.tracks, !tracks.isEmpty else { return 0 }
        return tracks.map(\.lengthInSeconds).max() ?? 0
    }

    private var graph: MultiTrackSamplerGraph?
    private var rendered: RenderedMIDI?
    /// Returned from `output` before `setup` runs so SwiftUI bindings have
    /// something stable to point at. Never connected to the engine.
    private let placeholderMixer = AVAudioMixerNode()

    /// Creates an engine in a clean, not-set-up state. Callers must invoke
    /// `setup(rendered:bankURL:)` before `play()`.
    public init() {}

    /// Allocates samplers for each music track in `rendered`, loads `bankURL`
    /// using per-track GM programs, and routes the rendered MIDI into the
    /// underlying graph's sequencer.
    public func setup(rendered: RenderedMIDI, bankURL: URL) throws {
        self.rendered = rendered
        let trackCount = min(rendered.trackInfo.count, MultiTrackSamplerGraph.maxTracks)
        let graph = try MultiTrackSamplerGraph(trackCount: trackCount)
        let presets = derivedPresets(rendered: rendered, samplerCount: trackCount)
        try graph.loadBank(at: bankURL, presets: presets)
        try graph.loadMIDI(rendered)
        self.graph = graph
        appleEngineLogger.info(
            "setup: trackCount=\(trackCount, privacy: .public) bank=\(bankURL.lastPathComponent, privacy: .public)"
        )
        PipelineFileLog.shared.log(
            "AppleAVSamplerEngine.setup: trackCount=\(trackCount) bank=\(bankURL.lastPathComponent)"
        )
    }

    /// Swaps the loaded SF2 to a new bank, reusing the per-track GM programs
    /// captured in the previous `setup`. No-op if `setup` has not yet run.
    public func loadBank(_ bankURL: URL) throws {
        guard let graph, let rendered else { return }
        let presets = derivedPresets(rendered: rendered, samplerCount: graph.samplers.count)
        try graph.loadBank(at: bankURL, presets: presets)
        PipelineFileLog.shared.log(
            "AppleAVSamplerEngine.loadBank: \(bankURL.lastPathComponent)"
        )
    }

    /// Starts the underlying graph's sequencer.
    public func play() throws {
        try graph?.play()
        PipelineFileLog.shared.log("AppleAVSamplerEngine.play")
    }

    /// Pauses the underlying graph's sequencer without resetting position.
    public func pause() {
        graph?.pause()
        PipelineFileLog.shared.log("AppleAVSamplerEngine.pause")
    }

    /// Stops the underlying graph's sequencer and resets to the start.
    public func stop() {
        graph?.stop()
        PipelineFileLog.shared.log("AppleAVSamplerEngine.stop")
    }

    /// Delegates the rate change to the graph's `AVAudioUnitTimePitch`.
    public func setTempo(rate: Float) {
        graph?.setTempo(rate: rate)
    }

    /// Detaches the underlying graph from the shared engine. Idempotent.
    public func tearDown() {
        graph?.stop()
        graph?.teardown()
        graph = nil
        rendered = nil
        PipelineFileLog.shared.log("AppleAVSamplerEngine.tearDown")
    }

    /// One-line snapshot of the engine state for `pipeline_log.txt`.
    public func diagnosticSummary() -> String {
        guard let graph else { return "AppleAVSamplerEngine: not set up" }
        return "AppleAVSamplerEngine: samplers=\(graph.samplers.count) playing=\(graph.isPlaying)"
    }

    // MARK: - Private helpers

    /// Derives per-sampler GM presets from `rendered.trackInfo`. Falls back
    /// to GM 0 (Acoustic Grand) if a track didn't include a Program Change.
    private func derivedPresets(rendered: RenderedMIDI, samplerCount: Int) -> [UInt8] {
        var result: [UInt8] = []
        for index in 0..<samplerCount {
            if index < rendered.trackInfo.count, let program = rendered.trackInfo[index].program {
                result.append(program)
            } else {
                result.append(0)
            }
        }
        return result
    }
}
