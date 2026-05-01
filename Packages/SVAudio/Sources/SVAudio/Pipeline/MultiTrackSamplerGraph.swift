import AVFoundation
import AudioKit
import Foundation
import os

private let graphLogger = Logger.survibe(category: "MultiTrackSamplerGraph")

/// Abstraction over `MultiTrackSamplerGraph` for testability.
///
/// `ArrangementPlayer` (Wave 3) depends on this protocol so tests can
/// inject a mock graph without spinning up AVAudioEngine.
@MainActor
public protocol MultiTrackSamplerGraphProtocol: AnyObject, Sendable {
    /// Load rendered MIDI data into the sequencer and route tracks.
    func loadMIDI(_ rendered: RenderedMIDI) throws
    /// Scale playback tempo via `AVAudioSequencer.rate`. Clamped to 0.5–1.5.
    func setTempoScale(_ rate: Float)
    /// Start sequencer playback.
    func play() throws
    /// Pause without resetting position.
    func pause()
    /// Stop and reset to start.
    func stop()
    /// Resume playback from current position (alias for `play()` when paused).
    func resume() throws
    /// Seek to a specific beat position.
    func seek(toBeat beat: Double)
    /// Mute specific track sampler outputs by index.
    func setMutedTracks(_ indices: Set<Int>)
    /// Schedule a MIDI note-on event for the metronome click at the given beat.
    func scheduleMetronomeClick(at beat: Double, channel: UInt8)
    /// Current playback position in beats.
    var currentPositionInBeats: Double { get }
    /// Whether the sequencer is currently playing.
    var isPlaying: Bool { get }
}

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
/// TimePitch is kept as a 1.0 passthrough for pitch preservation;
/// tempo scaling uses `AVAudioSequencer.rate` to avoid the 50–100 ms
/// overlap-add DSP latency that `timePitch.rate` introduces.
@MainActor
public final class MultiTrackSamplerGraph: MultiTrackSamplerGraphProtocol {

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

        // Per-instance identifier embedded in every sampler's name. Each
        // MIDISampler creates a CoreMIDI virtual MIDI destination whose
        // identity is keyed off `name`. Reusing the same names across
        // graph teardown→rebuild cycles (e.g. mid-playback song switch)
        // can cause new samplers to inherit a stale endpoint registration
        // from the prior cycle's detached samplers, with audible "single-
        // pipe" / muted-voice symptoms. A fresh UUID per graph guarantees
        // the new virtual destinations have never existed before.
        let instanceId = UUID().uuidString.prefix(8)
        var samplers: [MIDISampler] = []
        for i in 0..<trackCount {
            let sampler = MIDISampler(name: "AuditionPipeline_\(instanceId)_\(i)")
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

        let fmtSR = format.sampleRate
        let fmtCH = format.channelCount
        graphLogger.info("Attached \(trackCount, privacy: .public) samplers + sub-mixer + TimePitch")
        PipelineFileLog.shared.log(
            """
            MultiTrackSamplerGraph.init: trackCount=\(trackCount) \
            format=\(fmtSR)Hz/\(fmtCH)ch attached samplers=\(samplers.count) \
            instance=\(instanceId)
            """
        )
    }

    /// Load `RenderedMIDI` into a fresh `AVAudioSequencer` and route each
    /// track to the matching sampler by **track index** (not by MIDI channel,
    /// because `destinationMIDIEndpoint` does not channel-filter — all events
    /// on a track flow to the assigned destination regardless of channel byte).
    ///
    /// `RenderedMIDI.trackInfo[i]` is documented to align 1:1 with
    /// `AVAudioSequencer.tracks[i]` (Verovio excludes the conductor track from
    /// `trackInfo`, and Apple's `AVAudioSequencer.tracks` excludes the tempo
    /// track per the framework header). When the alignment holds — which is
    /// the common case — `samplers[i]` was already pre-banked from
    /// `trackInfo[i].program` by `loadBank(at:presets:)`, so index-based
    /// routing puts the right instrument on the right track.
    ///
    /// **Off-by-one defense (T3'):** when the source MIDI has fewer parts
    /// than expected and `seq.tracks.count != trackInfo.count`, the previous
    /// implementation silently routed the trailing tracks to mis-banked
    /// samplers. We now emit:
    ///   * `GRAPH-ROUTE track=<i> program=<p> sampler=<idx>` per routed track
    ///     (`p=0` fallback when `trackInfo[i]` is missing or its program is
    ///     `nil`, matching `derivedPresets` in `AuditionPipelineSection`).
    ///   * `GRAPH-ROUTE-MISMATCH seq=<n> info=<m>` when the count alignment
    ///     breaks, so audio_log captures the failure mode end-to-end.
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

        let seqTracks = seq.tracks.count
        let samplerCount = self.samplers.count
        let infoCount = rendered.trackInfo.count

        // Surface the count-alignment problem before we route. When this
        // fires, the trailing tracks beyond `min(infoCount, seqTracks)` will
        // fall back to program 0 (Acoustic Grand) for the GRAPH-ROUTE log
        // and inherit whatever preset was loaded into that sampler slot.
        if seqTracks != infoCount {
            graphLogger.warning(
                """
                GRAPH-ROUTE-MISMATCH seq=\(seqTracks, privacy: .public) \
                info=\(infoCount, privacy: .public)
                """
            )
            PipelineFileLog.shared.log(
                "GRAPH-ROUTE-MISMATCH seq=\(seqTracks) info=\(infoCount)"
            )
        }

        let trackCount = min(seqTracks, samplerCount)
        for i in 0..<trackCount {
            seq.tracks[i].destinationMIDIEndpoint = samplers[i].midiIn

            // Resolve the program that was pre-banked into this sampler slot
            // via `RenderedMIDI.trackInfo[i].program`. Falls back to GM 0
            // (Acoustic Grand) when trackInfo is short or the entry has no
            // Program Change — same fallback as `derivedPresets` so the log
            // matches what `loadBank(at:presets:)` actually loaded.
            let program: UInt8 = (i < infoCount)
                ? (rendered.trackInfo[i].program ?? 0)
                : 0
            graphLogger.info(
                """
                GRAPH-ROUTE track=\(i, privacy: .public) \
                program=\(program, privacy: .public) \
                sampler=\(i, privacy: .public)
                """
            )
            PipelineFileLog.shared.log(
                "GRAPH-ROUTE track=\(i) program=\(program) sampler=\(i)"
            )

            // Diagnostic: per-track length so we can see whether a track
            // is empty/short and that's why playback stops early.
            let t = seq.tracks[i]
            let lenBeats = t.lengthInBeats
            let lenSec = t.lengthInSeconds
            graphLogger.info(
                """
                track[\(i, privacy: .public)] \
                lenBeats=\(lenBeats, privacy: .public) \
                lenSec=\(lenSec, privacy: .public)
                """
            )
            PipelineFileLog.shared.log(
                "  track[\(i)] lenBeats=\(lenBeats) lenSec=\(lenSec)"
            )
        }
        self.sequencer = seq
        let tempoLen = seq.tempoTrack.lengthInSeconds
        graphLogger.info(
            """
            Loaded MIDI: seq tracks=\(seqTracks, privacy: .public) \
            samplers=\(samplerCount, privacy: .public) \
            routed=\(trackCount, privacy: .public) \
            tempoLen=\(tempoLen, privacy: .public)s
            """
        )
        PipelineFileLog.shared.log(
            """
            MultiTrackSamplerGraph.loadMIDI: seq.tracks=\(seqTracks) \
            samplers=\(samplerCount) routed=\(trackCount) tempoLen=\(tempoLen)s
            """
        )
    }

    /// URL of the bundled `MuseScore_General.sf2` SoundFont — the
    /// production bank used historically by Play tab.
    public static var bundledMuseScoreGeneralSF2URL: URL? {
        Bundle.module.url(forResource: "MuseScore_General", withExtension: "sf2")
    }

    /// URL of the bundled `GeneralUser-GS.sf2` — diagnostics-only.
    ///
    /// Production never resolves to this bank (`activeSoundFontURL` returns
    /// `MuseScore_General.sf2` exclusively). Kept exposed solely so the
    /// DEBUG-only audition view can preload it into slot B for A/B
    /// comparison against the production bank. Lives in `Bundle.main`
    /// (the diagnostics asset folder); excluded from Release builds via
    /// target membership.
    public static var bundledGeneralUserGSSF2URL: URL? {
        Bundle.main.url(forResource: "GeneralUser-GS", withExtension: "sf2")
    }

    /// Resolve the SoundFont URL for the active production bank.
    ///
    /// Production ships a single canonical bank: `MuseScore_General.sf2`
    /// in the SVAudio package resources (`Bundle.module`). No fallback,
    /// no user preference, no alternative bank.
    public static func activeSoundFontURL() -> URL? {
        bundledMuseScoreGeneralSF2URL
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

        let bankName = bankURL.lastPathComponent
        let presetList = presets.map { String($0) }.joined(separator: ",")
        graphLogger.info(
            """
            loadBank: bank=\(bankName, privacy: .public) \
            samplers=\(self.samplers.count, privacy: .public) \
            presets=\(presetList, privacy: .public)
            """
        )
        PipelineFileLog.shared.log(
            "MultiTrackSamplerGraph.loadBank: bank=\(bankName) presets=[\(presetList)]"
        )
        var loadError: Error?
        for (i, sampler) in samplers.enumerated() {
            do {
                try sampler.loadMelodicSoundFont(url: bankURL, preset: Int(presets[i]))
                let p = presets[i]
                graphLogger.info(
                    "loadBank: sampler[\(i, privacy: .public)] preset=\(p, privacy: .public) OK"
                )
                PipelineFileLog.shared.log("  sampler[\(i)] preset=\(p) loaded OK")
            } catch {
                loadError = error
                let msg = error.localizedDescription
                graphLogger.error(
                    """
                    Sampler \(i, privacy: .public) loadMelodicSoundFont \
                    failed: \(msg, privacy: .public)
                    """
                )
                PipelineFileLog.shared.log("  sampler[\(i)] LOAD FAILED: \(msg)")
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

    // MARK: - Transport State

    /// Whether the sequencer is currently playing.
    public var isPlaying: Bool { sequencer?.isPlaying ?? false }

    /// Current playback position in beats.
    public var currentPositionInBeats: Double {
        sequencer?.currentPositionInBeats ?? 0
    }

    #if DEBUG
    /// Test seam: current `AVAudioSequencer.rate` value.
    public var sequencerRate: Float { sequencer?.rate ?? 1.0 }
    /// Test seam: current `AVAudioUnitTimePitch.rate` value.
    public var timePitchRate: Float { timePitch.rate }
    #endif

    // MARK: - Tempo

    /// Scale playback tempo via `AVAudioSequencer.rate`.
    ///
    /// Uses the sequencer's native rate scaling which adjusts the MIDI
    /// timeline directly, avoiding the 50–100 ms overlap-add DSP latency
    /// that `AVAudioUnitTimePitch.rate` introduces. `timePitch` stays at
    /// 1.0 as a passthrough. Clamped to `[minRate, maxRate]`.
    ///
    /// - Parameter rate: Tempo multiplier (0.5 = half speed, 1.5 = 1.5x).
    public func setTempoScale(_ rate: Float) {
        let clamped = max(Self.minRate, min(Self.maxRate, rate))
        sequencer?.rate = clamped
        // timePitch stays at 1.0 — no time-stretch DSP on the audio path
        graphLogger.info("setTempoScale rate=\(clamped, privacy: .public)")
    }

    // MARK: - Transport Controls

    /// Start sequencer playback. Throws underlying `AVAudioSequencer` error.
    ///
    /// - Throws: `PipelineError.engineNotRunning` if no sequencer is loaded.
    public func play() throws {
        guard let sequencer else {
            MultiChannelLog.shared.log(.error, "GRAPH-PLAY no sequencer loaded — throwing engineNotRunning")
            throw PipelineError.engineNotRunning
        }
        sequencer.prepareToPlay()
        try sequencer.start()
        let pos = sequencer.currentPositionInSeconds
        let playing = sequencer.isPlaying
        let engineRunning = engine.isRunning
        let trackCount = sequencer.tracks.count
        let mainOutputVol = engine.mainMixerNode.outputVolume
        let samplerCount = samplers.count
        graphLogger.info(
            "play: pos=\(pos, privacy: .public)s isPlaying=\(playing, privacy: .public)"
        )
        PipelineFileLog.shared.log(
            "MultiTrackSamplerGraph.play: pos=\(pos)s isPlaying=\(playing) engineRunning=\(engineRunning)"
        )
        let mixVolStr = String(format: "%.2f", mainOutputVol)
        MultiChannelLog.shared.log(
            .info,
            "GRAPH-PLAY pos=\(pos)s isPlaying=\(playing) engRun=\(engineRunning) "
                + "seqTracks=\(trackCount) samplers=\(samplerCount) mainMixerVol=\(mixVolStr)"
        )
    }

    /// Resume playback from current position.
    ///
    /// Alias for `play()` when the sequencer is paused. If already playing,
    /// this is a no-op.
    ///
    /// - Throws: `PipelineError.engineNotRunning` if no sequencer is loaded.
    public func resume() throws {
        guard !isPlaying else { return }
        try play()
    }

    /// Pause without resetting position.
    public func pause() {
        let pos = sequencer?.currentPositionInSeconds ?? 0
        sequencer?.stop()
        graphLogger.info("pause at pos=\(pos, privacy: .public)s")
        PipelineFileLog.shared.log("MultiTrackSamplerGraph.pause at pos=\(pos)s")
    }

    /// Stop and reset to start.
    public func stop() {
        let pos = sequencer?.currentPositionInSeconds ?? 0
        sequencer?.stop()
        sequencer?.currentPositionInSeconds = 0
        graphLogger.info("stop from pos=\(pos, privacy: .public)s")
        PipelineFileLog.shared.log("MultiTrackSamplerGraph.stop from pos=\(pos)s")
    }

    /// Seek to a specific beat position in the sequencer timeline.
    ///
    /// - Parameter beat: Target position in beats. Clamped to non-negative.
    public func seek(toBeat beat: Double) {
        let clamped = max(0, beat)
        sequencer?.currentPositionInBeats = clamped
        graphLogger.info("seek toBeat=\(clamped, privacy: .public)")
    }

    // MARK: - Track Muting

    /// Mute specific tracks by index via `AVMusicTrack.isMuted`.
    ///
    /// Tracks not in `indices` are unmuted. Requires a loaded sequencer;
    /// no-ops if no MIDI is loaded yet.
    ///
    /// - Parameter indices: Set of track indices to mute.
    public func setMutedTracks(_ indices: Set<Int>) {
        guard let sequencer else { return }
        for (i, track) in sequencer.tracks.enumerated() {
            track.isMuted = indices.contains(i)
        }
        graphLogger.info("setMutedTracks: \(indices, privacy: .public)")
    }

    // MARK: - Metronome

    /// Schedule a MIDI note-on event for a metronome click at the given beat.
    ///
    /// Adds a short percussion note (note 37 = side stick, velocity 100,
    /// duration 0.1 beats) on the specified MIDI channel at the target beat
    /// position. Requires a loaded sequencer with tracks.
    ///
    /// - Parameters:
    ///   - beat: Beat position where the click should sound.
    ///   - channel: MIDI channel for the click event.
    public func scheduleMetronomeClick(at beat: Double, channel: UInt8) {
        guard let sequencer, !sequencer.tracks.isEmpty else { return }
        // Use the last track for metronome events to avoid conflicts
        // with melodic content on earlier tracks.
        let track = sequencer.tracks[sequencer.tracks.count - 1]
        let event = AVMIDINoteEvent(
            channel: UInt32(channel),
            key: 37,          // GM side stick
            velocity: 100,
            duration: 0.1
        )
        track.addEvent(event, at: beat)
        graphLogger.info(
            "scheduleMetronomeClick at beat=\(beat, privacy: .public) ch=\(channel, privacy: .public)"
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
