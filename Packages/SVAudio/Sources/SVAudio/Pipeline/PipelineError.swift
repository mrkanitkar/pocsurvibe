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
/// track / channel counts and per-track instrument programs.
public struct RenderedMIDI: Equatable, Sendable {
    public let data: Data
    public let trackCount: Int
    /// Distinct MIDI channels seen across all tracks (0-indexed; 9 = percussion).
    public let channels: [UInt8]
    /// Per-music-track metadata in source order. The conductor track
    /// (which has no notes / channel-voice events) is excluded so this
    /// array indexes the same way as `AVAudioSequencer.tracks`.
    public let trackInfo: [TrackInfo]
    /// Tempo in beats-per-minute derived from the first SMF meta-0x51
    /// (Set Tempo) event. Defaults to 120 BPM when no tempo event is
    /// present — the MIDI specification's implied default.
    public let originalBPM: Double

    public init(
        data: Data, trackCount: Int, channels: [UInt8], trackInfo: [TrackInfo] = [],
        originalBPM: Double = 120.0
    ) {
        self.data = data
        self.trackCount = trackCount
        self.channels = channels
        self.trackInfo = trackInfo
        self.originalBPM = originalBPM
    }
}

/// Per-track MIDI metadata extracted by walking the SMF byte stream.
public struct TrackInfo: Equatable, Sendable {
    /// First MIDI channel observed on the track (0-indexed; 9 = percussion).
    public let channel: UInt8
    /// First Program Change event's program number, or `nil` if the track
    /// emits notes without setting a program. Callers should fall back
    /// to a sensible default preset when this is `nil`.
    public let program: UInt8?
    /// True if any event on this track uses MIDI channel 9 (the GM
    /// percussion convention). Callers should load the SF2 percussion
    /// bank for this sampler instead of a melodic preset.
    public let isPercussion: Bool
    /// Human-readable track name from SMF meta event 0x03
    /// (Sequence/Track Name), or `nil` if the track contains none.
    public let trackName: String?
    /// Instrument name from SMF meta event 0x04 (Instrument Name),
    /// or `nil` if the track contains none.
    public let instrumentName: String?

    public init(
        channel: UInt8, program: UInt8?, isPercussion: Bool,
        trackName: String? = nil, instrumentName: String? = nil
    ) {
        self.channel = channel
        self.program = program
        self.isPercussion = isPercussion
        self.trackName = trackName
        self.instrumentName = instrumentName
    }
}
