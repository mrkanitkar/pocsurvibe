import AVFoundation
import os

/// Classification of the granted I/O buffer duration after audio session activation.
///
/// iPad hardware may grant a buffer duration different from the requested hint.
/// This enum classifies the granted duration to help diagnose latency issues.
public enum BufferGrantTier: Sendable {
    /// Session has not been configured yet.
    case unknown
    /// Granted buffer duration is 7 ms or less — ideal for real-time MIDI playback.
    case excellent
    /// Granted buffer duration is between 7 ms and 12 ms — acceptable latency.
    case acceptable
    /// Granted buffer duration exceeds 12 ms — may cause perceptible latency.
    case degraded
}

/// Protocol for the AVAudioSession deactivation call.
///
/// Used internally to allow test doubles to verify that
/// `.notifyOthersOnDeactivation` is always passed per Apple HIG.
/// See: https://developer.apple.com/documentation/avfaudio/avaudiosession/setactiveoptions/notifyothersondeactivation
protocol AudioSessionDeactivating: Sendable {
    /// Activates or deactivates the audio session with the given options.
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

extension AVAudioSession: AudioSessionDeactivating {}

/// Manages AVAudioSession configuration for simultaneous input/output.
/// Uses @MainActor isolation for thread-safe callback management.
///
/// Category: .playAndRecord, Mode: .measurement
/// Options: [.defaultToSpeaker, .mixWithOthers]
///
/// Bluetooth HFP is intentionally NOT enabled. HFP forces narrowband
/// 8/16 kHz mono audio which destroys pitch detection accuracy. Users
/// on BT headsets fall back to the built-in speaker and mic.
@MainActor
public final class AudioSessionManager {
    public static let shared = AudioSessionManager()

    private static let logger = Logger.survibe(category: "AudioSessionManager")

    private let session = AVAudioSession.sharedInstance()

    /// Backing session used exclusively for `deactivate()`.
    ///
    /// Defaults to `AVAudioSession.sharedInstance()`. Overridden in tests with
    /// a spy to assert `.notifyOthersOnDeactivation` is passed every time.
    let deactivatingSession: any AudioSessionDeactivating

    /// Whether the microphone is unavailable due to session configuration fallback.
    ///
    /// When `true`, the audio session is in `.playback` mode because `.playAndRecord`
    /// failed (e.g., MDM restriction). SoundFont playback works; mic input does not.
    public private(set) var isMicUnavailable: Bool = false

    /// The buffer grant tier from the most recent session activation.
    ///
    /// Updated after each call to `configure()` or `configureForPlayback()`.
    /// Remains `.unknown` until the first successful activation.
    public private(set) var lastBufferGrantTier: BufferGrantTier = .unknown

    /// Observer tokens for NotificationCenter — removed in `deinit` to prevent leaks.
    /// `nonisolated(unsafe)` is required because `deinit` is nonisolated but these
    /// properties live on a @MainActor class. This is safe because:
    /// 1. They are set exactly once during `init()` (on MainActor) and never mutated after.
    /// 2. `deinit` only reads them to call `removeObserver`, which is thread-safe.
    nonisolated(unsafe) private var interruptionObserver: (any NSObjectProtocol)?
    nonisolated(unsafe) private var routeChangeObserver: (any NSObjectProtocol)?

    private init() {
        deactivatingSession = AVAudioSession.sharedInstance()
        setupInterruptionObserver()
        setupRouteChangeObserver()
    }

    /// Package-internal initialiser used by tests to inject a deactivation spy.
    ///
    /// - Parameter deactivatingSession: A test double that records `setActive(_:options:)` calls.
    init(deactivatingSession: any AudioSessionDeactivating) {
        self.deactivatingSession = deactivatingSession
        setupInterruptionObserver()
        setupRouteChangeObserver()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
    }

    /// Configure audio session for simultaneous playback and recording.
    ///
    /// Uses a 256-frame I/O buffer (~5.33 ms at 48 kHz) to minimise
    /// SoundFont playback latency for MIDI-triggered notes. Pitch detection
    /// in `PracticeAudioProcessor` accumulates its own internal buffer, so it
    /// is unaffected by this smaller hardware I/O window.
    ///
    /// iPad native hardware rate is 48 kHz. Requesting 44.1 kHz forced an
    /// OS-level sample-rate-conversion stage that added unnecessary latency.
    ///
    /// A 46ms buffer (2048 frames) was unnecessarily large; professional
    /// MIDI playback apps typically use 128–256 frames.
    public func configure() throws {
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .mixWithOthers]
            )
            // Request 48 kHz — iPad native rate avoids OS sample-rate conversion.
            try session.setPreferredSampleRate(48000)
            // 256 frames at 48 kHz ≈ 5.33 ms — low-latency for MIDI-triggered SoundFont playback.
            // PracticeAudioProcessor accumulates its own buffer, so pitch detection is unaffected.
            try session.setPreferredIOBufferDuration(256.0 / 48000.0)
            try session.setActive(true)
            classifyBufferGrant()
            // Some iPad models ship with inputGain=0.5; quiet voice/acoustic
            // playing then registers below the DSP's 0.002 RMS gate. Raise to
            // full scale when the hardware allows it — does not affect
            // latency, only SNR above the noise floor. Apple documents that
            // most built-in mics return `isInputGainSettable == false`, so
            // the guard is expected to short-circuit on several devices.
            if session.isInputGainSettable {
                do {
                    try session.setInputGain(1.0)
                    Self.logger.info("Input gain set to 1.0")
                } catch {
                    Self.logger.warning(
                        "setInputGain(1.0) failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            isMicUnavailable = false
            Self.logger.info("Audio session configured: .playAndRecord")
        } catch {
            Self.logger.error(
                "Failed to configure .playAndRecord: \(error.localizedDescription, privacy: .public)"
            )
            isMicUnavailable = true
            // Fallback to playback-only so SoundFont output still works.
            // If this also fails, let the error propagate to the caller.
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setPreferredSampleRate(48000)
            try session.setActive(true)
            classifyBufferGrant()
            Self.logger.warning("Audio session fallback active: .playback (mic unavailable)")
        }
    }

    /// Configure audio session for playback only (no microphone input).
    ///
    /// Uses `.playback` category to avoid triggering a microphone permission prompt.
    /// Suitable for SoundFont-based MIDI playback via AVAudioUnitSampler.
    ///
    /// Requests 48 kHz sample rate (iPad native) and a 256-frame I/O buffer
    /// (~5.33 ms). After activation, classifies the granted buffer duration
    /// into a ``BufferGrantTier`` for latency diagnostics.
    public func configureForPlayback() throws {
        try session.setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers]
        )
        // 48 kHz — iPad native rate avoids OS sample-rate conversion.
        try session.setPreferredSampleRate(48000)
        // 256 frames at 48 kHz ≈ 5.33 ms — low-latency for MIDI playback.
        try session.setPreferredIOBufferDuration(256.0 / 48000.0)
        try session.setActive(true)
        classifyBufferGrant()
    }

    /// Deactivate the audio session and notify other apps.
    ///
    /// Passes `.notifyOthersOnDeactivation` so that apps that ducked their
    /// audio for SurVibe (Music, Podcasts, etc.) receive a signal to ramp
    /// back up. Required by Apple HIG for apps that play temporary audio.
    /// See: https://developer.apple.com/documentation/avfaudio/avaudiosession/setactiveoptions/notifyothersondeactivation
    ///
    /// Logs a warning on failure rather than silently swallowing the error.
    public func deactivate() {
        do {
            try deactivatingSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Self.logger.warning("Audio session deactivation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether other audio is currently playing.
    public var isOtherAudioPlaying: Bool {
        session.isOtherAudioPlaying
    }

    /// Current sample rate of the audio session.
    public var sampleRate: Double {
        session.sampleRate
    }

    // MARK: - Buffer Grant Classification

    /// Read the granted `ioBufferDuration` and classify it into a tier.
    ///
    /// Called after every successful `setActive(true)` to record what the
    /// hardware actually granted (which may differ from the preferred hint).
    private func classifyBufferGrant() {
        let granted = session.ioBufferDuration
        let grantedMs = granted * 1000.0
        if grantedMs <= 7.0 {
            lastBufferGrantTier = .excellent
        } else if grantedMs <= 12.0 {
            lastBufferGrantTier = .acceptable
        } else {
            lastBufferGrantTier = .degraded
        }
        let tierName = String(describing: lastBufferGrantTier)
        Self.logger.info(
            "IO buffer granted: \(grantedMs, format: .fixed(precision: 2), privacy: .public) ms → \(tierName, privacy: .public)"
        )
    }

    // MARK: - Interruption Handling

    /// Callback invoked when audio is interrupted (phone call, Siri, etc.).
    ///
    /// Marked `@Sendable` because it is called from a `NotificationCenter` observer
    /// that dispatches to MainActor via `Task`. Callers must not capture non-Sendable state.
    public var onInterruptionBegan: (@Sendable () -> Void)?

    /// Callback invoked when audio interruption ends.
    ///
    /// - Parameter shouldResume: `true` if the system recommends resuming playback.
    /// Marked `@Sendable` — see `onInterruptionBegan` for rationale.
    public var onInterruptionEnded: (@Sendable (Bool) -> Void)?

    /// Callback invoked when the audio route changes (e.g., Bluetooth connect/disconnect).
    ///
    /// Marked `@Sendable` — see `onInterruptionBegan` for rationale.
    public var onRouteChange: (@Sendable () -> Void)?

    /// Fired alongside `onRouteChange` but carries the specific reason.
    ///
    /// Use this for Play Along to distinguish `.oldDeviceUnavailable` (pause + toast)
    /// from other route changes such as `.newDeviceAvailable` or `.categoryChange`.
    /// Marked `@Sendable` — see `onInterruptionBegan` for rationale.
    public var onRouteChangeWithReason: (@Sendable (AVAudioSession.RouteChangeReason) -> Void)?

    private func setupInterruptionObserver() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            // Extract Sendable values before crossing isolation boundary
            // (Notification is not Sendable — cannot be passed into Task)
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        }
    }

    private func setupRouteChangeObserver() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            // Extract Sendable values before crossing isolation boundary
            // (Notification is not Sendable — cannot be passed into Task)
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                let reason = reasonValue.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
                self?.handleRouteChange(reason: reason)
            }
        }
    }

    /// Handle a route change, firing both legacy and reason-carrying callbacks.
    ///
    /// Extracted as an internal method so tests can invoke it directly without
    /// posting a `routeChangeNotification`.
    ///
    /// - Parameter reason: The route change reason, or `nil` if unknown.
    func handleRouteChange(reason: AVAudioSession.RouteChangeReason?) {
        onRouteChange?()
        if let reason {
            onRouteChangeWithReason?(reason)
        }
    }

    func handleInterruption(typeValue: UInt?, optionsValue: UInt?) {
        guard let typeValue,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        switch type {
        case .began:
            onInterruptionBegan?()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            let shouldResume = options.contains(.shouldResume)
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }
}
