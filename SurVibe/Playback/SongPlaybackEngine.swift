import AVFoundation
import Foundation
import SVAudio
import SVCore
import os

/// Drives song playback using AVAudioSequencer for sample-accurate MIDI
/// scheduling and tracks position for notation highlighting.
///
/// SongPlaybackEngine loads MIDI data from a Song model, configures an
/// AVAudioSequencer routed to AudioEngineManager's sampler, and parses
/// events via MIDIParser for display. A 30 Hz Task loop updates the
/// current position and note index for UI consumers (e.g., notation
/// scroll views, progress bars).
///
/// ## Lifecycle
/// ```
/// load(song:) → play() → pause()/resume() → stop()
/// ```
///
/// ## Note Scheduling Strategy (ARCH-005)
/// Uses AVAudioSequencer for sample-accurate MIDI playback, replacing
/// the previous Task.sleep-based scheduling. The sequencer runs on the
/// audio render thread, eliminating the ~10ms jitter of wall-clock
/// scheduling. MIDIParser events are still used for UI note highlighting.
///
/// ## Thread Safety
/// All mutable state is isolated to `@MainActor`. The sequencer is
/// created and controlled from MainActor; its internal scheduling
/// runs on the audio render thread.
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

    /// AVAudioSequencer for sample-accurate MIDI playback (ARCH-005).
    /// Replaces Task.sleep scheduling for sub-millisecond timing accuracy.
    /// Created during `load(song:)` and routed to AudioEngineManager's sampler.
    private var sequencer: AVAudioSequencer?

    /// AUD-010: Task-based display loop replaces `Timer` + `Task { @MainActor }`.
    /// A single Task sleeping 33 ms (~30 Hz) avoids the extra actor hop that
    /// `Timer` + `Task { @MainActor in }` incurred per tick.
    private var displayLinkTask: Task<Void, Never>?

    /// AUD-030: Forward-only cursor for O(1) note lookup during playback.
    /// Monotonically advanced; never reset during active playback.
    private var positionCursor: Int = 0

    private static let logger = Logger.survibe(category: "SongPlayback")

    /// Signposter for Instruments profiling of playback tick intervals.
    private static let signposter = OSSignposter(subsystem: "com.survibe", category: "SongPlayback")

    // MARK: - Initialization

    init() {}

    // Note: Cleanup is handled by stop() called from SongDetailView.onDisappear.
    // deinit cannot access @MainActor-isolated properties under strict concurrency.

    // MARK: - Public Methods

    /// Load a song's MIDI data and prepare for playback.
    ///
    /// Creates an AVAudioSequencer routed to the shared sampler for
    /// sample-accurate playback (ARCH-005). Also parses the MIDI data
    /// via `MIDIParser` to populate `midiEvents` for UI highlighting.
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
        sequencer = nil
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

        do {
            try await SoundFontManager.shared.loadBundledPiano()
        } catch {
            Self.logger.error(
                "SoundFont load failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        do {
            try configureSequencer(midiData: midiData, events: events)
        } catch {
            return
        }

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
        sequencer = nil
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
    /// Resets the sequencer position to zero and starts it for
    /// sample-accurate MIDI playback. Starts the 30 Hz display loop
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
        guard let sequencer else {
            Self.logger.warning("play() called with no sequencer configured")
            return
        }

        positionCursor = 0
        sequencer.currentPositionInSeconds = 0

        do {
            try sequencer.start()
        } catch {
            let audioError = AudioError.sequencerError(underlying: error.localizedDescription)
            playbackState = .error(audioError.errorDescription ?? error.localizedDescription)
            Self.logger.error("Sequencer start failed: \(error.localizedDescription, privacy: .public)")
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
    /// Stops the sequencer (preserving its position) and stops all
    /// sounding notes. The position is preserved so `resume()` can
    /// continue from where playback left off.
    ///
    /// Fires `songPlaybackPaused` analytics event.
    func pause() {
        guard playbackState == .playing else {
            Self.logger.warning(
                "pause() called in invalid state: \(String(describing: self.playbackState), privacy: .public)"
            )
            return
        }

        sequencer?.stop()
        playbackState = .paused

        stopDisplayLink()
        SoundFontManager.shared.stopAllNotes()

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
    /// Restarts the sequencer from its preserved position and
    /// resumes the display loop for UI updates.
    func resume() {
        guard playbackState == .paused else {
            Self.logger.warning(
                "resume() called in invalid state: \(String(describing: self.playbackState), privacy: .public)"
            )
            return
        }
        guard let sequencer else {
            Self.logger.warning("resume() called with no sequencer configured")
            return
        }

        do {
            try sequencer.start()
        } catch {
            let audioError = AudioError.sequencerError(underlying: error.localizedDescription)
            playbackState = .error(audioError.errorDescription ?? error.localizedDescription)
            Self.logger.error("Sequencer resume failed: \(error.localizedDescription, privacy: .public)")
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
    /// Stops the sequencer, resets its position to zero, stops all
    /// sounding notes, and transitions to `.stopped`.
    func stop() {
        guard playbackState == .playing || playbackState == .paused else {
            Self.logger.warning(
                "stop() called in invalid state: \(String(describing: self.playbackState), privacy: .public)"
            )
            return
        }

        sequencer?.stop()
        sequencer?.currentPositionInSeconds = 0

        stopDisplayLink()
        SoundFontManager.shared.stopAllNotes()

        currentPosition = 0
        currentNoteIndex = nil
        nextNoteIndex = midiEvents.isEmpty ? nil : 0
        playbackState = .stopped

        Self.logger.info("Playback stopped")
    }

    // MARK: - Private Methods — Sequencer Setup

    /// Create and configure the AVAudioSequencer from raw MIDI data.
    ///
    /// Loads the MIDI data, routes all tracks to the shared sampler,
    /// and derives the playback duration. On failure, transitions to
    /// `.error` state and throws to signal the caller to bail out.
    ///
    /// - Parameters:
    ///   - midiData: Raw Standard MIDI File bytes.
    ///   - events: Parsed MIDIEvent array for fallback duration calculation.
    /// - Throws: `AudioError.sequencerError` if the sequencer fails to load.
    private func configureSequencer(midiData: Data, events: [MIDIEvent]) throws {
        do {
            let seq = AVAudioSequencer(audioEngine: AudioEngineManager.shared.engine)
            try seq.load(from: midiData, options: .smf_ChannelsToTracks)

            // Route all tracks to the shared sampler so notes play through
            // the SoundFont piano instead of the default General MIDI synth.
            for track in seq.tracks {
                track.destinationAudioUnit = AudioEngineManager.shared.sampler
            }

            seq.prepareToPlay()

            // Derive duration from sequencer track lengths (most accurate source).
            duration = seq.tracks.reduce(0) { max($0, $1.lengthInSeconds) }

            // Fall back to parsed event duration if sequencer reports zero
            // (can happen with malformed tempo maps).
            if duration <= 0, let lastEvent = events.last {
                duration = lastEvent.timestamp + lastEvent.duration
            }

            sequencer = seq
        } catch {
            let audioError = AudioError.sequencerError(underlying: error.localizedDescription)
            playbackState = .error(audioError.errorDescription ?? error.localizedDescription)
            Self.logger.error("Sequencer load failed: \(error.localizedDescription, privacy: .public)")
            throw audioError
        }
    }

    // MARK: - Private Methods — Display Link

    /// Start a ~30 Hz Task loop to update playback position and note indices.
    ///
    /// AUD-010: Uses a Task instead of `Timer` + `Task { @MainActor in }`,
    /// eliminating the extra actor hop per tick that Timer callbacks incurred.
    private func startDisplayLink() {
        stopDisplayLink()
        displayLinkTask = Task { [weak self] in
            while !Task.isCancelled {
                // try? is intentional — Task.sleep throws CancellationError on task cancel, which is expected control flow.
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled else { return }
                self?.updatePlaybackPosition()
            }
        }
    }

    /// Cancel the display loop task.
    private func stopDisplayLink() {
        displayLinkTask?.cancel()
        displayLinkTask = nil
    }

    /// Read the current playback position from the sequencer,
    /// update `currentNoteIndex` and `nextNoteIndex` for UI highlighting,
    /// and detect playback completion.
    ///
    /// AUD-030: Uses forward-only `positionCursor` for O(1) amortised note
    /// lookup — advances past expired events, breaks at first future event.
    private func updatePlaybackPosition() {
        guard playbackState == .playing, let sequencer else {
            return
        }

        let signpostID = Self.signposter.makeSignpostID()
        let signpostState = Self.signposter.beginInterval("PlaybackTick", id: signpostID)

        currentPosition = min(sequencer.currentPositionInSeconds, duration)

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

        Self.signposter.endInterval("PlaybackTick", signpostState)

        // Detect playback completion.
        if currentPosition >= duration {
            handlePlaybackCompletion()
        }
    }

    /// Handle natural end-of-song: fire analytics, clean up, transition to idle.
    private func handlePlaybackCompletion() {
        sequencer?.stop()
        stopDisplayLink()
        SoundFontManager.shared.stopAllNotes()

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
