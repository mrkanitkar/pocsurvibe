import AVFoundation
import Foundation
import VerovioToolkit
import os

private let verovioLogger = Logger.survibe(category: "VerovioBridge")

/// Wraps Verovio's Swift toolkit so callers can hand it a MusicXML
/// string and get MIDI `Data` plus a track/channel summary.
///
/// Not `Sendable` — `VerovioToolkit` holds C++ state and must be
/// confined to a single thread. We pin it to `@MainActor`.
@MainActor
public final class VerovioBridge {

    // MARK: - Properties

    private let toolkit: VerovioToolkit

    // MARK: - Initialization

    /// Create a bridge with Verovio's bundled resources (fonts, SVG
    /// shapes, MIDI program maps) preloaded.
    ///
    /// The Verovio Swift Package ships its `data/` resource folder via
    /// `Bundle.module` (re-exported as `VerovioResources.bundle`). We
    /// resolve the on-disk path and pass it to the toolkit's resource
    /// initializer so `loadData` can succeed without manual setup. If
    /// the bundle resource path can't be resolved, we fall back to the
    /// no-resource init — Verovio will emit a warning but most
    /// MusicXML → MIDI paths still render.
    public init() {
        if let dataURL = VerovioResources.bundle.url(forResource: "data", withExtension: nil) {
            self.toolkit = VerovioToolkit(dataURL.path)
            verovioLogger.info("Initialized with data path: \(dataURL.path, privacy: .public)")
        } else {
            self.toolkit = VerovioToolkit()
            verovioLogger.warning("Initialized WITHOUT data path — Verovio resources not found in bundle")
        }
    }

    // MARK: - Public Methods

    /// Render a MusicXML score to MIDI bytes.
    ///
    /// Loads the score into the toolkit, asks Verovio for a
    /// base64-encoded MIDI string, decodes it to `Data`, and walks the
    /// byte stream once to count tracks and observed MIDI channels.
    ///
    /// - Parameter musicXML: A complete MusicXML 3.x or 4.x document.
    /// - Returns: `RenderedMIDI` with raw `Data`, track count, and the
    ///            distinct MIDI channels observed across all tracks.
    /// - Throws: `PipelineError.verovioRenderFailed` if Verovio rejects
    ///           the input or returns empty output.
    ///           `PipelineError.midiDecodeFailed` if base64 decode fails.
    public func render(musicXML: String) throws -> RenderedMIDI {
        let xmlBytes = musicXML.utf8.count
        verovioLogger.info("render: input MusicXML \(xmlBytes, privacy: .public) bytes")
        guard toolkit.loadData(musicXML) else {
            verovioLogger.error("render: loadData rejected input")
            throw PipelineError.verovioRenderFailed(reason: "Verovio loadData rejected input")
        }
        let base64 = toolkit.renderToMIDI()
        let b64Len = base64.count
        verovioLogger.info("render: renderToMIDI base64 length=\(b64Len, privacy: .public)")
        guard !base64.isEmpty else {
            verovioLogger.error("render: renderToMIDI returned empty string")
            throw PipelineError.verovioRenderFailed(reason: "renderToMIDI returned empty string")
        }
        guard let midiData = Data(base64Encoded: base64) else {
            verovioLogger.error("render: base64 decode failed (length=\(b64Len, privacy: .public))")
            throw PipelineError.midiDecodeFailed
        }
        let midiBytes = midiData.count
        let summary = try Self.summarize(midi: midiData)
        let chList = summary.channels.map { String($0) }.joined(separator: ",")
        let trackCount = summary.trackCount
        verovioLogger.info(
            """
            render: ok midi=\(midiBytes, privacy: .public)B \
            tracks=\(trackCount, privacy: .public) \
            channels=[\(chList, privacy: .public)]
            """
        )
        return RenderedMIDI(
            data: midiData, trackCount: trackCount, channels: summary.channels
        )
    }

    // MARK: - Private Methods

    /// Walk the MIDI byte stream once, counting `MTrk` chunks and
    /// channel bytes seen on any channel-voice status (0x80–0xEF).
    ///
    /// - Parameter midi: Raw Standard MIDI File bytes.
    /// - Returns: Tuple of track count and the sorted set of distinct
    ///            channel nibbles encountered.
    /// - Throws: `PipelineError.verovioRenderFailed` if the buffer is
    ///           shorter than the minimum SMF header.
    nonisolated private static func summarize(
        midi: Data
    ) throws -> (trackCount: Int, channels: [UInt8]) {
        let bytes = [UInt8](midi)
        guard bytes.count >= 14 else {
            throw PipelineError.verovioRenderFailed(reason: "MIDI too short to parse header")
        }
        var trackCount = 0
        var channelSet = Set<UInt8>()
        var i = 0
        while i + 4 <= bytes.count {
            let chunkID = Data(bytes[i..<i + 4])
            // MTrk = 0x4D 0x54 0x72 0x6B
            if chunkID == Data([0x4D, 0x54, 0x72, 0x6B]) {
                trackCount += 1
                guard i + 8 <= bytes.count else { break }
                let length = UInt32(bytes[i + 4]) << 24 |
                             UInt32(bytes[i + 5]) << 16 |
                             UInt32(bytes[i + 6]) << 8  |
                             UInt32(bytes[i + 7])
                let trackEnd = min(i + 8 + Int(length), bytes.count)
                var j = i + 8
                while j < trackEnd {
                    let status = bytes[j]
                    if status >= 0x80 && status < 0xF0 {
                        channelSet.insert(status & 0x0F)
                    }
                    j += 1
                }
                i = trackEnd
            } else {
                i += 1
            }
        }
        return (trackCount, channelSet.sorted())
    }
}
