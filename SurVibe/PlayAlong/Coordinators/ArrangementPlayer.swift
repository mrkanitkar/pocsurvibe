// SurVibe/PlayAlong/Coordinators/ArrangementPlayer.swift
import Foundation
import SVAudio
import SVCore
import os

private let arrangementPlayerLogger = Logger.survibe(category: "ArrangementPlayer")

/// Practice mode for hand isolation in the Learn-a-Song play-along flow.
///
/// `.both` — both hands sound (default). `.rightHand` — learner is
/// practising the RH part; LH may be muted depending on `hearOtherHand`.
/// `.leftHand` — learner is practising the LH part; RH may be muted.
public nonisolated enum PracticeMode: String, Sendable, Equatable, CaseIterable {
    /// Both hands play through the accompaniment sampler.
    case both
    /// Learner is practising the right-hand staff.
    case rightHand
    /// Learner is practising the left-hand staff.
    case leftHand
}

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

    /// Active section-loop controller, or `nil` when looping is disabled.
    /// Set via `setLoop(_:)`.
    private var loopController: SectionLoopController?

    /// Tracks whether the loop has wrapped at least once. The first
    /// iteration of a loop plays whatever count-in was scheduled by
    /// `start(...)`; subsequent iterations skip count-in (no new clicks
    /// are scheduled on wrap).
    private var firstLoopIterationDone = false

    /// Hand-isolation practice mode. Setting this re-applies the muted
    /// track set via `graph.setMutedTracks(_:)`.
    ///
    /// Defaults to `.both` — no tracks muted, full accompaniment audible.
    public var practiceMode: PracticeMode = .both {
        didSet { applyHandMute() }
    }

    /// When `true` (default), both hands sound regardless of
    /// `practiceMode`. When `false`, the staff opposite the
    /// `practiceMode` is muted to let the learner play that part
    /// themselves.
    ///
    /// Setting this re-applies the muted track set via
    /// `graph.setMutedTracks(_:)`.
    public var hearOtherHand: Bool = true {
        didSet { applyHandMute() }
    }

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
        applyHandMute()
        arrangementPlayerLogger.info(
            "load: accompaniment bytes=\(split.accompaniment.count, privacy: .public)"
        )
    }

    // MARK: - Transport

    /// Begin playback at the given beat with an optional metronome
    /// count-in lead-in.
    ///
    /// When `countInBars > 0`, schedules `countInBars *
    /// learner.beatsPerMeasure` metronome clicks on GM percussion
    /// channel 9, at beat positions `atBeat - beats ..< atBeat`. The
    /// observable `currentBeat` is initialised to the leading edge of
    /// the count-in (`atBeat - beats`) so subsequent tick-driven
    /// updates can count up to `atBeat` (the "real" downbeat).
    ///
    /// If no `PartSplit` has been loaded yet, the call is a no-op.
    ///
    /// - Parameters:
    ///   - atBeat: Target start beat. Defaults to 0.
    ///   - countInBars: Number of count-in bars before `atBeat`.
    ///     Defaults to 1. Pass `0` to skip the lead-in.
    public func start(atBeat: Double = 0, countInBars: Int = 1) {
        guard let split else { return }
        let beats = max(0, countInBars) * split.learner.beatsPerMeasure
        if beats > 0 {
            for i in 0..<beats {
                let beatPos = atBeat - Double(beats - i)
                graph.scheduleMetronomeClick(at: beatPos, channel: 9)
            }
        }
        currentBeat = atBeat - Double(beats)
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

    // MARK: - Section Loop (C3)

    /// Enable or disable section looping.
    ///
    /// When a non-nil `region` is supplied, playback will seek back to
    /// the start of `region` once `currentBeat` reaches or passes the
    /// end of `region`. Passing `nil` clears looping. Loop boundaries
    /// are computed from the loaded `PartSplit`'s
    /// `learner.beatsPerMeasure`; calling `setLoop` before `load(_:)`
    /// is a no-op.
    ///
    /// The first loop iteration plays whatever count-in was scheduled
    /// by `start(...)`; subsequent iterations skip count-in (no new
    /// metronome clicks are scheduled when wrapping).
    ///
    /// - Parameter region: The loop region, or `nil` to disable looping.
    public func setLoop(_ region: LoopRegion?) {
        guard let split else {
            loopController = nil
            return
        }
        if let region {
            loopController = SectionLoopController(
                region: region,
                beatsPerMeasure: split.learner.beatsPerMeasure
            )
            firstLoopIterationDone = false
        } else {
            loopController = nil
        }
    }

    /// Per-tick wrap check. Called from a display-link-driven beat
    /// updater (Task C5) and from the test seam `simulateBeatTick`.
    ///
    /// If looping is enabled and `currentBeat` has reached the end of
    /// the loop region, seek the graph back to the start of the region
    /// and update `currentBeat` to match. No new count-in is scheduled
    /// on wrap.
    private func tick() {
        guard isPlaying else { return }
        if let lc = loopController, lc.shouldWrap(currentBeat: currentBeat) {
            graph.seek(toBeat: lc.startBeat)
            currentBeat = lc.startBeat
            firstLoopIterationDone = true
        }
    }

    // MARK: - Test Seam

    /// Test-only seam used by `ArrangementPlayerTests` to simulate the
    /// playback driver advancing `currentBeat`. Production code uses
    /// the C5 display-link driver instead.
    ///
    /// `beatsPerMeasure` is accepted for parity with the plan signature
    /// but is unused by the seam — the active `SectionLoopController`
    /// already carries the bpm captured from the loaded `PartSplit`.
    ///
    /// - Parameters:
    ///   - beatsPerMeasure: Unused; accepted for plan-signature parity.
    ///   - newBeat: The beat to set as `currentBeat` before running the
    ///     loop wrap check.
    internal func simulateBeatTick(beatsPerMeasure: Int, currentBeat newBeat: Double) {
        _ = beatsPerMeasure
        self.currentBeat = newBeat
        tick()
    }

    // MARK: - Hand isolation (C4)

    /// Recompute the muted-track set from `practiceMode` + `hearOtherHand`
    /// and forward to the graph.
    ///
    /// Called from the `didSet` of either property and from `load(_:)`
    /// after the graph has the SMF. When `hearOtherHand` is `true` or
    /// `practiceMode` is `.both`, the muted set is empty.
    private func applyHandMute() {
        guard let split else {
            graph.setMutedTracks([])
            return
        }
        var muted: Set<Int> = []
        if !hearOtherHand {
            let mutedRole: HandRole? =
                switch practiceMode {
                case .leftHand: .rightHand
                case .rightHand: .leftHand
                case .both: nil
                }
            if let role = mutedRole {
                muted = trackIndicesFor(role: role, in: split)
            }
        }
        graph.setMutedTracks(muted)
    }

    /// Map a `HandRole` to the set of accompaniment-sequencer track
    /// indices that carry that staff's notes.
    ///
    /// **v1 limitation:** most piano scores have a single learner MIDI
    /// track with notes spanning two staves (RH = treble, LH = bass).
    /// Verovio does not split that into two MTrk chunks, so muting LH
    /// at the track level only works when the source SMF already
    /// separates hands into distinct tracks. Pitch-based filtering
    /// (split-by-middle-C) is a future enhancement.
    ///
    /// Algorithm:
    /// - If `learnerStaves.count == learnerTrackIndices.count`, zip
    ///   them and pick indices whose paired staff has the requested
    ///   role.
    /// - Else fall back to the heuristic: when there are exactly two
    ///   learner tracks, treat `[0]` as RH and `[1]` as LH.
    /// - Otherwise return an empty set.
    private func trackIndicesFor(role: HandRole, in split: PartSplit) -> Set<Int> {
        let staves = split.learnerStaves
        let indices = split.learnerTrackIndices
        if staves.count == indices.count, !staves.isEmpty {
            return Set(zip(staves, indices).filter { $0.0.role == role }.map { $0.1 })
        }
        // Fallback heuristic: two learner tracks → first=RH, second=LH.
        if indices.count == 2 {
            switch role {
            case .rightHand: return [indices[0]]
            case .leftHand: return [indices[1]]
            case .singleStaff: return []
            }
        }
        return []
    }
}
