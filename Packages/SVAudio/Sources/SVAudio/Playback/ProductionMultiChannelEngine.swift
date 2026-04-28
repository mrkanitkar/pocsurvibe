import AVFoundation
import Foundation
import ObjCExceptionCatcher
import os

/// The production multi-channel audio engine. Persistent — attached at
/// `AudioEngineManager.startForPlayback()` and lives for the app's lifetime.
///
/// Topology:
/// ```
/// samplers[0]    ← Acoustic Grand, reserved for touch input
/// samplers[1..15] ← song slots, re-banked per song (Task 8)
///   ↓ engine.connect(...)
/// subMixer (AVAudioMixerNode)
///   ↓
/// timePitch (AVAudioUnitTimePitch)
///   ↓
/// engine.mainMixerNode
/// ```
///
/// Per-song MIDI is loaded into a single persistent `AVAudioSequencer`
/// (reused via `load(from:options:)` per Apple sample-code pattern). Each
/// `sequencer.tracks[i].destinationAudioUnit = samplers[i+1]` —
/// Apple's documented best practice for per-track AU routing
/// (verified against `iPhoneOS17.0.sdk` AVMusicTrack.h header — `destinationAudioUnit`
/// and `destinationMIDIEndpoint` are mutually exclusive).
///
/// This file is the Task 7 slice: init topology + touch path + transport
/// surface + memory pressure. `loadSong` is intentionally stubbed and
/// implemented in Task 8.
@MainActor
public final class ProductionMultiChannelEngine: MultiChannelEngineProtocol {

    /// Maximum number of song tracks supported (samplers[1..15]).
    public static let maxSongTracks = 15
    private static let totalSamplers = 16
    private static let touchSamplerIndex = 0
    private static let bankNameMuseScoreGeneral = "MuseScore_General"

    // MARK: - Public state

    /// All 16 sampler nodes attached to the engine.
    /// samplers[0] is reserved for touch input (Acoustic Grand).
    /// samplers[1..15] are used for song tracks.
    public private(set) var samplers: [AVAudioUnitSampler]

    /// Metadata for the currently loaded song; nil before first load and after `unloadSong`.
    public private(set) var currentSong: SongHandle?

    /// Whether the sequencer is currently playing.
    public var isPlaying: Bool { sequencer?.isPlaying ?? false }

    /// Current playback position in seconds.
    public var currentPositionInSeconds: TimeInterval {
        guard let seq = sequencer else { return 0 }
        return seq.seconds(forBeats: seq.currentPositionInBeats)
    }

    /// Current playback rate. Range 0.5...1.5.
    public var rate: Float { timePitch.rate }

    // MARK: - Internal nodes

    /// The AVAudioEngine instance this engine manages.
    let engine: AVAudioEngine

    /// Sub-mixer node that collects all sampler outputs before time-pitch processing.
    let subMixer: AVAudioMixerNode

    /// Time-pitch node for rate adjustment without affecting pitch.
    let timePitch: AVAudioUnitTimePitch

    /// Sequencer for MIDI song playback. Nil until a song is loaded.
    var sequencer: AVAudioSequencer?

    /// True while a song-load operation is in progress.
    var isLoadingSong = false

    private static let logger = Logger(
        subsystem: "com.survibe", category: "ProductionMultiChannelEngine"
    )

    // MARK: - Initialization

    /// Create a new engine attached to the provided `AVAudioEngine`.
    ///
    /// Attaches 16 `AVAudioUnitSampler` nodes, a sub-mixer, and a
    /// `AVAudioUnitTimePitch` to `engine`. Connects them in the topology
    /// described in the type documentation. Preloads Acoustic Grand (program 0)
    /// into `samplers[0]` for touch input.
    ///
    /// - Parameter engine: The `AVAudioEngine` to attach nodes to.
    ///   In production this is `AudioEngineManager.shared.engine`;
    ///   in tests an isolated engine can be injected.
    /// - Throws: `MultiChannelEngineError.bankLoadFailed` if the bundled
    ///   `MuseScore_General.sf2` cannot be loaded into `samplers[0]`.
    public init(engine: AVAudioEngine) throws {
        self.engine = engine

        // Build samplers
        var built: [AVAudioUnitSampler] = []
        built.reserveCapacity(Self.totalSamplers)
        for _ in 0..<Self.totalSamplers {
            let s = AVAudioUnitSampler()
            engine.attach(s)
            built.append(s)
        }
        self.samplers = built

        // Build subMixer + TimePitch
        let mixer = AVAudioMixerNode()
        let tp = AVAudioUnitTimePitch()
        engine.attach(mixer)
        engine.attach(tp)
        self.subMixer = mixer
        self.timePitch = tp

        // Wire: each sampler → subMixer → timePitch → mainMixer
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        for s in built {
            engine.connect(s, to: mixer, format: format)
        }
        engine.connect(mixer, to: tp, format: format)
        engine.connect(tp, to: engine.mainMixerNode, format: format)

        let fmtSR = format.sampleRate
        let fmtCH = format.channelCount
        Self.logger.info(
            "init: samplers=\(Self.totalSamplers, privacy: .public) format=\(fmtSR, privacy: .public)Hz/\(fmtCH, privacy: .public)ch"
        )
        MultiChannelLog.shared.log(
            .info,
            "init: samplers=\(Self.totalSamplers) format=\(fmtSR)Hz/\(fmtCH)ch"
        )

        // Preload Acoustic Grand into samplers[0] (reserved for touch input)
        try loadProgram(into: Self.touchSamplerIndex, program: 0, isPercussion: false)
        MultiChannelLog.shared.log(
            .info, "init: sampler[0] preloaded program 0 (Acoustic Grand) for touch"
        )
    }

    // MARK: - Touch input

    /// Trigger a note on `samplers[0]` (Acoustic Grand).
    ///
    /// No-op if the engine is not running; the event is logged at warning level.
    ///
    /// - Parameters:
    ///   - midiNote: MIDI note number (0–127).
    ///   - velocity: Key velocity (0–127, default: 100).
    public func playTouchNote(_ midiNote: UInt8, velocity: UInt8 = 100) {
        guard engine.isRunning else {
            MultiChannelLog.shared.log(.warning, "playTouchNote: engine not running, ignored")
            return
        }
        samplers[Self.touchSamplerIndex].startNote(
            midiNote, withVelocity: velocity, onChannel: 0
        )
        MultiChannelLog.shared.log(.debug, "playTouchNote: midi=\(midiNote) vel=\(velocity)")
    }

    /// Stop a note on `samplers[0]`.
    ///
    /// No-op if the engine is not running.
    ///
    /// - Parameter midiNote: MIDI note number to stop (0–127).
    public func stopTouchNote(_ midiNote: UInt8) {
        guard engine.isRunning else { return }
        samplers[Self.touchSamplerIndex].stopNote(midiNote, onChannel: 0)
        MultiChannelLog.shared.log(.debug, "stopTouchNote: midi=\(midiNote)")
    }

    /// Stop every active note on the touch sampler.
    ///
    /// Sends note-off for all 128 MIDI note numbers on channel 0.
    /// No-op if the engine is not running.
    public func stopAllTouchNotes() {
        guard engine.isRunning else { return }
        for note in 0...127 {
            samplers[Self.touchSamplerIndex].stopNote(UInt8(note), onChannel: 0)
        }
        MultiChannelLog.shared.log(.info, "stopAllTouchNotes")
    }

    // MARK: - Song lifecycle

    /// Load a song from raw MIDI or MusicXML bytes.
    ///
    /// For `.musicXML` sources, auto-detects `.mxl` ZIP containers via a
    /// leading `PK\x03\x04` magic-bytes check, unwraps via `MXLLoader`,
    /// then renders through `VerovioBridge` to `RenderedMIDI`. The `.midi`
    /// path parses per-track Program Change events via `MIDIProgramExtractor`.
    ///
    /// Re-banks `samplers[1..N]` for this song's programs. Per-sampler bank
    /// failures are logged as warnings but do not abort the load — the song
    /// plays with that voice silent.
    ///
    /// If a song is already loaded, it is unloaded first (sequencer stopped,
    /// position reset). A concurrent second call is silently dropped.
    ///
    /// - Parameter source: MIDI or MusicXML data source.
    /// - Throws:
    ///   - `MultiChannelEngineError.engineNotRunning` if the engine is stopped.
    ///   - `MultiChannelEngineError.tooManyTracks` if the source has > 15 tracks.
    ///   - `MultiChannelEngineError.verovioRenderFailed` on MusicXML render error.
    ///   - `MultiChannelEngineError.sequencerLoadFailed` if the sequencer rejects the MIDI.
    public func loadSong(source: MIDISource) async throws {
        guard !isLoadingSong else {
            MultiChannelLog.shared.log(.warning, "loadSong: already loading another song; skipping")
            return
        }
        guard engine.isRunning else { throw MultiChannelEngineError.engineNotRunning }
        isLoadingSong = true
        defer { isLoadingSong = false }

        if currentSong != nil { unloadSong() }

        MultiChannelLog.shared.session("loadSong start")
        let startTime = Date()
        MultiChannelLog.shared.log(.info, "loadSong START source=\(sourceTag(source))")

        // Resolve MIDI bytes (run Verovio if needed) and per-track program info.
        let (midiData, trackInfos) = try resolveSource(source)

        // Validate track count against the song-slot capacity (samplers[1..15]).
        guard trackInfos.count <= Self.maxSongTracks else {
            throw MultiChannelEngineError.tooManyTracks(
                found: trackInfos.count, max: Self.maxSongTracks
            )
        }

        // Re-bank samplers[1..N] for this song's per-track programs.
        for (idx, spec) in trackInfos.enumerated() {
            let samplerIndex = idx + 1   // [0] is reserved for touch
            do {
                try loadProgram(
                    into: samplerIndex,
                    program: spec.program,
                    isPercussion: spec.isPercussion
                )
                MultiChannelLog.shared.log(
                    .info,
                    "loadSong: sampler[\(samplerIndex)] preset=\(spec.program) percussion=\(spec.isPercussion) loaded OK"
                )
            } catch let e as MultiChannelEngineError {
                // Continue loading remaining samplers; the song plays minus this voice.
                MultiChannelLog.shared.log(
                    .warning,
                    "loadSong: sampler[\(samplerIndex)] preset=\(spec.program) FAILED: \(e.localizedDescription)"
                )
            }
        }

        // Construct or reuse the persistent sequencer.
        let seq: AVAudioSequencer
        if let existing = sequencer {
            seq = existing
        } else {
            seq = AVAudioSequencer(audioEngine: engine)
            sequencer = seq
        }
        seq.stop()
        do {
            try seq.load(from: midiData, options: [])
        } catch {
            throw MultiChannelEngineError.sequencerLoadFailed(underlying: error)
        }

        // Bind tracks to samplers[1..N] via destinationAudioUnit
        // (Apple's documented best-practice pattern; verified in iPhoneOS17.0.sdk
        // AVMusicTrack.h that destinationAudioUnit and destinationMIDIEndpoint
        // are mutually exclusive).
        let trackBindCount = min(seq.tracks.count, trackInfos.count)
        if seq.tracks.count != trackInfos.count {
            MultiChannelLog.shared.log(
                .warning,
                "loadSong: seq.tracks.count=\(seq.tracks.count) != trackInfos.count=\(trackInfos.count); routing \(trackBindCount) tracks"
            )
        }
        for i in 0..<trackBindCount {
            seq.tracks[i].destinationAudioUnit = samplers[i + 1]
        }

        // Compute song duration as the max of per-track lengths.
        let durationBeats = seq.tracks.map { $0.lengthInBeats }.max() ?? 0
        let durationSec = seq.seconds(forBeats: durationBeats)

        self.currentSong = SongHandle(
            trackCount: trackInfos.count,
            durationSeconds: durationSec,
            programs: trackInfos.map { $0.program }
        )

        let elapsed = Date().timeIntervalSince(startTime)
        MultiChannelLog.shared.log(
            .info,
            "loadSong DONE tracks=\(trackInfos.count) elapsed=\(String(format: "%.2f", elapsed))s"
        )
    }

    /// Unload the current song. Stops the sequencer and resets position.
    ///
    /// Samplers stay attached and warm — re-banking happens on the next
    /// `loadSong` call. Logs the previous song's programs for diagnostics.
    public func unloadSong() {
        let prev = currentSong?.programs ?? []
        sequencer?.stop()
        sequencer?.currentPositionInBeats = 0
        currentSong = nil
        MultiChannelLog.shared.log(.info, "unloadSong: previous_programs=\(prev)")
    }

    // MARK: - Helpers

    /// Compact description of a `MIDISource` for log messages.
    private func sourceTag(_ s: MIDISource) -> String {
        switch s {
        case .midi(let d): return "midi(\(d.count)B)"
        case .musicXML(let d): return "musicXML(\(d.count)B)"
        }
    }

    /// Per-track program and percussion flag resolved during song load.
    private struct TrackProgramSpec {
        /// GM program number (0–127). Defaults to 0 (Acoustic Grand) if none found.
        let program: UInt8
        /// True when the track uses MIDI channel 9 (GM percussion convention).
        let isPercussion: Bool
    }

    // MARK: - Transport

    /// Start or resume playback of the loaded song.
    ///
    /// - Throws: `MultiChannelEngineError.noSongLoaded` if no song is loaded.
    public func play() throws {
        guard let seq = sequencer else { throw MultiChannelEngineError.noSongLoaded }
        try seq.start()
        MultiChannelLog.shared.log(.info, "play: pos=\(seq.currentPositionInBeats)beats rate=\(rate)")
    }

    /// Pause playback without resetting position.
    public func pause() {
        sequencer?.stop()
        MultiChannelLog.shared.log(.info, "pause")
    }

    /// Stop playback and reset position to the beginning.
    public func stop() {
        sequencer?.stop()
        sequencer?.currentPositionInBeats = 0
        MultiChannelLog.shared.log(.info, "stop")
    }

    // MARK: - Tempo

    /// Set playback rate, clamped to the range 0.5...1.5.
    ///
    /// Uses `AVAudioUnitTimePitch` so pitch is preserved at all rates.
    ///
    /// - Parameter rate: Desired playback rate. Values outside 0.5...1.5 are clamped.
    public func setRate(_ rate: Float) {
        let clamped = max(0.5, min(1.5, rate))
        timePitch.rate = clamped
        MultiChannelLog.shared.log(.info, "setRate: rate=\(clamped)")
    }

    // MARK: - Memory pressure

    /// Reset `samplers[1..15]` to program 0 to free SF2 program data.
    ///
    /// Only executes when no song is currently loaded. Safe to call from a
    /// `UIApplication.didReceiveMemoryWarningNotification` handler.
    public func flushSongPrograms() {
        guard currentSong == nil else {
            MultiChannelLog.shared.log(.info, "flushSongPrograms: skipped (song active)")
            return
        }
        var failedSlots: [Int] = []
        for i in 1..<Self.totalSamplers {
            do {
                try loadProgram(into: i, program: 0, isPercussion: false)
            } catch {
                failedSlots.append(i)
                MultiChannelLog.shared.log(
                    .warning,
                    "flushSongPrograms: sampler[\(i)] reset failed: \(error.localizedDescription)"
                )
            }
        }
        let level: MultiChannelLog.Level = failedSlots.isEmpty ? .info : .warning
        MultiChannelLog.shared.log(
            level,
            "flushSongPrograms: reset samplers[1..15] to program 0; failed=\(failedSlots)"
        )
    }

    // MARK: - Private

    /// Resolve a `MIDISource` into raw MIDI bytes and per-track program info.
    ///
    /// For `.midi` sources, extracts GM program numbers via
    /// `MIDIProgramExtractor`. For `.musicXML`, unwraps optional MXL ZIP
    /// containers and renders through `VerovioBridge`.
    ///
    /// - Parameter source: The audio data source to resolve.
    /// - Returns: A tuple of the raw MIDI `Data` and an array of
    ///   `TrackProgramSpec` values (one per MIDI track).
    /// - Throws: `MultiChannelEngineError.sequencerLoadFailed` on malformed
    ///   MIDI bytes; `MultiChannelEngineError.verovioRenderFailed` on
    ///   MusicXML render errors.
    private func resolveSource(_ source: MIDISource) throws -> (Data, [TrackProgramSpec]) {
        switch source {
        case .midi(let bytes):
            let raw: [UInt8?]
            do {
                raw = try MIDIProgramExtractor.extractPrograms(midi: bytes)
            } catch {
                throw MultiChannelEngineError.sequencerLoadFailed(underlying: error)
            }
            let infos = raw.map { TrackProgramSpec(program: $0 ?? 0, isPercussion: false) }
            return (bytes, infos)
        case .musicXML(let bytes):
            let xml: String
            if MIDISource.isLikelyMXLZip(bytes) {
                do {
                    xml = try MXLLoader.loadMusicXML(from: bytes)
                } catch {
                    throw MultiChannelEngineError.verovioRenderFailed(underlying: error)
                }
            } else {
                guard let s = String(data: bytes, encoding: .utf8) else {
                    throw MultiChannelEngineError.verovioRenderFailed(
                        underlying: PipelineError.verovioRenderFailed(reason: "musicXML not utf8")
                    )
                }
                xml = s
            }
            let bridge = VerovioBridge()
            let rendered: RenderedMIDI
            do {
                rendered = try bridge.render(musicXML: xml)
            } catch {
                throw MultiChannelEngineError.verovioRenderFailed(underlying: error)
            }
            let infos = rendered.trackInfo.map {
                TrackProgramSpec(program: $0.program ?? 0, isPercussion: $0.isPercussion)
            }
            return (rendered.data, infos)
        }
    }

    /// Load `program` into `samplers[index]` from the bundled
    /// `MuseScore_General.sf2`.
    ///
    /// Wrapped in `SVAudioTryObjC` to catch ObjC exceptions from malformed
    /// presets (Apple's `loadSoundBankInstrument` raises `NSException` on bad
    /// SF2 inputs). Mirrors the pattern in `SoundFontManager.loadSoundFont`.
    ///
    /// - Parameters:
    ///   - index: Index into `samplers` (0–15).
    ///   - program: GM program number (0–127).
    ///   - isPercussion: When true, uses `kAUSampler_DefaultPercussionBankMSB`.
    /// - Throws: `MultiChannelEngineError.bankLoadFailed` on any failure.
    func loadProgram(into index: Int, program: UInt8, isPercussion: Bool) throws {
        guard let url = Bundle.module.url(
            forResource: Self.bankNameMuseScoreGeneral, withExtension: "sf2"
        ) else {
            throw MultiChannelEngineError.bankLoadFailed(
                samplerIndex: index,
                underlying: PipelineError.resourceMissing(
                    name: "\(Self.bankNameMuseScoreGeneral).sf2"
                )
            )
        }
        let bankMSB: UInt8 = isPercussion
            ? UInt8(kAUSampler_DefaultPercussionBankMSB)
            : UInt8(kAUSampler_DefaultMelodicBankMSB)
        let sampler = samplers[index]

        var swiftError: (any Error)?
        var objcError: NSError?
        let success = SVAudioTryObjC({
            do {
                try sampler.loadSoundBankInstrument(
                    at: url,
                    program: program,
                    bankMSB: bankMSB,
                    bankLSB: 0
                )
            } catch {
                swiftError = error
            }
        }, &objcError)

        if let swiftError {
            throw MultiChannelEngineError.bankLoadFailed(
                samplerIndex: index, underlying: swiftError
            )
        }
        if !success {
            let message = objcError?.localizedDescription ?? "Unknown SF2 load failure"
            throw MultiChannelEngineError.bankLoadFailed(
                samplerIndex: index,
                underlying: PipelineError.resourceMissing(name: "objc-exception:\(message)")
            )
        }
    }
}

// MARK: - Errors

/// Errors surfaced by `ProductionMultiChannelEngine` and `MultiChannelEngineProtocol`.
public enum MultiChannelEngineError: Error, LocalizedError, Equatable {
    /// The `AVAudioEngine` is not running.
    case engineNotRunning
    /// Song has more tracks than the 15-slot limit.
    case tooManyTracks(found: Int, max: Int)
    /// `AVAudioUnitSampler.loadSoundBankInstrument` failed for a sampler slot.
    case bankLoadFailed(samplerIndex: Int, underlying: any Error)
    /// Verovio render or post-processing failed.
    case verovioRenderFailed(underlying: any Error)
    /// `AVAudioSequencer` could not load the MIDI data.
    case sequencerLoadFailed(underlying: any Error)
    /// A transport operation was attempted with no song loaded.
    case noSongLoaded

    public var errorDescription: String? {
        switch self {
        case .engineNotRunning: return "Audio engine is not running"
        case .tooManyTracks(let found, let max):
            return "Song has \(found) tracks; max supported is \(max)"
        case .bankLoadFailed(let i, let e):
            return "Bank load failed on sampler[\(i)]: \(e.localizedDescription)"
        case .verovioRenderFailed(let e):
            return "Verovio render failed: \(e.localizedDescription)"
        case .sequencerLoadFailed(let e):
            return "Sequencer load failed: \(e.localizedDescription)"
        case .noSongLoaded: return "No song loaded"
        }
    }

    public static func == (lhs: MultiChannelEngineError, rhs: MultiChannelEngineError) -> Bool {
        switch (lhs, rhs) {
        case (.engineNotRunning, .engineNotRunning): return true
        case (.noSongLoaded, .noSongLoaded): return true
        case (.tooManyTracks(let lf, let lm), .tooManyTracks(let rf, let rm)):
            return lf == rf && lm == rm
        case (.bankLoadFailed(let li, _), .bankLoadFailed(let ri, _)): return li == ri
        case (.verovioRenderFailed, .verovioRenderFailed): return true
        case (.sequencerLoadFailed, .sequencerLoadFailed): return true
        default: return false
        }
    }
}
