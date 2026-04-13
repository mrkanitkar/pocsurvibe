import AVFoundation
import os

/// Metronome player using AVAudioPlayerNode with sample-accurate AVAudioTime scheduling.
///
/// Instead of wall-clock `DispatchSourceTimer` (which drifts 1-5ms due to OS scheduling),
/// beats are pre-scheduled on the audio engine's sample timeline using `AVAudioTime`.
/// A look-ahead loop runs via `Task.sleep`, scheduling 4 beats ahead to ensure the
/// audio hardware always has upcoming beats queued.
@MainActor
public final class MetronomePlayer: MetronomePlaying {
    // MARK: - Properties

    public static let shared = MetronomePlayer()

    /// Reference to the engine's metronome player node.
    private var playerNode: AVAudioPlayerNode {
        AudioEngineManager.shared.metronomeNode
    }

    /// Beats per minute (default: 60).
    public private(set) var bpm: Double = 60.0

    /// Whether the metronome is currently running.
    public private(set) var isPlaying: Bool = false

    /// Pre-loaded click buffer for efficient scheduling.
    private var clickBuffer: AVAudioPCMBuffer?

    /// Async scheduling task that pre-schedules beats ahead on the audio timeline.
    private var schedulerTask: Task<Void, Never>?

    /// Number of beats to schedule ahead of the current playback position.
    private let lookAheadBeats = 4

    private static let logger = Logger.survibe(category: "Metronome")

    /// Signposter for Instruments profiling of click scheduling intervals.
    private static let signposter = OSSignposter(subsystem: "com.survibe", category: "Metronome")

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Load a click sound for the metronome. Pre-loads into buffer.
    /// - Parameter url: URL to the click audio file (.wav, .aif)
    public func loadClick(at url: URL) throws {
        let audioFile = try AVAudioFile(forReading: url)
        let frameCount = AVAudioFrameCount(audioFile.length)
        let format = audioFile.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(
                domain: "MetronomePlayer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create PCM buffer"]
            )
        }
        try audioFile.read(into: buffer)
        clickBuffer = buffer
    }

    /// Start the metronome at the current BPM.
    ///
    /// Captures the engine's current sample time as a reference point, then
    /// launches a scheduling loop that pre-schedules beats at exact sample
    /// positions on the audio timeline.
    public func start() {
        guard !isPlaying else { return }
        guard clickBuffer != nil else {
            Self.logger.error("start: no click buffer loaded")
            return
        }

        isPlaying = true
        playerNode.play()

        let sampleRate = AudioSessionManager.shared.sampleRate
        guard sampleRate > 0 else {
            Self.logger.error("start: sampleRate is 0")
            isPlaying = false
            return
        }

        // Get the engine's current sample time as our reference anchor
        let startSampleTime = currentSampleTime()

        Self.logger.info(
            "Starting metronome: bpm=\(self.bpm) sampleRate=\(sampleRate) startSample=\(startSampleTime)"
        )

        startSchedulingLoop(fromSampleTime: startSampleTime, sampleRate: sampleRate)
    }

    /// Stop the metronome.
    public func stop() {
        schedulerTask?.cancel()
        schedulerTask = nil
        playerNode.stop()
        isPlaying = false
    }

    /// Update BPM. Restarts scheduling with the new interval if running.
    ///
    /// Cancels the current scheduling loop and starts a new one anchored at
    /// the engine's current sample time to avoid gaps or overlaps.
    public func setBPM(_ newBPM: Double) {
        guard newBPM.isFinite, newBPM >= 1, newBPM <= 300 else {
            Self.logger.warning("setBPM: rejected invalid value \(newBPM)")
            return
        }
        bpm = newBPM
        if isPlaying {
            schedulerTask?.cancel()
            schedulerTask = nil

            let sampleRate = AudioSessionManager.shared.sampleRate
            guard sampleRate > 0 else { return }

            let anchorSample = currentSampleTime()
            startSchedulingLoop(fromSampleTime: anchorSample, sampleRate: sampleRate)
        }
    }

    /// Set the volume of the metronome (0.0 to 1.0).
    public func setVolume(_ volume: Float) {
        AudioEngineManager.shared.setMetronomeVolume(volume)
    }

    // MARK: - Internal (Visible for Testing)

    /// Compute the sample time for a given beat index relative to a start time.
    ///
    /// - Parameters:
    ///   - beatIndex: The zero-based beat number.
    ///   - startSampleTime: The anchor sample time (beat 0).
    ///   - sampleRate: Audio sample rate in Hz.
    ///   - bpm: Beats per minute.
    /// - Returns: The exact sample time for the beat.
    nonisolated static func sampleTimeForBeat(
        _ beatIndex: Int,
        startSampleTime: AVAudioFramePosition,
        sampleRate: Double,
        bpm: Double
    ) -> AVAudioFramePosition {
        let samplesPerBeat = Int64(60.0 / bpm * sampleRate)
        return startSampleTime + Int64(beatIndex) * samplesPerBeat
    }

    // MARK: - Private Methods

    /// Get the engine's current sample time, falling back to 0 if unavailable.
    private func currentSampleTime() -> AVAudioFramePosition {
        guard let lastRenderTime = playerNode.lastRenderTime,
            lastRenderTime.isSampleTimeValid
        else {
            return 0
        }
        return lastRenderTime.sampleTime
    }

    /// Launch the async scheduling loop that pre-schedules beats on the audio timeline.
    ///
    /// The loop calculates exact sample positions for each beat and schedules them
    /// using `AVAudioPlayerNode.scheduleBuffer(_:at:)`. It sleeps between scheduling
    /// rounds — the sleep is NOT used for timing; it only controls how often we
    /// schedule the next batch of beats.
    private func startSchedulingLoop(
        fromSampleTime startSampleTime: AVAudioFramePosition,
        sampleRate: Double
    ) {
        schedulerTask = Task { [weak self] in
            var nextBeatIndex = 0

            while !Task.isCancelled {
                guard let self else { return }

                // Schedule the next batch of beats ahead
                let signpostID = Self.signposter.makeSignpostID()
                let signpostState = Self.signposter.beginInterval("ClickScheduling", id: signpostID)

                for offset in 0..<self.lookAheadBeats {
                    let beatIndex = nextBeatIndex + offset
                    let beatSampleTime = Self.sampleTimeForBeat(
                        beatIndex,
                        startSampleTime: startSampleTime,
                        sampleRate: sampleRate,
                        bpm: self.bpm
                    )
                    let beatTime = AVAudioTime(sampleTime: beatSampleTime, atRate: sampleRate)
                    self.scheduleClick(at: beatTime)
                }

                Self.signposter.endInterval("ClickScheduling", signpostState)

                nextBeatIndex += self.lookAheadBeats

                // Sleep for roughly the duration of the scheduled batch.
                // This is NOT timing-critical — beats are already pre-scheduled on the
                // audio timeline using exact AVAudioTime sample positions. The sleep only
                // controls how often we schedule the next batch. (Reviewed: M-5 false positive)
                let sleepSeconds = 60.0 / self.bpm * Double(self.lookAheadBeats) * 0.8
                let sleepNanoseconds = UInt64(sleepSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
            }
        }
    }

    /// Schedule a single click sound at an exact audio time.
    private func scheduleClick(at time: AVAudioTime) {
        guard let clickBuffer else { return }
        playerNode.scheduleBuffer(clickBuffer, at: time)
    }
}
