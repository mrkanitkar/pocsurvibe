import AVFoundation
import os

/// Manages AVAudioSession configuration for simultaneous input/output.
/// Uses @MainActor isolation for thread-safe callback management.
///
/// Category: .playAndRecord, Mode: .measurement
/// Options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
@MainActor
public final class AudioSessionManager {
    public static let shared = AudioSessionManager()

    private static let logger = Logger.survibe(category: "AudioSessionManager")

    private let session = AVAudioSession.sharedInstance()

    /// Observer tokens for NotificationCenter — removed in `deinit` to prevent leaks.
    /// `nonisolated(unsafe)` is required because `deinit` is nonisolated but these
    /// properties live on a @MainActor class. This is safe because:
    /// 1. They are set exactly once during `init()` (on MainActor) and never mutated after.
    /// 2. `deinit` only reads them to call `removeObserver`, which is thread-safe.
    nonisolated(unsafe) private var interruptionObserver: (any NSObjectProtocol)?
    nonisolated(unsafe) private var routeChangeObserver: (any NSObjectProtocol)?

    private init() {
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
    /// Uses a 256-frame I/O buffer (~5.8ms at 44100 Hz) to minimise
    /// SoundFont playback latency for MIDI-triggered notes. Pitch detection
    /// in `PracticeAudioProcessor` accumulates its own internal buffer, so it
    /// is unaffected by this smaller hardware I/O window.
    ///
    /// A 46ms buffer (2048 frames) was unnecessarily large; professional
    /// MIDI playback apps typically use 128–256 frames.
    public func configure() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
        )
        // Request 44100 Hz sample rate per spec
        try session.setPreferredSampleRate(44100)
        // 256 frames at 44100 Hz ≈ 5.8 ms — low-latency for MIDI-triggered SoundFont playback.
        // PracticeAudioProcessor accumulates its own buffer, so pitch detection is unaffected.
        try session.setPreferredIOBufferDuration(256.0 / 44100.0)
        try session.setActive(true)
    }

    /// Configure audio session for playback only (no microphone input).
    ///
    /// Uses `.playback` category to avoid triggering a microphone permission prompt.
    /// Suitable for SoundFont-based MIDI playback via AVAudioUnitSampler.
    public func configureForPlayback() throws {
        try session.setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers]
        )
        try session.setPreferredSampleRate(44100)
        try session.setActive(true)
    }

    /// Deactivate the audio session.
    /// Logs a warning on failure rather than silently swallowing the error.
    public func deactivate() {
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
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
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onRouteChange?()
            }
        }
    }

    private func handleInterruption(typeValue: UInt?, optionsValue: UInt?) {
        guard let typeValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
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
