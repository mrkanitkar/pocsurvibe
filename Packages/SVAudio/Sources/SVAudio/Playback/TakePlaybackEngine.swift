import AVFoundation
import Foundation
import QuartzCore
import SVCore

/// Plays back a `TakeSnapshot` audibly via `AVAudioSequencer` (sample-accurate
/// scheduling on slot 2 of the production multi-channel engine) and visually
/// via a `CADisplayLink`-driven `HighlightSink`.
///
/// The two streams are deliberately decoupled:
/// - **Audible** — `AVAudioSequencer` is loaded with a fresh SMF Type-0 byte
///   stream produced by `MIDISerializer`. Every track's `destinationAudioUnit`
///   is bound to `samplers[Self.playbackSlot]` so the take never collides with
///   touch input (slot 0) or a song (slots 1–15). Timing is sample-accurate.
/// - **Visual** — a `CADisplayLink` fires every display frame, computes the
///   set of notes whose `[onSec, offSec)` window contains the current sequencer
///   position, and dispatches `noteOn` / `noteOff` to the `HighlightSink` for
///   any notes that entered or exited the window. This produces sub-frame
///   highlight jitter for chords (vs. driving the sink directly from MIDI
///   callbacks, which would miss simultaneous note-ons inside a single frame).
///
/// Hand-filter, playback speed, and (future) Sa transposition are baked into
/// the snapshot at `schedule(...)` time — the sequencer does not re-tempo.
/// Active scheduling mode for `TakePlaybackEngine`.
///
/// The engine plays back two distinct content types through one transport:
/// recorded takes from the Play tab (`takeSnapshot` mode, scheduled via
/// `MIDISerializer` from `[RecordedNote]`) and Standard MIDI Files from the
/// Songs library (`smf` mode, loaded via `loadSMFData(_:graph:...)`). Both
/// modes share the same `AVAudioSequencer` instance; the mode flag controls
/// only the visual highlight tick path (SMF mode currently has no per-note
/// highlight cache because the renderers project from `[NoteEvent]`).
public enum TakePlaybackMode: String, Sendable, Equatable {
    /// Recorded-take playback driven by `schedule(snapshot:...)`.
    case takeSnapshot
    /// SMF playback driven by `loadSMFData(_:graph:...)`.
    case smf
}

@MainActor
public final class TakePlaybackEngine: TakePlaybackProviding {

    /// Sampler slot dedicated to take playback. Slots 0 (touch) and 1–15 (song
    /// tracks) are owned by other features; slot 2 is reserved for this engine.
    public static let playbackSlot: Int = 2

    // MARK: - Dependencies

    private let multiChannel: MultiChannelEngineProtocol
    private weak var highlightSink: HighlightSink?
    private let engine: AVAudioEngine
    private var sequencer: AVAudioSequencer

    // MARK: - State

    /// Cached note timing (post-filter, post-speed) used by the visual link to
    /// compute which highlights should be lit on each frame.
    private struct ScheduledEvent {
        let onSec: TimeInterval
        let offSec: TimeInterval
        let midi: UInt8
        let channel: UInt8
    }
    private var scheduledNotes: [ScheduledEvent] = []
    private var lastFrameLitNotes: Set<Int> = []
    private var visualLink: CADisplayLink?

    // MARK: - Public read-only state

    /// Whether the sequencer is currently playing.
    public private(set) var isPlaying: Bool = false

    /// Current scheduling mode. Defaults to `.takeSnapshot` for back-compat
    /// with the Play tab path; flips to `.smf` after `loadSMFData(...)`.
    public private(set) var mode: TakePlaybackMode = .takeSnapshot

    /// Current playback position in seconds (in the loaded content's
    /// timeline). Reads from the engine's authoritative `AVAudioSequencer`,
    /// so both `.takeSnapshot` and `.smf` modes return the same notion of
    /// "now" — this is the **single canonical clock** for Songs Play Along
    /// per locked decision #3 (T10').
    public var currentPositionSec: TimeInterval {
        sequencer.seconds(forBeats: sequencer.currentPositionInBeats)
    }

    /// Per-frame display position in seconds, queried at a future host time.
    ///
    /// Pass `CADisplayLink.targetTimestamp` (the next-frame presentation time)
    /// so the returned position leads the audio clock by one frame, matching
    /// what the user will see when the frame actually appears. This is the
    /// recommended `AVAudioSequencer` clock pattern — see
    /// `AVAudioSequencer.beats(forHostTime:)` and
    /// `AVAudioSequencer.seconds(forBeats:)` on developer.apple.com.
    ///
    /// - Parameter hostTime: Mach host time at which to sample the clock,
    ///   typically `CADisplayLink.targetTimestamp` converted via
    ///   `mach_absolute_time` semantics.
    /// - Returns: Position in seconds from song start at `hostTime`. Returns
    ///   `currentPositionSec` if the host-time conversion fails.
    public func displayPositionSec(forHostTime hostTime: UInt64) -> TimeInterval {
        var error: NSError?
        let beats = sequencer.beats(forHostTime: hostTime, error: &error)
        guard error == nil else { return currentPositionSec }
        return sequencer.seconds(forBeats: beats)
    }

    /// Number of notes currently scheduled for visual highlight (post-filter).
    /// Test hook used by `TakePlaybackEngineTests`.
    public var scheduledNoteCount: Int { scheduledNotes.count }

    /// Onset (in seconds) of the first scheduled note, or 0 if none.
    /// Test hook used by `TakePlaybackEngineTests` to verify speed scaling.
    public var scheduledFirstOnsetSec: TimeInterval {
        scheduledNotes.first?.onSec ?? 0
    }

    // MARK: - Initialization

    /// Creates a take-playback engine.
    ///
    /// - Parameters:
    ///   - multiChannel: The shared `ProductionMultiChannelEngine` (or a
    ///     conforming test double). Used to bind the sequencer's track
    ///     destinations to slot 2 and to issue an `allNotesOff` on `stop()`.
    ///   - highlightSink: Visual sink driven by the `CADisplayLink`. May be
    ///     nil for headless playback (e.g. unit tests of audio scheduling).
    ///     Held weakly — typically `MIDINoteHighlightCoordinator`, owned by
    ///     the view layer.
    ///   - engine: The shared `AVAudioEngine` instance from
    ///     `AudioEngineManager.shared.engine`.
    public init(
        multiChannel: MultiChannelEngineProtocol,
        highlightSink: HighlightSink?,
        engine: AVAudioEngine
    ) {
        self.multiChannel = multiChannel
        self.highlightSink = highlightSink
        self.engine = engine
        self.sequencer = AVAudioSequencer(audioEngine: engine)
    }

    // MARK: - TakePlaybackProviding

    public func schedule(
        snapshot: TakeSnapshot,
        speed: Double,
        handFilter: HandFilter,
        saMidi _: UInt8
    ) async {
        let safeSpeed = max(speed, 0.000_1)
        let filtered = snapshot.notes.filter { Self.matches(handFilter: handFilter, note: $0) }
        let scaledNotes = filtered.map { Self.scale(note: $0, by: safeSpeed) }
        let scaledSustain = snapshot.sustain.map { Self.scale(sustain: $0, by: safeSpeed) }

        scheduledNotes = scaledNotes
            .map {
                ScheduledEvent(
                    onSec: $0.onTimeSec,
                    offSec: $0.offTimeSec,
                    midi: $0.midi,
                    channel: $0.channel
                )
            }
            .sorted { $0.onSec < $1.onSec }

        let midiData = MIDISerializer.serializeType0(
            notes: scaledNotes,
            sustain: scaledSustain,
            program: snapshot.instrumentProgram
        )
        do {
            try sequencer.load(from: midiData, options: [])
            bindTracksToPlaybackSlot(program: snapshot.instrumentProgram)
        } catch {
            // Surface to tests/console; UI error path is wired in Task 14.
            assertionFailure("TakePlaybackEngine.schedule: load failed: \(error)")
        }
    }

    /// Routes every sequencer track's audio destination to slot 2's sampler so
    /// the take never collides with touch input (slot 0) or a song (slots 1–15).
    /// Also loads the SoundFont program for the take's instrument into slot 2 —
    /// without this, the AUSampler routes MIDI through a default sine tone and
    /// playback sounds distorted.
    private func bindTracksToPlaybackSlot(program: UInt8) {
        guard
            let production = multiChannel as? ProductionMultiChannelEngine,
            production.samplers.indices.contains(Self.playbackSlot)
        else { return }
        // Load the SoundFont bank/program on slot 2 so the sampler renders the
        // correct instrument timbre instead of the default oscillator.
        try? production.loadProgram(
            into: Self.playbackSlot, program: program, isPercussion: false
        )
        let dest = production.samplers[Self.playbackSlot]
        for track in sequencer.tracks {
            track.destinationAudioUnit = dest
        }
    }

    nonisolated private static func matches(handFilter: HandFilter, note: RecordedNote) -> Bool {
        switch handFilter {
        case .both: return true
        case .trebleOnly: return note.midi >= 60
        case .bassOnly: return note.midi < 60
        }
    }

    nonisolated private static func scale(note: RecordedNote, by speed: Double) -> RecordedNote {
        RecordedNote(
            id: note.id,
            midi: note.midi,
            velocity: note.velocity,
            velocity16Bit: note.velocity16Bit,
            onTimeSec: note.onTimeSec / speed,
            offTimeSec: note.offTimeSec / speed,
            channel: note.channel
        )
    }

    nonisolated private static func scale(sustain: RecordedSustainEvent, by speed: Double) -> RecordedSustainEvent {
        RecordedSustainEvent(
            timeSec: sustain.timeSec / speed,
            down: sustain.down,
            channel: sustain.channel
        )
    }

    public func play() {
        do {
            try sequencer.start()
        } catch {
            return
        }
        isPlaying = true
        // SMF mode renderers consume `[NoteEvent]` directly and read
        // `currentPositionSec` per-frame; no per-tick highlight diff is
        // needed (and the `scheduledNotes` cache is empty in SMF mode).
        if mode == .takeSnapshot {
            startVisualLink()
        }
    }

    public func pause() {
        sequencer.stop()
        isPlaying = false
        stopVisualLink()
    }

    public func seek(to sec: TimeInterval) {
        sequencer.currentPositionInSeconds = max(0, sec)
    }

    /// Seek to a position in seconds. Convenience wrapper used by the Songs
    /// Play Along clock-adoption path (T10') so callers can use a clearer
    /// name than the legacy `seek(to:)`.
    public func seek(toSec sec: TimeInterval) {
        seek(to: sec)
    }

    /// Set the playback rate of the underlying `AVAudioSequencer`.
    ///
    /// `1.0` is the original tempo, `0.5` half-speed, `1.5` 1.5x. Affects
    /// audible playback and `currentPositionSec` together so visualization
    /// stays sample-accurate. Used by Songs Play Along's tempo slider.
    ///
    /// - Parameter rate: Playback rate. Clamped to a small positive
    ///   epsilon to avoid stalling the sequencer.
    public func setTempoScale(_ rate: Float) {
        sequencer.rate = max(0.01, rate)
    }

    public func stop() {
        sequencer.stop()
        sequencer.currentPositionInSeconds = 0
        isPlaying = false
        stopVisualLink()
        // Light off any remaining highlights so the keyboard view doesn't
        // leak state into the next take.
        for midi in lastFrameLitNotes {
            highlightSink?.noteOff(midi, channel: 0)
        }
        lastFrameLitNotes.removeAll()
        // Slot 2 silence is a no-op in SMF mode (samplers belong to the
        // caller-supplied graph) but it's safe to issue regardless — the
        // production engine routes the call to its own slot 2 sampler.
        multiChannel.allNotesOffOnSlot(Self.playbackSlot)
    }

    // MARK: - SMF mode (T10')

    /// Load Standard MIDI File bytes into the engine's sequencer, routing
    /// each music track to the matching sampler in `graph`.
    ///
    /// This is the Songs Play Along entry point. `MultiTrackSamplerGraph`
    /// has already been built and pre-banked by the caller (see
    /// `PlayAlongViewModel.loadArrangementIfPossible`). After this call,
    /// `currentPositionSec` reflects the SMF timeline; `play()` starts the
    /// underlying `AVAudioSequencer`; `seek(toSec:)` jumps the clock; and
    /// `displayPositionSec(forHostTime:)` returns a per-frame display
    /// position synchronized to the engine output.
    ///
    /// `instrumentProgram` is a fallback GM program for any track whose
    /// sampler slot wasn't pre-banked from a Program Change event in the
    /// SMF (the common case is `0` = Acoustic Grand). The graph's
    /// per-sampler bank load is the authoritative routing — this argument
    /// is only used to log a sensible default when track count exceeds
    /// `graph.samplers.count`.
    ///
    /// Primary-source justification for the per-frame clock pattern:
    /// `AVAudioSequencer.beats(forHostTime:)` / `seconds(forBeats:)` on
    /// developer.apple.com. The locked decision (#3) is that this engine
    /// owns the master clock for Songs Play Along — replacing the prior
    /// `installArrangementBeatBridge` accumulator that drifted past song
    /// duration.
    ///
    /// - Parameters:
    ///   - data: SMF byte stream (typically `Song.midiData` or the full
    ///     rendered Verovio output).
    ///   - graph: Pre-banked sampler graph that owns the destination
    ///     `AVAudioUnitSampler` instances. Each sequencer track is routed
    ///     to `graph.samplers[i].samplerUnit`.
    ///   - instrumentProgram: Fallback GM program for unconfigured tracks.
    ///     Defaults to `0` (Acoustic Grand).
    /// - Throws: Underlying `AVAudioSequencer` errors on malformed MIDI;
    ///   `PipelineError.engineNotRunning` if the shared engine is stopped.
    public func loadSMFData(
        _ data: Data,
        graph: any MultiTrackSamplerGraphProtocol,
        instrumentProgram: UInt8 = 0
    ) throws {
        guard AudioEngineManager.shared.isRunning else {
            throw PipelineError.engineNotRunning
        }
        // Stop and reset any in-flight take playback before adopting the
        // sequencer for SMF — the new `load(from:options:)` invalidates the
        // previous content unconditionally, but stopping first keeps the
        // visual link from observing torn state mid-swap.
        sequencer.stop()
        stopVisualLink()
        scheduledNotes = []
        lastFrameLitNotes.removeAll()

        // Build a fresh sequencer over the same engine — `AVAudioSequencer`
        // does not formally support re-loading after a previous load is in
        // play, so re-instantiating is the safest path. The new sequencer
        // shares the engine and therefore the audio output graph.
        let seq = AVAudioSequencer(audioEngine: engine)
        try seq.load(from: data, options: [])

        // Route each music track to the corresponding sampler in the
        // caller-supplied graph. We deliberately do NOT also call
        // `graph.loadMIDI(_:)` — that would create a second sequencer on the
        // same engine and split the clock. After T10' the engine's sequencer
        // is the single authority.
        let production = (graph as? MultiTrackSamplerGraph)
        let samplers = production?.samplers ?? []
        let count = min(seq.tracks.count, samplers.count)
        for i in 0..<count {
            seq.tracks[i].destinationAudioUnit = samplers[i].samplerUnit
        }

        self.sequencer = seq
        self.mode = .smf
        MultiChannelLog.shared.log(
            .info,
            "==> TakePlaybackEngine.loadSMFData bytes=\(data.count) "
                + "tracks=\(seq.tracks.count) routed=\(count) program=\(instrumentProgram)"
        )
        MultiChannelLog.shared.log(
            .info,
            "==> TakePlaybackEngine: SMF mode active, position=\(currentPositionSec)s"
        )
    }

    // MARK: - Visual link

    private func startVisualLink() {
        guard visualLink == nil else { return }
        let proxy = VisualLinkProxy(self)
        let link = CADisplayLink(target: proxy, selector: #selector(VisualLinkProxy.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        visualLink = link
    }

    private func stopVisualLink() {
        visualLink?.invalidate()
        visualLink = nil
    }

    /// Computes the set of notes whose window contains the current sequencer
    /// position, then dispatches edge transitions to the highlight sink.
    fileprivate func visualTick() {
        let now = currentPositionSec
        var nowLit: Set<Int> = []
        nowLit.reserveCapacity(scheduledNotes.count)
        for ev in scheduledNotes where ev.onSec <= now && now < ev.offSec {
            nowLit.insert(Int(ev.midi))
        }
        let added = nowLit.subtracting(lastFrameLitNotes)
        let removed = lastFrameLitNotes.subtracting(nowLit)
        for midi in added { highlightSink?.noteOn(midi) }
        for midi in removed { highlightSink?.noteOff(midi, channel: 0) }
        lastFrameLitNotes = nowLit
    }
}

// MARK: - CADisplayLink target shim

/// Breaks the `CADisplayLink` → `TakePlaybackEngine` retain cycle.
///
/// `CADisplayLink` strongly retains its target; this proxy holds a weak
/// reference back so the engine can be deallocated even if a stale display
/// link fires before `invalidate()` returns.
private final class VisualLinkProxy: NSObject {
    private weak var owner: TakePlaybackEngine?

    init(_ owner: TakePlaybackEngine) {
        self.owner = owner
        super.init()
    }

    @MainActor @objc func tick() {
        owner?.visualTick()
    }
}
