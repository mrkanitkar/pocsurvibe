// SurVibe/PlayAlong/Lean/SongPlayAlongViewModel.swift
// swiftlint:disable file_length
import AVFoundation
import Foundation
import QuartzCore
import SVAudio
import SVCore
import SVLearning
import SwiftData
import SwiftUI
import os

/// Single view-model for Songs Play Along — lean rewrite.
///
/// Owns the full playback graph (no four-coordinator facade, no
/// `ArrangementPlayer` wrapper). Mirrors `PlayTabViewModel`'s
/// architecture: one `@Observable`, one isolated tick state, direct
/// engine wiring.
///
/// ## What it owns
/// - The loaded `Song` and parsed `[NoteEvent]`.
/// - A `MultiTrackSamplerGraph` for SoundFont rendering.
/// - A `TakePlaybackEngine` driving the `AVAudioSequencer`.
/// - A wall-clock cursor source (`CACurrentMediaTime`-based).
/// - The isolated `SongPlayAlongTickState`.
/// - Lean `SongPlayAlongScoring`.
/// - The mic `PracticeAudioProcessor`.
///
/// ## What writes to `tickState`
/// The `TakePlaybackEngine.onVisualTick` callback. That's it. Every
/// SwiftUI invalidation visible during playback originates from that
/// one place — body never reads `tickState` directly.
@Observable
@MainActor
final class SongPlayAlongViewModel {

    // MARK: - Observed public state (low-frequency only)

    /// High-level transport state.
    private(set) var playbackState: PlaybackState = .idle

    /// The currently loaded song, `nil` until `loadSong(_:)` returns.
    private(set) var song: Song?

    /// Parsed MIDI events for visualization. Empty during load.
    private(set) var noteEvents: [NoteEvent] = []

    /// Song duration in seconds, derived from `noteEvents.last`.
    private(set) var duration: TimeInterval = 0

    /// Human-readable error surface for the UI.
    private(set) var errorMessage: String?

    /// `1.0` = original tempo. Clamped on assignment to `[0.5, 1.5]`.
    /// Forwards to `MultiTrackSamplerGraph.setTempoScale(_:)` which
    /// sets `AVAudioSequencer.rate` — the same path used by Play tab.
    var tempoScale: Double = 1.0 {
        didSet {
            let clamped = min(1.5, max(0.5, tempoScale))
            if clamped != tempoScale {
                tempoScale = clamped
                return
            }
            samplerGraph?.setTempoScale(Float(clamped))
        }
    }

    /// Isolated tick state — only leaf views read this.
    let tickState = SongPlayAlongTickState()

    /// Lazily created on first `loadSong`. Resets on restart.
    private(set) var scoring: SongPlayAlongScoring?

    // MARK: - Private — audio + clock

    private var samplerGraph: MultiTrackSamplerGraph?
    private var playbackEngine: TakePlaybackEngine?

    /// VM-owned `CADisplayLink` — drives `handleVisualTick()` on the
    /// main runloop at display refresh rate. Started on `play()`,
    /// stopped on `pause()` / `stop()` / `cleanup()`. The VM owns this
    /// (not the engine) so the engine layer stays generic — the engine
    /// only plays audio, the VM advances visualization.
    private var displayLink: CADisplayLink?

    /// Wall-clock baseline. `CACurrentMediaTime()` at the most recent
    /// play/resume. While `clockRunning`, `currentTime = clockAccum +
    /// (now - clockBase)`. On pause, fold the delta into `clockAccum`
    /// and flip `clockRunning` off.
    private var clockBase: TimeInterval = 0
    private var clockAccum: TimeInterval = 0
    private var clockRunning: Bool = false

    // MARK: - Private — pitch detection

    private var pitchDetector: PracticeAudioProcessor?
    private var pitchTask: Task<Void, Never>?
    private var lastPitchPublishAt: TimeInterval = 0
    private static let pitchPublishInterval: TimeInterval = 0.1  // 10 Hz max

    /// SwiftData context — set by the view's `.task` after navigation.
    var modelContext: ModelContext?

    private static let logger = Logger.survibe(category: "SongPlayAlong")

    // MARK: - Init

    init() {}

    // MARK: - Public — lifecycle

    /// Load a Song's MIDI into the audio graph and prepare for playback.
    ///
    /// On success, `playbackState` transitions to `.idle` (ready to play),
    /// `noteEvents` is populated, and `duration` is set. On any failure,
    /// `playbackState = .error` and `errorMessage` carries the reason.
    func loadSong(_ s: Song) async {
        playbackState = .loading
        song = s
        errorMessage = nil

        guard let midiData = s.midiData, !midiData.isEmpty else {
            finishWithError("Song has no playable MIDI data.")
            return
        }

        // Parse for visualization.
        switch MIDIParser.parse(data: midiData) {
        case .success(let events):
            let parsed = NoteEvent.fromMIDI(events: events)
            noteEvents = parsed
            if let last = parsed.last {
                duration = last.timestamp + last.duration
            }
            scoring = SongPlayAlongScoring(totalNotes: parsed.count)
        case .failure(let err):
            finishWithError("MIDI parse failed: \(err.localizedDescription)")
            return
        }

        // Start the shared engine if it isn't running already.
        do {
            try AudioEngineManager.shared.startForPlayback()
        } catch {
            finishWithError("Audio engine start failed: \(error.localizedDescription)")
            return
        }
        guard let multiChannel = AudioEngineManager.shared.multiChannel else {
            finishWithError("Audio engine unavailable.")
            return
        }

        // Build the sampler graph for the song's track count.
        do {
            let rendered = try VerovioBridge.summarizeSMF(midiData)
            let trackCount = max(1, min(rendered.trackInfo.count, MultiTrackSamplerGraph.maxTracks))
            let graph = try MultiTrackSamplerGraph(trackCount: trackCount)
            if let bankURL = MultiTrackSamplerGraph.activeSoundFontURL() {
                let presets: [UInt8] = (0..<graph.samplers.count).map { i in
                    if i < rendered.trackInfo.count, let p = rendered.trackInfo[i].program {
                        return p
                    }
                    return 0
                }
                try? graph.loadBank(at: bankURL, presets: presets)
            }
            samplerGraph = graph

            // Build the playback engine over that graph.
            let avEngine = AudioEngineManager.shared.engine
            let engine = TakePlaybackEngine(
                multiChannel: multiChannel,
                highlightSink: nil,
                engine: avEngine
            )
            try engine.loadSMFData(
                midiData,
                graph: graph,
                instrumentProgram: rendered.trackInfo.first?.program ?? 0
            )
            playbackEngine = engine
        } catch {
            finishWithError("Failed to prepare song: \(error.localizedDescription)")
            return
        }

        playbackState = .idle
        let durStr = String(format: "%.1f", duration)
        Self.logger.info(
            "Loaded \(s.title, privacy: .public) — \(self.noteEvents.count) notes, \(durStr, privacy: .public)s"
        )
    }

    // MARK: - Public — transport

    /// Begin playback. From `.idle` or `.stopped` only.
    func play() async {
        guard playbackState == .idle || playbackState == .stopped else { return }
        guard !noteEvents.isEmpty else { return }

        resetWallClock()
        startWallClock()
        startDisplayLink()

        // Engine seek + start. Engine may be nil in tests; that's fine.
        playbackEngine?.seek(toSec: 0)
        playbackEngine?.play()
        playbackState = .playing
    }

    /// Pause playback in place.
    func pause() {
        guard playbackState == .playing else { return }
        pauseWallClock()
        stopDisplayLink()
        playbackEngine?.pause()
        playbackState = .paused
    }

    /// Resume playback from the paused position.
    func resume() {
        guard playbackState == .paused else { return }
        startWallClock()
        startDisplayLink()
        playbackEngine?.play()
        playbackState = .playing
    }

    /// Stop + reset to song start. Clears scoring.
    func restart() async {
        playbackEngine?.stop()
        stopDisplayLink()
        resetWallClock()
        scoring?.reset()
        tickState.reset()
        playbackState = .idle
        await play()
    }

    /// Tear down playback and clear all transient state. Called from the
    /// view's `.onDisappear`.
    func cleanup() {
        pitchTask?.cancel()
        pitchTask = nil
        pitchDetector?.stop()
        pitchDetector = nil
        stopDisplayLink()
        playbackEngine?.stop()
        playbackEngine = nil
        samplerGraph = nil
        tickState.reset()
        scoring?.reset()
        resetWallClock()
        playbackState = .idle
        Self.logger.info("VM cleanup complete")
    }

    // MARK: - Private — display link

    /// Install a `CADisplayLink` on the main runloop. Idempotent.
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let proxy = DisplayLinkProxy { [weak self] in
            self?.handleVisualTick()
        }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Invalidate the active display link. Idempotent.
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: - Public — keyboard input

    /// Handle a note-on from the on-screen piano. Adds to user-press set
    /// and counts a hit if the pressed key matches a currently-active
    /// sequenced note.
    func handleKeyboardNoteOn(_ midi: Int) {
        tickState.userPressedNotes.insert(midi)
        if tickState.activeMidiNotes.contains(midi) {
            scoring?.recordHit()
        }
    }

    /// Handle a note-off from the on-screen piano.
    func handleKeyboardNoteOff(_ midi: Int) {
        tickState.userPressedNotes.remove(midi)
    }

    // MARK: - Public — mic pitch detection

    /// Start the mic pitch stream. Idempotent.
    func startPitchDetection() {
        guard pitchDetector == nil else { return }
        let processor = PracticeAudioProcessor()
        pitchDetector = processor
        do {
            try processor.start()
        } catch {
            Self.logger.error("Pitch start failed: \(error.localizedDescription, privacy: .public)")
            pitchDetector = nil
            return
        }
        pitchTask = Task { [weak self] in
            guard let stream = self?.pitchDetector?.pitchStream else { return }
            for await result in stream {
                await MainActor.run {
                    self?.publishPitchIfDue(result)
                }
            }
        }
    }

    private func publishPitchIfDue(_ result: PitchResult) {
        let now = CACurrentMediaTime()
        guard now - lastPitchPublishAt >= Self.pitchPublishInterval else { return }
        lastPitchPublishAt = now
        if result.amplitude >= PracticeConstants.silenceThreshold,
            result.confidence >= PracticeConstants.confidenceThreshold {
            tickState.detectedPitch = result
        } else if tickState.detectedPitch != nil {
            tickState.detectedPitch = nil
        }
    }

    // MARK: - Private — error path

    private func finishWithError(_ message: String) {
        errorMessage = message
        playbackState = .error(message)
        Self.logger.error("\(message, privacy: .public)")
    }

    // MARK: - Private — wall clock

    private func startWallClock() {
        clockBase = CACurrentMediaTime()
        clockRunning = true
    }

    private func pauseWallClock() {
        guard clockRunning else { return }
        clockAccum += CACurrentMediaTime() - clockBase
        clockRunning = false
    }

    private func resetWallClock() {
        clockBase = 0
        clockAccum = 0
        clockRunning = false
    }

    /// Smooth wall-clock position. Used by `handleVisualTick`.
    private var wallClockSec: TimeInterval {
        if clockRunning {
            return clockAccum + (CACurrentMediaTime() - clockBase)
        }
        return clockAccum
    }

    // MARK: - Private — visual tick (the core fix)

    /// Visual-tick handler installed on `TakePlaybackEngine.onVisualTick`.
    /// Reads the wall clock, advances `tickState`, detects natural
    /// completion. Writes only to `tickState` — never to any property
    /// the parent body reads.
    private func handleVisualTick() {
        guard playbackState == .playing else { return }
        let t = wallClockSec
        advanceFor(time: t)
    }

    #if DEBUG
    /// Drive the tick handler with a synthetic clock value. Tests use this
    /// instead of waiting on a real `CADisplayLink`.
    func tickForTesting(at t: TimeInterval) {
        advanceFor(time: t)
    }

    /// Install pre-built note events for tests, bypassing `loadSong`.
    func installNoteEventsForTesting(_ events: [NoteEvent]) {
        noteEvents = events
        if let last = events.last {
            duration = last.timestamp + last.duration
        }
        scoring = SongPlayAlongScoring(totalNotes: events.count)
        playbackState = .idle
    }
    #endif

    /// Single source of truth for the per-tick cursor + active-set + completion
    /// update. Writes only to `tickState`.
    private func advanceFor(time t: TimeInterval) {
        guard !noteEvents.isEmpty else { return }

        // Natural completion.
        if playbackState == .playing, duration > 0, t >= duration {
            completeNaturally()
            return
        }

        tickState.currentTime = t

        // Binary search: first index whose timestamp > t. `lastStarted` is
        // one back — the last note that has started by time t.
        var lo = 0
        var hi = noteEvents.count
        while lo < hi {
            let mid = (lo &+ hi) >> 1
            if noteEvents[mid].timestamp <= t { lo = mid &+ 1 } else { hi = mid }
        }
        let lastStarted: Int? = lo > 0 ? lo - 1 : nil

        // Walk back up to 64 events to gather chord members still sustaining.
        var newActive: Set<Int> = []
        var lowestActive: Int?
        if let last = lastStarted {
            var i = last
            let lowerBound = max(0, last - 64)
            while i >= lowerBound {
                let ev = noteEvents[i]
                if t < ev.timestamp + ev.duration {
                    newActive.insert(Int(ev.midiNote))
                    lowestActive = i
                }
                if i == 0 { break }
                i -= 1
            }
        }

        let newIndex = lowestActive ?? lastStarted
        if tickState.currentNoteIndex != newIndex {
            tickState.currentNoteIndex = newIndex
        }
        if tickState.activeMidiNotes != newActive {
            tickState.activeMidiNotes = newActive
        }
    }

    private func completeNaturally() {
        playbackEngine?.stop()
        stopDisplayLink()
        pauseWallClock()
        playbackState = .stopped
        Self.logger.info(
            "Song completed: \(self.song?.title ?? "<unknown>", privacy: .public)"
        )
    }
}
// swiftlint:enable file_length

/// `CADisplayLink` requires an `NSObject` target. This proxy holds a weak
/// reference back to the VM so an in-flight tick after `invalidate()` becomes
/// a no-op instead of a use-after-free.
private final class DisplayLinkProxy: NSObject {
    private let callback: @MainActor () -> Void

    init(callback: @escaping @MainActor () -> Void) {
        self.callback = callback
    }

    @MainActor
    @objc
    func tick() {
        callback()
    }
}

