import Foundation
import QuartzCore
import SVAudio
import SVCore
import UIKit
import os.log

/// Drives song playback by delegating to
/// `AudioEngineManager.shared.multiChannel` (the production
/// `ProductionMultiChannelEngine`). Tracks position via
/// `CADisplayLink` for notation highlighting.
///
/// SongPlaybackEngine loads MIDI data from a Song model, delegates
/// the sequencer setup + per-track sampler banking to multiChannel,
/// and parses events via MIDIParser for display. A `CADisplayLink`
/// running at up to 120 Hz (ProMotion) updates the current position
/// and note index for UI consumers.
///
/// ## Lifecycle
/// ```
/// load(song:) → play() → pause()/resume() → stop()
/// ```
///
/// ## Note Scheduling Strategy (ARCH-005)
/// The actual sequencer lives inside multiChannel and runs on the audio
/// render thread, providing sub-millisecond timing accuracy. MIDIParser
/// events are used for UI note highlighting only. Audio events are
/// completely decoupled from display timing — dropped CADisplayLink
/// frames do NOT cause missed audio events.
///
/// ## Thread Safety
/// All mutable state is isolated to `@MainActor`. multiChannel is
/// itself `@MainActor`; its internal scheduling runs on the audio
/// render thread. The `CADisplayLink` runs on the main run loop.
@Observable
@MainActor
final class SongPlaybackEngine {
    // MARK: - Public Properties

    /// Current playback state.
    private(set) var playbackState: PlaybackState = .idle

    /// Current playback position in seconds from song start.
    private(set) var currentPosition: TimeInterval = 0

    /// Index of the MIDI event currently being played (note whose
    /// `timestamp <= currentPosition < timestamp + duration`).
    /// `nil` when no note is active at the current position.
    private(set) var currentNoteIndex: Int?

    /// Index of the next MIDI event to be played after the current position.
    /// `nil` when there are no remaining events.
    private(set) var nextNoteIndex: Int?

    /// Total duration of the loaded song in seconds.
    private(set) var duration: TimeInterval = 0

    /// Parsed MIDI events for the loaded song, sorted by timestamp.
    private(set) var midiEvents: [MIDIEvent] = []

    /// Title of the currently loaded song (used for analytics).
    private(set) var songTitle: String = ""

    /// Whether the loaded song has MIDI events available for audio playback.
    /// Returns `false` for notation-only songs that lack binary MIDI data.
    var hasPlayableContent: Bool {
        !midiEvents.isEmpty
    }

    // MARK: - Private Properties

    /// True once `load(song:)` has successfully delegated the song to
    /// `AudioEngineManager.shared.multiChannel`. The actual sequencer
    /// lives inside `multiChannel`; this flag exists so transport
    /// methods can guard cleanly without reaching into the manager.
    private var hasLoadedSong = false

    /// AUD-010: CADisplayLink for UI position tracking at display refresh rate.
    /// Runs at up to 120 Hz on ProMotion devices, automatically matching the
    /// display's actual refresh rate. Paused when the app enters background.
    private var displayLink: CADisplayLink?

    /// AUD-030: Forward-only cursor for O(1) note lookup during playback.
    /// Monotonically advanced; never reset during active playback.
    private var positionCursor: Int = 0

    /// Observers for app lifecycle notifications (background/foreground).
    private var backgroundObserver: (any NSObjectProtocol)?
    private var foregroundObserver: (any NSObjectProtocol)?

    private static let logger = Logger.survibe(category: "SongPlayback")

    // MARK: - Initialization

    init() {
        observeAppLifecycle()
    }

    // Note: Cleanup is handled by stop() called from SongDetailView.onDisappear.
    // deinit cannot access @MainActor-isolated properties under strict concurrency.

    // MARK: - Public Methods

    /// Load a song's MIDI data and prepare for playback.
    ///
    /// Delegates sequencer setup to `multiChannel` for sample-accurate
    /// playback (ARCH-005). Also parses the MIDI data via `MIDIParser`
    /// to populate `midiEvents` for UI highlighting.
    /// Transitions to `.idle` on success or `.error` on failure.
    ///
    /// - Parameter song: The Song model whose `midiData` will be parsed.
    ///   If `midiData` is nil or empty, stays in `.idle` (notation-only mode).
    func load(song: Song) async {
        playbackState = .loading
        songTitle = song.title

        Self.logger.info("Loading song: \(song.title, privacy: .public)")

        guard let midiData = song.midiData, !midiData.isEmpty else {
            setNotationOnlyMode(song: song)
            return
        }

        let result = MIDIParser.parse(data: midiData)

        switch result {
        case .success(let events):
            await handleParsedEvents(events, midiData: midiData)

        case .failure(let error):
            handleParseFailure(error, songTitle: song.title)
        }
    }

    /// Configure for notation-only mode when no MIDI data is available.
    private func setNotationOnlyMode(song: Song) {
        midiEvents = []
        duration = TimeInterval(song.durationSeconds)
        currentPosition = 0
        currentNoteIndex = nil
        nextNoteIndex = nil
        hasLoadedSong = false
        playbackState = .idle

        Self.logger.info(
            "Song '\(song.title, privacy: .public)' has no MIDI data — notation-only mode"
        )
    }

    /// Set up playback state from successfully parsed MIDI events.
    private func handleParsedEvents(
        _ events: [MIDIEvent], midiData: Data
    ) async {
        midiEvents = events
        currentPosition = 0
        currentNoteIndex = nil
        nextNoteIndex = events.isEmpty ? nil : 0

        // Ensure the audio engine is running so multiChannel exists.
        do {
            try AudioEngineManager.shared.startForPlayback()
        } catch {
            Self.logger.error(
                "Audio engine start failed: \(error.localizedDescription, privacy: .public)"
            )
            playbackState = .error(error.localizedDescription)
            return
        }

        guard let multiChannel = AudioEngineManager.shared.multiChannel else {
            Self.logger.error("multiChannel unavailable after startForPlayback()")
            playbackState = .error("Audio engine unavailable")
            return
        }

        do {
            try await multiChannel.loadSong(source: .midi(midiData))
        } catch {
            let audioError = AudioError.sequencerError(underlying: error.localizedDescription)
            playbackState = .error(audioError.errorDescription ?? error.localizedDescription)
            Self.logger.error(
                "multiChannel.loadSong failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }

        // Derive duration from multiChannel; fall back to parsed events.
        if let song = multiChannel.currentSong, song.durationSeconds > 0 {
            duration = song.durationSeconds
        } else if let lastEvent = events.last {
            duration = lastEvent.timestamp + lastEvent.duration
        } else {
            duration = 0
        }

        hasLoadedSong = true
        playbackState = .idle

        Self.logger.info(
            """
            Song loaded: \(events.count) events, \
            duration=\(String(format: "%.1f", self.duration), privacy: .public)s
            """
        )
    }

    /// Handle a MIDI parse failure by transitioning to error state.
    private func handleParseFailure(
        _ error: MIDIParseError, songTitle: String
    ) {
        midiEvents = []
        duration = 0
        hasLoadedSong = false
        playbackState = .error(
            error.errorDescription ?? "Unknown MIDI parse error"
        )

        Self.logger.error(
            """
            Failed to load song '\(songTitle, privacy: .public)': \
            \(error.localizedDescription, privacy: .public)
            """
        )
    }

    /// Begin playback from the beginning of the song.
    ///
    /// Transitions from `.idle` or `.stopped` to `.playing`.
    /// Delegates to `multiChannel.play()` for sample-accurate MIDI
    /// playback. Starts the CADisplayLink (up to 120 Hz on ProMotion)
    /// for UI position tracking.
    ///
    /// Fires `songPlaybackStarted` analytics event.
    func play() {
        guard playbackState == .idle || playbackState == .stopped else {
            Self.logger.warning(
                "play() called in invalid state: \(String(describing: self.playbackState), privacy: .public)"
            )
            return
        }
        guard !midiEvents.isEmpty else {
            Self.logger.warning("play() called with no MIDI events loaded")
            return
        }
        guard hasLoadedSong, let multiChannel = AudioEngineManager.shared.multiChannel else {
            Self.logger.warning("play() called before song loaded into multiChannel")
            return
        }

        positionCursor = 0
        // stop() resets the multiChannel sequencer position to zero, then play() starts it.
        multiChannel.stop()
        do {
            try multiChannel.play()
        } catch {
            let audioError = AudioError.sequencerError(underlying: error.localizedDescription)
            playbackState = .error(audioError.errorDescription ?? error.localizedDescription)
            Self.logger.error("multiChannel.play failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        playbackState = .playing
        startDisplayLink()

        AnalyticsManager.shared.track(
            .songPlaybackStarted,
            properties: ["song_title": songTitle]
        )

        Self.logger.info("Playback started: \(self.songTitle, privacy: .public)")
    }

    /// Pause playback at the current position.
    ///
    /// Delegates to `multiChannel.pause()` (preserving its position)
    /// and stops all sounding notes. The position is preserved so
    /// `resume()` can continue from where playback left off.
    ///
    /// Fires `songPlaybackPaused` analytics event.
    func pause() {
        guard playbackState == .playing else {
            Self.logger.warning(
                "pause() called in invalid state: \(String(describing: self.playbackState), privacy: .public)"
            )
            return
        }

        AudioEngineManager.shared.multiChannel?.pause()
        playbackState = .paused

        stopDisplayLink()
        AudioEngineManager.shared.multiChannel?.stopAllTouchNotes()

        AnalyticsManager.shared.track(
            .songPlaybackPaused,
            properties: ["song_title": songTitle]
        )

        Self.logger.info(
            "Playback paused at \(String(format: "%.1f", self.currentPosition), privacy: .public)s"
        )
    }

    /// Resume playback from the paused position.
    ///
    /// Delegates to `multiChannel.play()` from its preserved position
    /// and resumes the display loop for UI updates.
    func resume() {
        guard playbackState == .paused else {
            Self.logger.warning(
                "resume() called in invalid state: \(String(describing: self.playbackState), privacy: .public)"
            )
            return
        }
        guard hasLoadedSong, let multiChannel = AudioEngineManager.shared.multiChannel else {
            Self.logger.warning("resume() called before song loaded")
            return
        }

        do {
            try multiChannel.play()
        } catch {
            let audioError = AudioError.sequencerError(underlying: error.localizedDescription)
            playbackState = .error(audioError.errorDescription ?? error.localizedDescription)
            Self.logger.error("multiChannel.play (resume) failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        playbackState = .playing
        startDisplayLink()

        Self.logger.info(
            "Playback resumed from \(String(format: "%.1f", self.currentPosition), privacy: .public)s"
        )
    }

    /// Stop playback and reset position to the beginning.
    ///
    /// Delegates to `multiChannel.stop()` (which also resets the
    /// sequencer position to zero), stops all sounding notes,
    /// and transitions to `.stopped`.
    func stop() {
        guard playbackState == .playing || playbackState == .paused else {
            Self.logger.warning(
                "stop() called in invalid state: \(String(describing: self.playbackState), privacy: .public)"
            )
            return
        }

        AudioEngineManager.shared.multiChannel?.stop()
        stopDisplayLink()
        AudioEngineManager.shared.multiChannel?.stopAllTouchNotes()

        currentPosition = 0
        currentNoteIndex = nil
        nextNoteIndex = midiEvents.isEmpty ? nil : 0
        playbackState = .stopped

        Self.logger.info("Playback stopped")
    }

    // MARK: - Private Methods — Display Link

    /// Start a CADisplayLink at up to 120 Hz for UI position tracking.
    ///
    /// AUD-010: Uses `CADisplayLink` instead of `Task.sleep` polling,
    /// synchronizing UI updates exactly to the display refresh rate.
    /// On ProMotion displays this runs at 120 Hz; on standard displays
    /// at 60 Hz. Audio events remain on the multiChannel sequencer timeline,
    /// completely decoupled from the display link cadence.
    private func startDisplayLink() {
        stopDisplayLink()
        let target = PlaybackDisplayLinkTarget(engine: self)
        let link = CADisplayLink(target: target, selector: #selector(PlaybackDisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Invalidate and release the CADisplayLink.
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Read the current playback position from `multiChannel`,
    /// update `currentNoteIndex` and `nextNoteIndex` for UI highlighting,
    /// and detect playback completion.
    ///
    /// Called by `CADisplayLink` every display frame. Visual updates ONLY —
    /// audio events are scheduled by the multiChannel sequencer on the audio
    /// render thread and are NOT triggered from this callback. Dropped frames
    /// do NOT cause missed audio events.
    ///
    /// AUD-030: Uses forward-only `positionCursor` for O(1) amortised note
    /// lookup — advances past expired events, breaks at first future event.
    fileprivate func updatePlaybackPosition() {
        guard playbackState == .playing,
              let multiChannel = AudioEngineManager.shared.multiChannel else {
            return
        }

        currentPosition = min(multiChannel.currentPositionInSeconds, duration)

        // AUD-030: Advance cursor past events whose end time has passed.
        while positionCursor < midiEvents.count,
              midiEvents[positionCursor].timestamp + midiEvents[positionCursor].duration < currentPosition {
            positionCursor += 1
        }

        // Find the active note at or just before cursor.
        var foundCurrent: Int?
        var foundNext: Int?

        if positionCursor < midiEvents.count {
            let event = midiEvents[positionCursor]
            if event.timestamp <= currentPosition,
               currentPosition < event.timestamp + event.duration {
                foundCurrent = positionCursor
                foundNext = positionCursor + 1 < midiEvents.count ? positionCursor + 1 : nil
            } else if event.timestamp > currentPosition {
                foundNext = positionCursor
            }
        }

        currentNoteIndex = foundCurrent
        nextNoteIndex = foundNext

        // Detect playback completion.
        if currentPosition >= duration {
            handlePlaybackCompletion()
        }
    }

    // MARK: - Private Methods — App Lifecycle

    /// Register for background/foreground notifications to pause/resume
    /// the CADisplayLink. The display link must be paused when the app
    /// is backgrounded to avoid wasting GPU cycles and battery.
    private func observeAppLifecycle() {
        let center = NotificationCenter.default

        backgroundObserver = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract sendable values before entering MainActor Task.
            let _ = notification.name
            Task { @MainActor [weak self] in
                self?.displayLink?.isPaused = true
                Self.logger.debug("CADisplayLink paused (app backgrounded)")
            }
        }

        foregroundObserver = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let _ = notification.name
            Task { @MainActor [weak self] in
                guard let self, self.playbackState == .playing else { return }
                self.displayLink?.isPaused = false
                Self.logger.debug("CADisplayLink resumed (app foregrounded)")
            }
        }
    }

    /// Handle natural end-of-song: fire analytics, clean up, transition to idle.
    private func handlePlaybackCompletion() {
        AudioEngineManager.shared.multiChannel?.stop()
        stopDisplayLink()
        AudioEngineManager.shared.multiChannel?.stopAllTouchNotes()

        currentPosition = duration
        currentNoteIndex = nil
        nextNoteIndex = nil
        playbackState = .idle

        AnalyticsManager.shared.track(
            .songPlaybackCompleted,
            properties: [
                "song_title": songTitle,
                "duration_seconds": Int(duration),
            ]
        )

        Self.logger.info(
            "Playback completed: \(self.songTitle, privacy: .public) (\(Int(self.duration))s)"
        )
    }
}

// MARK: - CADisplayLink target shim

/// Breaks the CADisplayLink -> SongPlaybackEngine retain cycle.
///
/// CADisplayLink strongly retains its target. A weak-reference shim prevents
/// the engine from being kept alive by the display link after `stopDisplayLink()`.
/// Same pattern used by `MIDINoteHighlightCoordinator`.
private final class PlaybackDisplayLinkTarget: NSObject {
    private weak var engine: SongPlaybackEngine?

    init(engine: SongPlaybackEngine) {
        self.engine = engine
    }

    @MainActor @objc func tick(_ link: CADisplayLink) {
        engine?.updatePlaybackPosition()
    }
}
