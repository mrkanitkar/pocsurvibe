import Foundation

/// Protocol for permission checking and requesting.
///
/// Decouples ViewModels from `PermissionManager` singleton, enabling
/// test doubles for microphone permission flows without actual hardware.
@MainActor
public protocol PermissionProviding: Sendable {
    /// Current microphone permission status.
    var microphoneStatus: MicrophonePermissionStatus { get }

    /// URL to the app's Settings page for permission management.
    var settingsURL: URL? { get }

    /// Refresh the cached microphone permission status from the system.
    func updateMicrophoneStatus()

    /// Request microphone access. Returns true if granted.
    func requestMicrophoneAccess() async -> Bool
}
