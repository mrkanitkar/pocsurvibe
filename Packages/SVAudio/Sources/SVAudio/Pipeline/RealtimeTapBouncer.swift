import AVFoundation
import Foundation
import os

private let bouncerLogger = Logger.survibe(category: "RealtimeTapBouncer")

/// Tap-based real-time bouncer. Captures audio off a source `AVAudioNode`
/// (typically the audition sub-mixer) into an `.m4a` AAC file.
///
/// Why not `enableManualRenderingMode(.offline)`?
/// `AVAudioSequencer` produces silence in offline manual rendering mode
/// (Apple Forums thread 79698, unresolved as of iOS 26). Real-time tap
/// avoids that bug at the cost of taking wall-clock time.
@MainActor
public final class RealtimeTapBouncer {

    /// Source node to tap. The audition pipeline uses the sub-mixer so
    /// the bounce excludes other engine audio (tanpura, metronome).
    private let source: AVAudioNode

    /// Destination file URL. `.m4a` extension required.
    private let outputURL: URL

    /// The open AVAudioFile for the active capture, or nil when not tapping.
    /// Captured by-value into the tap closure at install time so the closure
    /// does not need to touch `self` on the audio thread (Swift 6 friendly).
    private var file: AVAudioFile?

    private var isTapping = false

    /// Tap buffer size — 4096 frames is a good balance between callback
    /// overhead and write granularity (~93 ms at 44100 Hz).
    private static let tapBufferSize: AVAudioFrameCount = 4096

    public init(source: AVAudioNode, outputURL: URL) {
        self.source = source
        self.outputURL = outputURL
    }

    /// Begin capturing. Idempotent — a no-op if already capturing.
    /// - Throws: `PipelineError.bounceFailed` if `AVAudioFile` creation fails.
    public func start() throws {
        guard !isTapping else { return }
        let format = source.outputFormat(forBus: 0)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 128_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let openedFile: AVAudioFile
        do {
            openedFile = try AVAudioFile(forWriting: outputURL, settings: settings)
        } catch {
            throw PipelineError.bounceFailed(
                reason: "AVAudioFile create failed: \(error.localizedDescription)"
            )
        }
        self.file = openedFile

        // Fix C3 (review 2026-04-26): defensively remove any pre-existing tap
        // before installing. AVAudioNode.installTap traps with
        // "required condition is false: nullptr == Tap()" if a tap is already
        // attached. The `isTapping` guard above only protects within a single
        // bouncer instance — callers that construct a fresh bouncer per bounce
        // (e.g. AuditionPipelineSection.bounce) can race past the section's
        // `isBouncing` flag and attempt to install two taps on the same node.
        // `removeTap` is a no-op when no tap exists, so this is always safe.
        source.removeTap(onBus: 0)

        // Capture the AVAudioFile by value into the tap closure. The closure
        // runs on a high-priority audio thread; it never touches `self` or
        // any MainActor state. AVAudioFile.write(from:) is thread-safe when
        // called from a single concurrent context (the tap callback is the
        // only writer for the file's lifetime).
        source.installTap(
            onBus: 0,
            bufferSize: Self.tapBufferSize,
            format: format
        ) { buffer, _ in
            do {
                try openedFile.write(from: buffer)
            } catch {
                bouncerLogger.error(
                    "Tap write failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        isTapping = true
        bouncerLogger.info(
            "Started bounce → \(self.outputURL.lastPathComponent, privacy: .public)"
        )
    }

    /// Stop capturing and finalize the file. Safe to call multiple times.
    public func stop() {
        guard isTapping else { return }
        source.removeTap(onBus: 0)
        file = nil  // releases AVAudioFile, finalizing the .m4a
        isTapping = false
        bouncerLogger.info("Stopped bounce")
    }

    /// Stop capturing AND delete the partial file. For interruption /
    /// background / disk-full / user-cancel paths.
    public func abort() {
        if isTapping {
            source.removeTap(onBus: 0)
            file = nil
            isTapping = false
        }
        try? FileManager.default.removeItem(at: outputURL)
        bouncerLogger.info("Aborted bounce; partial file removed")
    }
}
