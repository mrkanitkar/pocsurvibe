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

    // MARK: - RenderOptions

    /// Knobs that control how `VerovioBridge` configures the toolkit
    /// before rendering a score to SVG + MIDI.
    ///
    /// The defaults are tuned for the Learn-a-Song pipeline: lyrics are
    /// preserved so learners can sing along.
    ///
    /// Voice-staff-always-visible behavior is handled at the score-renderer
    /// level (Wave 5+), not here — Verovio doesn't expose a clean filter
    /// for "keep this part visible regardless of selection".
    public struct RenderOptions: Sendable, Equatable {
        /// When `true` (default), lyric `<text>` syllables that appear in
        /// the source MusicXML are surfaced in Verovio's SVG output as
        /// `<g class="lyric ...">` nodes. When `false`, all `<lyric>`
        /// elements are stripped from the MusicXML *before* it reaches
        /// Verovio — there is no Verovio toolkit option that suppresses
        /// lyric rendering directly, so we pre-process the input string
        /// (trade-off: an extra regex pass on the XML, no toolkit churn).
        public var includeLyrics: Bool

        public init(includeLyrics: Bool = true) {
            self.includeLyrics = includeLyrics
        }
    }

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
            let nameStr = info.trackName ?? "nil"
            let instrStr = info.instrumentName ?? "nil"
            PipelineFileLog.shared.log(
                """
                  music-track[\(idx)] channel=\(info.channel) \
                  program=\(progStr) percussion=\(info.isPercussion) \
                  name=\(nameStr) instrument=\(instrStr)
                """
            )
        }
        let bpm = summary.originalBPM
        PipelineFileLog.shared.log(
            "VerovioBridge.render: originalBPM=\(bpm)"
        )
        return RenderedMIDI(
            data: midiData,
            trackCount: trackCount,
            channels: summary.channels,
            trackInfo: summary.trackInfo,
            originalBPM: bpm
        )
    }

    /// Render a MusicXML score to MIDI bytes *and* one SVG page per
    /// Verovio page, with caller-controlled lyric handling.
    ///
    /// This is the Learn-a-Song-friendly variant of `render(musicXML:)`.
    /// Compared to the MIDI-only path, it additionally:
    ///   1. Pre-processes the MusicXML to strip `<lyric>...</lyric>`
    ///      elements when `options.includeLyrics == false` (Verovio has
    ///      no first-class option to suppress lyric rendering, so we
    ///      operate on the input string).
    ///   2. Configures Verovio's lyric layout knobs (`lyricElision`,
    ///      `lyricVerseCollapse`) before `loadData`.
    ///   3. After MIDI is produced, also iterates `getPageCount()` and
    ///      collects each page's SVG so the UI can paint the score.
    ///
    /// The MIDI half of the result is identical to what `render(musicXML:)`
    /// returns for the same (post-pre-processed) input.
    ///
    /// - Parameters:
    ///   - musicXML: A complete MusicXML 3.x or 4.x document.
    ///   - options: Lyric / voice-staff knobs. Defaults are lyric-friendly.
    /// - Returns: `RenderedScore` with `midi` and per-page `svgPages`.
    /// - Throws: `PipelineError.verovioRenderFailed` if Verovio rejects
    ///           the input, returns empty MIDI, or fails to apply options.
    ///           `PipelineError.midiDecodeFailed` if base64 decode fails.
    public func render(musicXML: String, options: RenderOptions) throws -> RenderedScore {
        // Step 1: Apply lyric layout options. We always set the lyric knobs
        // to predictable values so test runs are deterministic regardless
        // of toolkit state from prior renders.
        let optsJSON = """
            {"lyricElision": true, "lyricVerseCollapse": false}
            """
        if !toolkit.setOptions(optsJSON) {
            verovioLogger.warning("render(options): setOptions returned false; continuing")
            PipelineFileLog.shared.log("VerovioBridge.render(options): WARN setOptions=false")
        }
        // Step 2: Pre-process the MusicXML to strip <lyric>...</lyric>
        // when the caller doesn't want lyrics. Verovio has no first-class
        // toolkit option to suppress lyric rendering, so we operate on
        // the input string. This is a measured trade-off: one regex pass
        // over the XML is cheaper than re-rendering and post-processing
        // the SVG, and it also keeps the rendered MIDI free of any lyric
        // meta events that downstream parts of the pipeline don't need.
        let xml = options.includeLyrics ? musicXML : Self.stripLyrics(from: musicXML)
        // Step 3: MIDI render via the existing path (same input).
        let midi = try render(musicXML: xml)
        // Step 4: Collect SVG pages. `getPageCount()` returns the number
        // of pages Verovio produced for the most recent `loadData` call.
        // We pass `xmlDeclaration: false` so each page is a self-contained
        // <svg> element suitable for direct embedding.
        let pageCount = toolkit.getPageCount()
        var svgPages: [String] = []
        if pageCount > 0 {
            svgPages.reserveCapacity(pageCount)
            // Verovio page numbering is 1-based.
            for page in 1...pageCount {
                let svg = toolkit.renderToSVG(page, false)
                svgPages.append(svg)
            }
        }
        let pageBytes = svgPages.reduce(0) { $0 + $1.utf8.count }
        verovioLogger.info(
            """
            render(options): pages=\(pageCount, privacy: .public) \
            svgBytes=\(pageBytes, privacy: .public) \
            includeLyrics=\(options.includeLyrics, privacy: .public)
            """
        )
        PipelineFileLog.shared.log(
            "VerovioBridge.render(options): pages=\(pageCount) svgBytes=\(pageBytes) "
            + "includeLyrics=\(options.includeLyrics)"
        )
        return RenderedScore(midi: midi, svgPages: svgPages)
    }

    // MARK: - Public SMF Analysis

    /// Parse a Standard MIDI File byte stream and return a fully-populated
    /// `RenderedMIDI` summary without re-running Verovio.
    ///
    /// Use this when the caller already has SMF bytes in hand — for
    /// example a `Song.midiData` blob produced by an earlier MXL import.
    /// The summary mirrors what `render(musicXML:)` returns for the same
    /// MIDI bytes, so downstream consumers (PartSplitter,
    /// MultiTrackSamplerGraph) can run unchanged.
    ///
    /// - Parameter midi: Raw SMF bytes (Verovio output, .mid file, …).
    /// - Returns: `RenderedMIDI` carrying the original bytes plus
    ///   per-track metadata, the distinct channel set, and the
    ///   first-tempo-derived `originalBPM` (default 120).
    /// - Throws: `PipelineError.verovioRenderFailed` when the buffer is
    ///   shorter than the minimum SMF header.
    public nonisolated static func summarizeSMF(_ midi: Data) throws -> RenderedMIDI {
        let summary = try summarize(midi: midi)
        return RenderedMIDI(
            data: midi,
            trackCount: summary.trackCount,
            channels: summary.channels,
            trackInfo: summary.trackInfo,
            originalBPM: summary.originalBPM
        )
    }

    // MARK: - Private Methods

    /// Remove every `<lyric>...</lyric>` element from a MusicXML string.
    ///
    /// Uses `NSRegularExpression` with `.dotMatchesLineSeparators` so the
    /// regex spans newlines. This is intentionally a string-level pass —
    /// pulling in a full XML parser just to delete one element type
    /// would dwarf the cost of the regex (and Verovio re-parses the
    /// result anyway). MusicXML `<lyric>` cannot legally nest, so the
    /// non-greedy match is safe.
    nonisolated private static func stripLyrics(from musicXML: String) -> String {
        let pattern = "<lyric\\b[^>]*>.*?</lyric>"
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.dotMatchesLineSeparators]
        ) else {
            return musicXML
        }
        let ns = musicXML as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.stringByReplacingMatches(
            in: musicXML, options: [], range: range, withTemplate: ""
        )
    }



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
        /// BPM from the first SMF meta-0x51 (Set Tempo) event, or 120
        /// when no tempo event is present.
        var originalBPM: Double
    }

    nonisolated private static func summarize(midi: Data) throws -> MIDISummary {
        let bytes = [UInt8](midi)
        guard bytes.count >= 14 else {
            throw PipelineError.verovioRenderFailed(reason: "MIDI too short to parse header")
        }
        var trackCount = 0
        var channelSet = Set<UInt8>()
        var trackInfo: [TrackInfo] = []
        var firstTempoMicros: UInt32?
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
                        isPercussion: info.isPercussion,
                        trackName: info.trackName,
                        instrumentName: info.instrumentName
                    ))
                    info.channels.forEach { channelSet.insert($0) }
                }
                // Capture first tempo from any track (usually the conductor)
                if firstTempoMicros == nil, let micros = info.tempoMicros {
                    firstTempoMicros = micros
                }
                i = trackEnd
            } else {
                i += 1
            }
        }
        let bpm = 60_000_000.0 / Double(firstTempoMicros ?? 500_000)
        return MIDISummary(
            trackCount: trackCount,
            channels: channelSet.sorted(),
            trackInfo: trackInfo,
            originalBPM: bpm
        )
    }

    /// Result of parsing one MTrk chunk.
    nonisolated private struct ParsedTrack {
        var hasChannelVoiceEvents: Bool
        var firstChannel: UInt8?
        var firstProgram: UInt8?
        var isPercussion: Bool
        var channels: Set<UInt8>
        /// Sequence/Track Name from meta event 0x03.
        var trackName: String?
        /// Instrument Name from meta event 0x04.
        var instrumentName: String?
        /// Microseconds-per-quarter from meta event 0x51 (Set Tempo).
        var tempoMicros: UInt32?
    }

    private struct MetaResult {
        var trackName: String?
        var instrumentName: String?
        var tempoMicros: UInt32?
    }

    nonisolated private static func parseMeta(
        _ metaType: UInt8, bytes: [UInt8], dataStart: Int, len: Int, end: Int,
        existingName: String?, existingInstr: String?, existingTempo: UInt32?
    ) -> MetaResult {
        var result = MetaResult(
            trackName: existingName,
            instrumentName: existingInstr,
            tempoMicros: existingTempo
        )
        switch metaType {
        case 0x03 where result.trackName == nil:
            if len > 0, dataStart + len <= end {
                result.trackName = String(
                    bytes: bytes[dataStart..<dataStart + len],
                    encoding: .utf8
                )
            }
        case 0x04 where result.instrumentName == nil:
            if len > 0, dataStart + len <= end {
                result.instrumentName = String(
                    bytes: bytes[dataStart..<dataStart + len],
                    encoding: .utf8
                )
            }
        case 0x51 where result.tempoMicros == nil:
            if len == 3, dataStart + 3 <= end {
                result.tempoMicros = UInt32(bytes[dataStart]) << 16
                    | UInt32(bytes[dataStart + 1]) << 8
                    | UInt32(bytes[dataStart + 2])
            }
        default:
            break
        }
        return result
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
        var trackName: String?
        var instrumentName: String?
        var tempoMicros: UInt32?

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
                let metaType = bytes[j]
                j += 1  // type
                var len = 0
                while j < end {
                    let lb = bytes[j]
                    j += 1
                    len = (len << 7) | Int(lb & 0x7F)
                    if lb & 0x80 == 0 { break }
                }
                let parsed = parseMeta(
                    metaType, bytes: bytes, dataStart: j, len: len, end: end,
                    existingName: trackName, existingInstr: instrumentName,
                    existingTempo: tempoMicros
                )
                trackName = parsed.trackName
                instrumentName = parsed.instrumentName
                tempoMicros = parsed.tempoMicros
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
            channels: channels,
            trackName: trackName,
            instrumentName: instrumentName,
            tempoMicros: tempoMicros
        )
    }
}
