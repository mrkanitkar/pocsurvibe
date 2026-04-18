import AVFoundation
import Foundation
import Observation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Microphone permission status.
public enum MicrophonePermissionStatus: Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Manages microphone and other permission requests.
/// Request in context (first practice attempt), NOT at app launch, per Apple HIG.
@MainActor
@Observable
public final class PermissionManager: PermissionProviding {
    public static let shared = PermissionManager()

    /// Current microphone permission status.
    public var microphoneStatus: MicrophonePermissionStatus = .notDetermined

    /// Whether the user has been shown the denied-state message.
    ///
    /// Set to `true` after the "microphone denied" inline message is displayed in a
    /// pitch-detection view (Sing/Exercise step), so the message is not repeatedly shown
    /// on every view appearance.
    public var hasShownDeniedMessage: Bool = false

    private static let logger = Logger.survibe(category: "Permissions")

    private init() {
        updateMicrophoneStatus()
    }

    /// Check and update the current microphone permission status.
    public func updateMicrophoneStatus() {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            microphoneStatus = .notDetermined
        case .denied:
            microphoneStatus = .denied
        case .granted:
            microphoneStatus = .authorized
        @unknown default:
            microphoneStatus = .restricted
        }
        Self.logger.debug(
            "Microphone status updated: \(String(describing: self.microphoneStatus))"
        )
    }

    /// Request microphone access. Call in context (first practice), NOT at launch.
    /// Returns true if permission was granted.
    public func requestMicrophoneAccess() async -> Bool {
        guard microphoneStatus == .notDetermined else {
            return microphoneStatus == .authorized
        }

        Self.logger.info("Requesting microphone permission...")
        let granted = await AVAudioApplication.requestRecordPermission()
        updateMicrophoneStatus()
        Self.logger.info(
            "Microphone permission result: \(granted ? "granted" : "denied")"
        )
        return granted
    }

    /// URL to open iOS Settings for this app (when mic access is denied).
    public var settingsURL: URL? {
        #if canImport(UIKit)
        URL(string: UIApplication.openSettingsURLString)
        #else
        nil
        #endif
    }
}
