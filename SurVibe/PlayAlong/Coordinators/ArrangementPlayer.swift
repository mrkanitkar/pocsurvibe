// SurVibe/PlayAlong/Coordinators/ArrangementPlayer.swift
import Foundation
import SVAudio
import SVCore
import os

private let arrangementPlayerLogger = Logger.survibe(category: "ArrangementPlayer")

/// Coordinates the accompaniment sequencer for the Learn-a-Song play-along
/// flow. Wraps `MultiTrackSamplerGraphProtocol` and exposes transport
/// (start / pause / resume / stop), tempo scaling, and observable state
/// (`isPlaying`, `currentBeat`, `startHostTime`).
///
/// This is the C1 base. Subsequent tasks layer count-in (C2), loop
/// punch-in/out (C3), and per-staff hand isolation (C4) on top.
@Observable
@MainActor
public final class ArrangementPlayer {

    // MARK: - Properties

    private let graph: MultiTrackSamplerGraphProtocol

    /// Whether the player is enabled. Future tasks (C4) toggle this for
    /// hand-isolation muting; C1 leaves it `true`.
    public private(set) var isEnabled = true

    /// Whether the underlying sequencer is playing. Mirrors transport
    /// calls (`start` / `pause` / `resume` / `stop`).
    public private(set) var isPlaying = false

    /// Current beat in song time. Always 0 in C1 — count-in (C2) makes
    /// this transiently negative during the lead-in bars and the playback
    /// driver (C5) advances it during playback.
    public private(set) var currentBeat: Double = 0

    /// Host time captured when `start()` was called. `nil` until `start()`
    /// has been invoked at least once. Used by downstream consumers
    /// (visual sync, scoring) to align with `mach_absolute_time()` clocks.
    public private(set) var startHostTime: HostTime?

    /// The currently loaded part split, or `nil` if `load(_:)` has not
    /// yet been called. Kept private — callers should consult the graph
    /// or the originating split source.
    private var split: PartSplit?

    // MARK: - Initialization

    /// Create an `ArrangementPlayer` over a graph instance.
    ///
    /// - Parameter graph: The sampler graph to drive. Tests inject a mock
    ///   conforming to `MultiTrackSamplerGraphProtocol`; production code
    ///   passes a real `MultiTrackSamplerGraph` instance.
    public init(graph: MultiTrackSamplerGraphProtocol) {
        self.graph = graph
    }

    // MARK: - Loading

    /// Load a `PartSplit` into the underlying graph.
    ///
    /// Wraps `split.accompaniment` (raw SMF bytes) into a `RenderedMIDI`
    /// before handing it to `graph.loadMIDI(_:)`. The synthetic
    /// `RenderedMIDI` carries empty `trackInfo` and a placeholder
    /// `originalBPM` of 120 — neither field is consulted by the
    /// `AVAudioSequencer.load(from:options:)` path; only the SMF byte
    /// stream is parsed. After load, tempo scale is reset to 1.0.
    ///
    /// - Parameter split: The learner / accompaniment split produced by
    ///   `PartSplitter`.
    /// - Throws: Underlying `PipelineError` from
    ///   `MultiTrackSamplerGraph.loadMIDI(_:)`.
    public func load(_ split: PartSplit) async throws {
        self.split = split
        let rendered = RenderedMIDI(
            data: split.accompaniment,
            trackCount: 0,
            channels: [],
            trackInfo: [],
            originalBPM: 120.0
        )
        try graph.loadMIDI(rendered)
        graph.setTempoScale(1.0)
        arrangementPlayerLogger.info(
            "load: accompaniment bytes=\(split.accompaniment.count, privacy: .public)"
        )
    }

    // MARK: - Transport

    /// Begin playback at the given beat.
    ///
    /// In C1 this captures `startHostTime`, calls `graph.play()`, and
    /// flips `isPlaying` to `true`. Count-in scheduling (C2) and seek
    /// support layer on top — for now `atBeat` and `countInBars` are
    /// accepted parameters but their bodies are deferred to C2.
    ///
    /// - Parameters:
    ///   - atBeat: Target start beat. Currently unused; reserved for C2.
    ///   - countInBars: Number of count-in bars before song beat 0.
    ///     Currently unused; reserved for C2.
    public func start(atBeat: Double = 0, countInBars: Int = 1) {
        _ = atBeat
        _ = countInBars
        startHostTime = HostTime.now()
        do {
            try graph.play()
            isPlaying = true
        } catch {
            arrangementPlayerLogger.error(
                "start: graph.play() failed: \(error.localizedDescription, privacy: .public)"
            )
            isPlaying = false
        }
    }

    /// Pause playback without resetting position.
    public func pause() {
        graph.pause()
        isPlaying = false
    }

    /// Resume playback from the current position.
    public func resume() {
        do {
            try graph.resume()
            isPlaying = true
        } catch {
            arrangementPlayerLogger.error(
                "resume: graph.resume() failed: \(error.localizedDescription, privacy: .public)"
            )
            isPlaying = false
        }
    }

    /// Stop playback and reset position to the start.
    public func stop() {
        graph.stop()
        isPlaying = false
    }

    // MARK: - Tempo

    /// Forward a tempo scale factor to the sampler graph. Clamped to the
    /// graph's supported range (0.5–1.5).
    ///
    /// - Parameter rate: Tempo multiplier (1.0 = original tempo).
    public func setTempoScale(_ rate: Float) {
        graph.setTempoScale(rate)
    }
}
