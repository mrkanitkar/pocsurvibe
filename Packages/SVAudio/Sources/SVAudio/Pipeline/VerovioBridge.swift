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
            PipelineFileLog.shared.log("VerovioBridge.init: dataPath=\(dataURL.path)")
        } else {
            self.toolkit = VerovioToolkit()
            verovioLogger.warning("Initialized WITHOUT data path — Verovio resources not found in bundle")
            PipelineFileLog.shared.log("VerovioBridge.init: NO DATA PATH (resources missing)")
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
        PipelineFileLog.shared.log("VerovioBridge.render: input MusicXML \(xmlBytes) bytes")
        guard toolkit.loadData(musicXML) else {
            verovioLogger.error("render: loadData rejected input")
            PipelineFileLog.shared.log("VerovioBridge.render: ERROR loadData rejected input")
            throw PipelineError.verovioRenderFailed(reason: "Verovio loadData rejected input")
        }
        let base64 = toolkit.renderToMIDI()
        let b64Len = base64.count
        verovioLogger.info("render: renderToMIDI base64 length=\(b64Len, privacy: .public)")
        guard !base64.isEmpty else {
            verovioLogger.error("render: renderToMIDI returned empty string")
            PipelineFileLog.shared.log("VerovioBridge.render: ERROR renderToMIDI returned empty")
            throw PipelineError.verovioRenderFailed(reason: "renderToMIDI returned empty string")
        }
        guard let midiData = Data(base64Encoded: base64) else {
            verovioLogger.error("render: base64 decode failed (length=\(b64Len, privacy: .public))")
            PipelineFileLog.shared.log("VerovioBridge.render: ERROR base64 decode failed len=\(b64Len)")
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
        PipelineFileLog.shared.log(
            "VerovioBridge.render: OK midi=\(midiBytes)B tracks=\(trackCount) channels=[\(chList)]"
        )
        for (idx, info) in summary.trackInfo.enumerated() {
            let progStr = info.program.map { String($0) } ?? "nil"
            PipelineFileLog.shared.log(
                """
                  music-track[\(idx)] channel=\(info.channel) \
                  program=\(progStr) percussion=\(info.isPercussion)
                """
            )
        }
        return RenderedMIDI(
            data: midiData,
            trackCount: trackCount,
            channels: summary.channels,
            trackInfo: summary.trackInfo
        )
    }

    // MARK: - Private Methods

    /// Walk the MIDI byte stream once. Counts `MTrk` chunks and, for each
    /// chunk, properly parses MIDI events (variable-length deltas, running
    /// status, meta/sysex, channel-voice events) to extract the first
    /// MIDI channel observed and the first Program Change program — so
    /// each sampler in the multi-track graph can load the per-part
    /// instrument that Verovio assigned from MusicXML's
    /// `<midi-instrument><midi-program>` tags.
    ///
    /// Tracks with no channel-voice events (the conductor / tempo track)
    /// are excluded from the returned `trackInfo` so its indexing aligns
    /// with `AVAudioSequencer.tracks`.
    ///
    /// - Parameter midi: Raw Standard MIDI File bytes.
    /// - Returns: total MTrk count, the sorted set of distinct channels
    ///            seen across the file, and per-music-track metadata.
    /// - Throws: `PipelineError.verovioRenderFailed` if the buffer is
    ///           shorter than the minimum SMF header.
    /// Summary of an SMF byte stream — total chunk count, distinct
    /// channels seen, and per-music-track metadata.
    nonisolated private struct MIDISummary {
        var trackCount: Int
        var channels: [UInt8]
        var trackInfo: [TrackInfo]
    }

    nonisolated private static func summarize(midi: Data) throws -> MIDISummary {
        let bytes = [UInt8](midi)
        guard bytes.count >= 14 else {
            throw PipelineError.verovioRenderFailed(reason: "MIDI too short to parse header")
        }
        var trackCount = 0
        var channelSet = Set<UInt8>()
        var trackInfo: [TrackInfo] = []
        var i = 0
        while i + 4 <= bytes.count {
            let chunkID = Data(bytes[i..<i + 4])
            if chunkID == Data([0x4D, 0x54, 0x72, 0x6B]) {  // "MTrk"
                trackCount += 1
                guard i + 8 <= bytes.count else { break }
                let length = UInt32(bytes[i + 4]) << 24 |
                             UInt32(bytes[i + 5]) << 16 |
                             UInt32(bytes[i + 6]) << 8  |
                             UInt32(bytes[i + 7])
                let trackEnd = min(i + 8 + Int(length), bytes.count)
                let info = parseTrack(bytes: bytes, start: i + 8, end: trackEnd)
                if info.hasChannelVoiceEvents {
                    trackInfo.append(TrackInfo(
                        channel: info.firstChannel ?? 0,
                        program: info.firstProgram,
                        isPercussion: info.isPercussion
                    ))
                    info.channels.forEach { channelSet.insert($0) }
                }
                i = trackEnd
            } else {
                i += 1
            }
        }
        return MIDISummary(
            trackCount: trackCount,
            channels: channelSet.sorted(),
            trackInfo: trackInfo
        )
    }

    /// Result of parsing one MTrk chunk.
    nonisolated private struct ParsedTrack {
        var hasChannelVoiceEvents: Bool
        var firstChannel: UInt8?
        var firstProgram: UInt8?
        var isPercussion: Bool
        var channels: Set<UInt8>
    }

    /// Single-MTrk parser. Walks events respecting variable-length deltas,
    /// running status, and meta/sysex skip. Captures the first
    /// channel-voice channel and the first Program Change program so the
    /// caller can decide which SF2 preset to load on the sampler.
    nonisolated private static func parseTrack(
        bytes: [UInt8], start: Int, end: Int
    ) -> ParsedTrack {
        var j = start
        var runningStatus: UInt8 = 0
        var hasMusic = false
        var firstChannel: UInt8?
        var firstProgram: UInt8?
        var channels = Set<UInt8>()
        var isPercussion = false

        while j < end {
            // Skip variable-length delta time
            while j < end, bytes[j] & 0x80 != 0 { j += 1 }
            j += 1  // last delta byte
            if j >= end { break }

            var status = bytes[j]
            if status & 0x80 != 0 {
                // New status byte
                j += 1
                if status < 0xF0 {
                    runningStatus = status
                }
            } else {
                // Running status — reuse last channel-voice status
                status = runningStatus
            }

            if status == 0xFF {
                // Meta event: type byte + variable-length length + data
                guard j < end else { break }
                j += 1  // type
                var len = 0
                while j < end {
                    let lb = bytes[j]
                    j += 1
                    len = (len << 7) | Int(lb & 0x7F)
                    if lb & 0x80 == 0 { break }
                }
                j += len
            } else if status == 0xF0 || status == 0xF7 {
                // SysEx: variable-length length + data
                var len = 0
                while j < end {
                    let lb = bytes[j]
                    j += 1
                    len = (len << 7) | Int(lb & 0x7F)
                    if lb & 0x80 == 0 { break }
                }
                j += len
            } else if status >= 0x80 && status < 0xF0 {
                // Channel-voice event
                hasMusic = true
                let channel = status & 0x0F
                channels.insert(channel)
                if firstChannel == nil { firstChannel = channel }
                if channel == 9 { isPercussion = true }

                let high = status & 0xF0
                if high == 0xC0 {
                    // Program Change: 1 data byte
                    if j < end {
                        if firstProgram == nil { firstProgram = bytes[j] }
                        j += 1
                    }
                } else if high == 0xD0 {
                    // Channel Pressure: 1 data byte
                    if j < end { j += 1 }
                } else {
                    // Note On/Off, Poly Pressure, CC, Pitch Bend: 2 data bytes
                    j += 2
                }
            } else {
                // Unknown / malformed — bail to avoid infinite loop
                break
            }
        }

        return ParsedTrack(
            hasChannelVoiceEvents: hasMusic,
            firstChannel: firstChannel,
            firstProgram: firstProgram,
            isPercussion: isPercussion,
            channels: channels
        )
    }
}
