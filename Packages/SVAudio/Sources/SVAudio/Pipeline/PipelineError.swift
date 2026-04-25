import Foundation

/// Errors that can occur in the audition `.mxl` → multi-channel pipeline.
public enum PipelineError: Error, LocalizedError, Equatable {

    /// A required bundled asset (e.g. `james-bond-theme.mxl`) is missing.
    case resourceMissing(name: String)

    /// The `.mxl` zip container could not be unwrapped or its
    /// `META-INF/container.xml` could not be parsed.
    case mxlUnzipFailed(reason: String)

    /// Verovio rejected the MusicXML or produced no MIDI output.
    case verovioRenderFailed(reason: String)

    /// Verovio's base64-encoded MIDI string failed to decode to `Data`.
    case midiDecodeFailed

    /// The rendered MIDI has more tracks than the pipeline supports
    /// (MIDI cap is 16 channels per port; full orchestral scores
    /// exceed this and require sub-mixing — out of POC scope).
    case tooManyTracks(found: Int, max: Int)

    /// `AudioEngineManager.shared.engine` is not running.
    case engineNotRunning

    /// The realtime tap bounce failed (disk, format, interruption, etc.).
    case bounceFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            return "Resource '\(name)' is not bundled in AuditionAssets/."
        case .mxlUnzipFailed(let reason):
            return "Could not unzip .mxl container: \(reason)"
        case .verovioRenderFailed(let reason):
            return "Verovio render failed: \(reason)"
        case .midiDecodeFailed:
            return "Verovio MIDI base64 decode failed."
        case .tooManyTracks(let found, let max):
            return "Score has \(found) parts; pipeline supports max \(max)."
        case .engineNotRunning:
            return "AudioEngineManager.shared.engine is not running."
        case .bounceFailed(let reason):
            return "Bounce failed: \(reason)"
        }
    }
}

/// Output of `VerovioBridge.render(...)` — raw MIDI bytes plus a
/// pre-parsed summary so callers don't need to re-parse to learn
/// track / channel counts.
public struct RenderedMIDI: Equatable, Sendable {
    public let data: Data
    public let trackCount: Int
    /// Distinct MIDI channels seen across all tracks (0-indexed; 9 = percussion).
    public let channels: [UInt8]

    public init(data: Data, trackCount: Int, channels: [UInt8]) {
        self.data = data
        self.trackCount = trackCount
        self.channels = channels
    }
}
