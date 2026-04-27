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
        let createdFile: AVAudioFile
        do {
            createdFile = try AVAudioFile(forWriting: outputURL, settings: settings)
        } catch {
            throw PipelineError.bounceFailed(reason: "AVAudioFile create failed: \(error.localizedDescription)")
        }
        self.file = createdFile

        // Fix C3 (review 2026-04-26): defensively remove any pre-existing tap
        // before installing. AVAudioNode.installTap traps with
        // "required condition is false: nullptr == Tap()" if a tap is already
        // attached. The `isTapping` guard above only protects within a single
        // bouncer instance — callers that construct a fresh bouncer per bounce
        // (e.g. AuditionPipelineSection.bounce) can race past the section's
        // `isBouncing` flag and attempt to install two taps on the same node.
        // `removeTap` is a no-op when no tap exists, so this is always safe.
        source.removeTap(onBus: 0)

        // Bug 1 fix (2026-04-27, third attempt — the actual root cause).
        //
        // First two attempts (capture-fixing) did NOT work because the
        // problem isn't the capture — it's the CLOSURE TYPE. Per Apple
        // docs (verified 2026-04-27):
        //   typealias AVAudioNodeTapBlock = (AVAudioPCMBuffer, AVAudioTime) -> Void
        // is NOT @Sendable. installTap's `block:` parameter is also not
        // @Sendable. So when we write a trailing closure inside @MainActor
        // start(), Swift 6 strict mode INFERS the closure literal as
        // @MainActor-isolated (the rule: a non-Sendable closure literal in
        // an actor-isolated scope inherits that actor). At every CoreAudio
        // invocation on RealtimeMessenger.mServiceQueue, the runtime calls
        // dispatch_assert_queue(main) — fails — traps with EXC_BREAKPOINT.
        // Confirmed across 4 crash logs (15:10:52, 15:24:09, 15:25:58,
        // 15:30:09) all sharing identical signature.
        //
        // The fix mirrors the project's existing AudioEngineManager.installMicTap
        // pattern: declare the block as @Sendable explicitly. The compiler
        // accepts a @Sendable closure where a plain AVAudioNodeTapBlock is
        // expected (subtyping). The @Sendable annotation forces the closure
        // to NOT inherit @MainActor, which strips the runtime isolation
        // check, which lets CoreAudio invoke the closure on its own queue
        // without trapping.
        //
        // The TapWriter wrapper is still required: the @Sendable closure
        // can only capture Sendable values, and AVAudioFile is not Sendable
        // in Swift 6. CLAUDE.md / .claude/rules/audio.md permits
        // @unchecked Sendable for CoreMIDI interop; CoreAudio realtime
        // tap callbacks are the same category (audio.md notes
        // MIDIInputManager uses OSAllocatedUnfairLock for the same reason).
        let writer = TapWriter(file: createdFile)
        let tapBlock: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
            writer.write(buffer)
        }
        source.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: format, block: tapBlock)
        isTapping = true
        bouncerLogger.info("Started bounce → \(self.outputURL.lastPathComponent, privacy: .public)")
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

/// Sendable wrapper around an `AVAudioFile` so the tap closure can capture
/// it without inheriting `@MainActor` from `RealtimeTapBouncer.start()`.
///
/// Marked `@unchecked Sendable` because `AVAudioFile` itself is not Sendable
/// in Swift 6 — but `AVAudioFile.write(from:)` is thread-safe per Apple's
/// "Performing Offline Audio Processing" sample. CoreAudio invokes the tap
/// on `RealtimeMessenger.mServiceQueue` (a single dispatch queue), so calls
/// are already serialized; the only concurrent access would be the main
/// actor reading `RealtimeTapBouncer.file` for stop/abort, which doesn't
/// touch this wrapper's `file` reference at all (it sets the parent's
/// `file = nil` to release the wrapper's strong ref).
///
/// CLAUDE.md permits `@unchecked Sendable` for CoreMIDI interop; CoreAudio
/// realtime callbacks (this case) are the same category.
private final class TapWriter: @unchecked Sendable {
    private let file: AVAudioFile

    init(file: AVAudioFile) {
        self.file = file
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        // Drop write errors silently — `bouncerLogger` would re-introduce
        // actor isolation. Stop() finalizes whatever was successfully written.
        try? file.write(from: buffer)
    }
}
