import Foundation

/// Errors originating from audio engine, session, and playback operations.
///
/// Used by SVAudio and the app target for structured audio error handling.
/// Cases cover engine lifecycle, session configuration, and sequencer failures.
public enum AudioError: SurVibeError {
    /// The audio engine is not running when an operation requires it.
    case engineNotRunning
    /// The audio engine failed to start.
    case engineStartFailed(underlying: String)
    /// Audio session configuration failed with primary and/or fallback modes.
    case sessionConfigurationFailed(underlying: String)
    /// Both .playAndRecord and .playback session modes failed.
    case sessionFallbackFailed(primary: String, fallback: String)
    /// MIDI sequencer failed to load or play data.
    case sequencerError(underlying: String)
    /// Audio buffer creation failed (e.g., invalid format or allocation failure).
    case bufferCreationFailed(reason: String)

    public var domain: String { "SVAudio" }

    public var code: String {
        switch self {
        case .engineNotRunning: "engine_not_running"
        case .engineStartFailed: "engine_start_failed"
        case .sessionConfigurationFailed: "session_config_failed"
        case .sessionFallbackFailed: "session_fallback_failed"
        case .sequencerError: "sequencer_error"
        case .bufferCreationFailed: "buffer_creation_failed"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .engineNotRunning:
            String(localized: "Audio engine is not running.", bundle: .module)
        case .engineStartFailed(let underlying):
            String(localized: "Audio engine failed to start: \(underlying)", bundle: .module)
        case .sessionConfigurationFailed(let underlying):
            String(localized: "Audio session configuration failed: \(underlying)", bundle: .module)
        case .sessionFallbackFailed(let primary, let fallback):
            String(
                localized:
                    "Audio session failed. Primary: \(primary). Fallback: \(fallback)",
                bundle: .module
            )
        case .sequencerError(let underlying):
            String(localized: "MIDI sequencer error: \(underlying)", bundle: .module)
        case .bufferCreationFailed(let reason):
            String(localized: "Audio buffer creation failed: \(reason)", bundle: .module)
        }
    }
}
