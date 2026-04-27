import AVFoundation
import CoreMIDI
import Foundation
import os

private let fsEngineLogger = Logger.survibe(category: "FluidSynthEngine")

/// `AuditionEngine` powered by FluidSynth 2.5. Single multi-timbral instance
/// handles all 16 MIDI channels through one render block. MIDI events flow:
///
///   AVAudioSequencer → AVMusicTrack.destinationMIDIEndpoint
///       → CoreMIDI virtual destination → receive callback (high-prio thread)
///       → FluidSynthMIDIParser → FluidSynthMIDIEventRing
///       → drained by FluidSynthRenderer.makeRenderBlock (CoreAudio realtime thread)
///       → fluid_synth_noteon / write_float
@MainActor
public final class FluidSynthEngine: AuditionEngine {

    // MARK: - Properties

    /// Picker label sourced from `EngineKind.fluidsynth.displayName`.
    public var displayName: String { EngineKind.fluidsynth.displayName }

    /// Sub-mixer node exposed to the pipeline. Always non-nil so SwiftUI
    /// bindings have a stable reference even before `setup` runs.
    public var output: AVAudioNode { subMixer }

    /// Whether the underlying `AVAudioSequencer` is currently producing audio.
    public var isPlaying: Bool { sequencer?.isPlaying ?? false }

    /// Wall-clock duration of the loaded sequence (longest non-empty track).
    public var sequenceDuration: TimeInterval {
        guard let tracks = sequencer?.tracks, !tracks.isEmpty else { return 0 }
        return tracks.map(\.lengthInSeconds).max() ?? 0
    }

    private let subMixer = AVAudioMixerNode()
    private var sourceNode: AVAudioSourceNode?
    private var sequencer: AVAudioSequencer?
    private var renderer: FluidSynthRenderer?
    private var ring: FluidSynthMIDIEventRing?
    private var parser: FluidSynthMIDIParser?
    private var midiClient = MIDIClientRef()
    private var midiDest = MIDIEndpointRef()
    private var rendered: RenderedMIDI?

    // MARK: - Initialization

    /// Creates an engine in a clean, not-set-up state. Callers must invoke
    /// `setup(rendered:bankURL:)` before `play()`.
    public init() {}

    // MARK: - Public Methods

    /// Builds the FluidSynth audio graph: ring + parser + renderer +
    /// `AVAudioSourceNode` + `AVAudioMixerNode`, attaches them to the shared
    /// `AVAudioEngine`, creates a CoreMIDI virtual destination wired to the
    /// parser, and loads `bankURL` with per-channel programs from
    /// `rendered.trackInfo`.
    ///
    /// - Parameters:
    ///   - rendered: The Verovio-rendered MIDI to schedule via the sequencer.
    ///   - bankURL: SF2 SoundFont to load.
    /// - Throws: `PipelineError.bounceFailed` on CoreMIDI / SF2 / sequencer
    ///   failures.
    public func setup(rendered: RenderedMIDI, bankURL: URL) throws {
        self.rendered = rendered
        let avEngine = AudioEngineManager.shared.engine
        let format = avEngine.mainMixerNode.outputFormat(forBus: 0)

        // 1. Build MIDI ring + parser
        let ring = FluidSynthMIDIEventRing(capacity: 1024)
        let parser = FluidSynthMIDIParser(ring: ring)
        self.ring = ring
        self.parser = parser

        // 2. Build renderer + load SF2 + assign per-channel programs
        let renderer = FluidSynthRenderer(sampleRate: format.sampleRate, ring: ring)
        try renderer.loadSoundFont(at: bankURL)
        for info in rendered.trackInfo {
            if let program = info.program {
                renderer.setProgram(channel: info.channel, program: program)
            }
        }
        self.renderer = renderer

        // 3. Build source node + sub-mixer + attach to engine
        let block = renderer.makeRenderBlock(format: format)
        let node = AVAudioSourceNode(format: format, renderBlock: block)
        avEngine.attach(node)
        avEngine.attach(subMixer)
        avEngine.connect(node, to: subMixer, format: format)
        avEngine.connect(subMixer, to: avEngine.mainMixerNode, format: format)
        self.sourceNode = node

        // 4. Build CoreMIDI virtual destination + receive callback
        try buildCoreMIDIDestination(parser: parser)

        // 5. Build sequencer + route every track to our virtual destination
        let seq = AVAudioSequencer(audioEngine: avEngine)
        try seq.load(from: rendered.data, options: [])
        for track in seq.tracks {
            track.destinationMIDIEndpoint = midiDest
        }
        self.sequencer = seq

        let trackCount = rendered.trackInfo.count
        fsEngineLogger.info(
            "setup: trackCount=\(trackCount, privacy: .public) bank=\(bankURL.lastPathComponent, privacy: .public)"
        )
        PipelineFileLog.shared.log(
            "FluidSynthEngine.setup: trackCount=\(trackCount) bank=\(bankURL.lastPathComponent) format=\(format.sampleRate)/\(format.channelCount)"
        )
    }

    /// Swaps the loaded SF2 to a new bank and re-applies the per-channel
    /// GM programs captured in the previous `setup`. No-op if `setup` has
    /// not yet run.
    public func loadBank(_ bankURL: URL) throws {
        guard let renderer, let rendered else { return }
        try renderer.loadSoundFont(at: bankURL)
        for info in rendered.trackInfo {
            if let program = info.program {
                renderer.setProgram(channel: info.channel, program: program)
            }
        }
        PipelineFileLog.shared.log(
            "FluidSynthEngine.loadBank: \(bankURL.lastPathComponent)"
        )
    }

    /// Starts the underlying `AVAudioSequencer`. No-op if `setup` has not
    /// yet run.
    public func play() throws {
        guard let sequencer else { return }
        sequencer.prepareToPlay()
        try sequencer.start()
        PipelineFileLog.shared.log(
            "FluidSynthEngine.play: pos=\(sequencer.currentPositionInSeconds)s"
        )
    }

    /// Pauses the sequencer without resetting the playback position.
    public func pause() {
        sequencer?.stop()
        PipelineFileLog.shared.log("FluidSynthEngine.pause")
    }

    /// Stops the sequencer and resets the playback position to zero.
    public func stop() {
        sequencer?.stop()
        sequencer?.currentPositionInSeconds = 0
        PipelineFileLog.shared.log("FluidSynthEngine.stop")
    }

    /// Detaches all nodes from the shared engine, disposes of the CoreMIDI
    /// virtual destination + client, and releases the renderer / parser /
    /// ring. Idempotent.
    public func tearDown() {
        sequencer?.stop()
        sequencer = nil
        let avEngine = AudioEngineManager.shared.engine
        if let node = sourceNode {
            avEngine.disconnectNodeOutput(node)
            avEngine.detach(node)
        }
        avEngine.disconnectNodeOutput(subMixer)
        if subMixer.engine != nil {
            avEngine.detach(subMixer)
        }
        if midiDest != 0 {
            MIDIEndpointDispose(midiDest)
            midiDest = 0
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
            midiClient = 0
        }
        sourceNode = nil
        renderer = nil
        ring = nil
        parser = nil
        rendered = nil
        PipelineFileLog.shared.log("FluidSynthEngine.tearDown")
    }

    /// One-line snapshot of the engine state for `pipeline_log.txt`.
    public func diagnosticSummary() -> String {
        let trackCount = rendered?.trackInfo.count ?? 0
        return "FluidSynthEngine: tracks=\(trackCount) playing=\(isPlaying)"
    }

    // MARK: - Private Methods

    /// Creates a CoreMIDI client and a virtual destination endpoint whose
    /// receive block forwards every incoming packet list to `parser`.
    ///
    /// CRITICAL: the `MIDIReadBlock` closure is `@Sendable` per CoreMIDI's
    /// API contract, so we capture only `parser` (which is
    /// `@unchecked Sendable`) — never `self`. Capturing `self` would pull
    /// in `@MainActor` isolation and break the closure's Sendable contract,
    /// matching the bug class previously hit on `RealtimeTapBouncer`.
    private func buildCoreMIDIDestination(parser: FluidSynthMIDIParser) throws {
        let clientStatus = MIDIClientCreate(
            "SurVibe.AuditionFluidSynth" as CFString, nil, nil, &midiClient
        )
        if clientStatus != noErr {
            throw PipelineError.bounceFailed(
                reason: "MIDIClientCreate failed: \(clientStatus)"
            )
        }
        let block: MIDIReadBlock = { packetList, _ in
            parser.parsePacketList(packetList)
        }
        let destStatus = MIDIDestinationCreateWithBlock(
            midiClient, "SurVibe.FluidSynthDest" as CFString, &midiDest, block
        )
        if destStatus != noErr {
            throw PipelineError.bounceFailed(
                reason: "MIDIDestinationCreateWithBlock failed: \(destStatus)"
            )
        }
    }
}
