// swiftlint:disable file_length type_body_length function_body_length
import Foundation

// MARK: - Public Types (spec §5.1)

/// A learner / accompaniment split of a `RenderedMIDI`.
///
/// `learner` carries the expected-note score used by the scoring layer.
/// `accompaniment` is a fresh SMF byte stream identical in tempo/division
/// to the source but with the learner MTrk chunk(s) removed, suitable for
/// loading into an `AVAudioSequencer` for backing playback.
public struct PartSplit: Sendable {
    /// Expected notes for scoring (the part the user plays).
    public let learner: LearnerScore
    /// SMF bytes for the sequencer (everything except the learner part).
    public let accompaniment: Data
    /// Display label for the learner part — e.g. `"Piano"`, `"Voice (transposed)"`.
    public let learnerInstrumentLabel: String
    /// Display labels for accompaniment parts in source order.
    public let accompanimentInstruments: [String]
    /// Track indices (into `RenderedMIDI.trackInfo`) chosen as the learner.
    /// Stored as a list to support per-staff sub-tracks (RH/LH).
    public let learnerTrackIndices: [Int]
    /// Per-staff structure for hand isolation. Zero entries when no notes
    /// are assigned, otherwise one (single staff) or two (RH + LH).
    public let learnerStaves: [StaffSpec]
    /// Track index containing `<lyric>` events (SMF meta-0x05); `nil` when
    /// no lyrics are present.
    ///
    /// TODO(Wave 5+): consume this in the score renderer to keep the voice
    /// staff visible when the learner is on a non-vocal part.
    public let lyricsStaffTrackIndex: Int?

    public init(
        learner: LearnerScore,
        accompaniment: Data,
        learnerInstrumentLabel: String,
        accompanimentInstruments: [String],
        learnerTrackIndices: [Int],
        learnerStaves: [StaffSpec],
        lyricsStaffTrackIndex: Int?
    ) {
        self.learner = learner
        self.accompaniment = accompaniment
        self.learnerInstrumentLabel = learnerInstrumentLabel
        self.accompanimentInstruments = accompanimentInstruments
        self.learnerTrackIndices = learnerTrackIndices
        self.learnerStaves = learnerStaves
        self.lyricsStaffTrackIndex = lyricsStaffTrackIndex
    }
}

/// One staff in the learner score — RH, LH, or a single combined staff.
public struct StaffSpec: Sendable {
    /// MusicXML `<staff>` value: 1 = RH (treble), 2 = LH (bass).
    /// For SMF-only input where staff data is unavailable, `1`.
    public let staffNumber: Int
    /// Hand role used for isolation UI.
    public let role: HandRole
    /// Expected-note IDs assigned to this staff.
    public let noteIDs: [UUID]

    public init(staffNumber: Int, role: HandRole, noteIDs: [UUID]) {
        self.staffNumber = staffNumber
        self.role = role
        self.noteIDs = noteIDs
    }
}

/// Hand role for staff isolation.
public enum HandRole: Sendable { case rightHand, leftHand, singleStaff }

/// User-provided learner-track selection for `PartSplitter.split(_:selection:)`.
public enum LearnerSelection: Sendable {
    /// Splitter picks the learner using the auto-rule cascade.
    case auto
    /// User override — index into `RenderedMIDI.trackInfo`.
    case trackIndex(Int)
}

/// The expected-note timeline the scoring layer matches against.
public struct LearnerScore: Sendable {
    /// Notes in beat order (ascending `beat`).
    public let notes: [ExpectedNote]
    /// Original tempo in BPM (taken from `RenderedMIDI.originalBPM`).
    public let originalBPM: Double
    /// Beats per measure. Defaults to 4 when no time-signature meta event
    /// is present in the source SMF.
    public let beatsPerMeasure: Int

    public init(notes: [ExpectedNote], originalBPM: Double, beatsPerMeasure: Int) {
        self.notes = notes
        self.originalBPM = originalBPM
        self.beatsPerMeasure = beatsPerMeasure
    }
}

/// One expected note in the learner part.
public struct ExpectedNote: Sendable, Identifiable {
    public let id: UUID
    /// Beats from the start of the song at the original tempo.
    public let beat: Double
    /// Note duration in beats.
    public let durationBeats: Double
    /// MIDI pitch (0–127).
    public let midiNote: UInt8
    /// 1-indexed measure number (uses `beatsPerMeasure`).
    public let measureNumber: Int

    public init(
        id: UUID = UUID(),
        beat: Double,
        durationBeats: Double,
        midiNote: UInt8,
        measureNumber: Int
    ) {
        self.id = id
        self.beat = beat
        self.durationBeats = durationBeats
        self.midiNote = midiNote
        self.measureNumber = measureNumber
    }
}

// MARK: - PartSplitter

/// Splits a `RenderedMIDI` into a learner part (expected notes for scoring)
/// and an accompaniment SMF (everything else, for sequencer playback).
///
/// Selection algorithm (spec §5.1):
/// 1. Track/instrument name matches `/piano|pianoforte/i`.
/// 2. Else GM Piano program (0–7) on a non-percussion track.
/// 3. Else track name matches `/voice|vocal|melody|lead/i`.
/// 4. Else fallback: most-notes non-percussion track.
///
/// A percussion track is **never** auto-selected as learner. A user
/// override pointing at a percussion track throws
/// `PipelineError.noPlayableLearnerPart`.
public struct PartSplitter: Sendable {
    public init() {}

    /// Split `rendered` into learner + accompaniment.
    ///
    /// - Parameters:
    ///   - rendered: The Verovio render output.
    ///   - selection: `.auto` (default) or `.trackIndex(N)` user override.
    /// - Returns: A `PartSplit` carrying the learner score, accompaniment SMF,
    ///            and display labels for the Parts picker.
    /// - Throws: `PipelineError.noPlayableLearnerPart` if no melodic track
    ///           exists or the override picks a percussion track.
    public func split(
        _ rendered: RenderedMIDI,
        selection: LearnerSelection = .auto
    ) throws -> PartSplit {
        guard !rendered.trackInfo.isEmpty else {
            throw PipelineError.noPlayableLearnerPart
        }

        let parsed = Self.parseSMF(rendered.data)
        let candidates = rendered.trackInfo.enumerated().map { idx, info -> Candidate in
            let noteCount =
                idx < parsed.musicTrackNoteCounts.count
                ? parsed.musicTrackNoteCounts[idx] : 0
            return Candidate(idx: idx, info: info, noteCount: noteCount)
        }

        let learnerIdx: Int
        let learnerLabel: String
        switch selection {
        case .trackIndex(let i):
            guard i >= 0, i < rendered.trackInfo.count else {
                throw PipelineError.noPlayableLearnerPart
            }
            learnerIdx = i
            learnerLabel = Self.labelFor(rendered.trackInfo[i])
        case .auto:
            guard let pick = Self.autoSelect(candidates) else {
                throw PipelineError.noPlayableLearnerPart
            }
            learnerIdx = pick.idx
            learnerLabel = pick.label
        }

        guard !rendered.trackInfo[learnerIdx].isPercussion else {
            throw PipelineError.noPlayableLearnerPart
        }

        let accompIndices = (0..<rendered.trackInfo.count).filter { $0 != learnerIdx }
        let accompMIDI = Self.stripTracks(rendered.data, droppingMusicTrack: learnerIdx, parsed: parsed)

        let bpm = rendered.originalBPM
        let beatsPerMeasure = parsed.beatsPerMeasure
        let learnerNotes = Self.buildExpectedNotes(
            for: learnerIdx,
            parsed: parsed,
            beatsPerMeasure: beatsPerMeasure
        )
        let learnerScore = LearnerScore(
            notes: learnerNotes,
            originalBPM: bpm,
            beatsPerMeasure: beatsPerMeasure
        )
        let staves: [StaffSpec]
        if learnerNotes.isEmpty {
            staves = []
        } else {
            // SMF input doesn't carry MusicXML <staff> assignments. Until
            // the loader propagates that data we expose a single staff
            // covering all notes.
            staves = [
                StaffSpec(
                    staffNumber: 1,
                    role: .singleStaff,
                    noteIDs: learnerNotes.map { $0.id }
                )
            ]
        }

        let lyricsTrackIdx = parsed.lyricsTrackIndex
        let accompLabels = accompIndices.map { Self.labelFor(rendered.trackInfo[$0]) }

        return PartSplit(
            learner: learnerScore,
            accompaniment: accompMIDI,
            learnerInstrumentLabel: learnerLabel,
            accompanimentInstruments: accompLabels,
            learnerTrackIndices: [learnerIdx],
            learnerStaves: staves,
            lyricsStaffTrackIndex: lyricsTrackIdx
        )
    }

    // MARK: - Auto-selection

    private struct Candidate {
        let idx: Int
        let info: TrackInfo
        let noteCount: Int
    }

    private static func autoSelect(_ cands: [Candidate]) -> (idx: Int, label: String)? {
        // Rule 1: track or instrument name matches /piano|pianoforte/i.
        if let m = cands.first(where: {
            !$0.info.isPercussion && (matchesPiano($0.info.trackName) || matchesPiano($0.info.instrumentName))
        }) {
            return (m.idx, "Piano")
        }
        // Rule 2: GM Piano program (0–7), non-percussion.
        if let m = cands.first(where: {
            !$0.info.isPercussion && (($0.info.program ?? 255) <= 7)
        }) {
            let prog = m.info.program ?? 0
            return (m.idx, GMProgramName.label(for: prog))
        }
        // Rule 3: voice / vocal / melody / lead by name.
        if let m = cands.first(where: {
            !$0.info.isPercussion && (matchesVoice($0.info.trackName) || matchesVoice($0.info.instrumentName))
        }) {
            return (m.idx, "Voice (transposed)")
        }
        // Rule 4: most-notes non-percussion fallback.
        let melodic = cands.filter { !$0.info.isPercussion }
        guard let m = melodic.max(by: { $0.noteCount < $1.noteCount }) else {
            return nil
        }
        return (m.idx, labelFor(m.info))
    }

    private static func matchesPiano(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return name.contains("piano") || name.contains("pianoforte")
    }

    private static func matchesVoice(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return name.contains("voice") || name.contains("vocal")
            || name.contains("melody") || name.contains("lead")
    }

    private static func labelFor(_ info: TrackInfo) -> String {
        if let instr = info.instrumentName, !instr.isEmpty { return instr }
        if let track = info.trackName, !track.isEmpty { return track }
        return GMProgramName.label(for: info.program ?? 0)
    }

    // MARK: - SMF Parsing (private)

    /// Per-music-track view of the SMF needed to count notes, build the
    /// learner score, identify lyrics tracks, and rewrite accompaniment.
    private struct ParsedSMF {
        /// Byte ranges of each MTrk chunk in source order (incl. conductor).
        let mtrkRanges: [Range<Int>]
        /// Indices into `mtrkRanges` of MTrk chunks that have channel-voice
        /// events. The N-th entry corresponds to `RenderedMIDI.trackInfo[N]`.
        let musicMTrkIndices: [Int]
        /// Header bytes (`MThd` chunk including length+payload).
        let headerBytes: Data
        /// SMF division word from MThd (PPQ value when bit 15 == 0).
        let division: UInt16
        /// Note-on counts indexed by music-track index (matches `trackInfo`).
        let musicTrackNoteCounts: [Int]
        /// Note events for each music track (matches `trackInfo`).
        let musicTrackNotes: [[NoteEvent]]
        /// Track index (in `trackInfo`) carrying lyric meta events, or nil.
        let lyricsTrackIndex: Int?
        /// Beats per measure from the first 0xFF 0x58 (Time Signature) meta;
        /// defaults to 4 when none is present.
        let beatsPerMeasure: Int
    }

    /// One note-on / note-off pair extracted from an MTrk.
    private struct NoteEvent {
        let pitch: UInt8
        let onTick: Int
        let offTick: Int
    }

    /// Walk the SMF once and capture ranges, division, notes, lyric flags.
    /// Mirrors the logic in `VerovioBridge.summarize` so the music-track
    /// indexing here matches the one used to build `trackInfo`.
    private static func parseSMF(_ data: Data) -> ParsedSMF {
        let bytes = [UInt8](data)
        guard bytes.count >= 14, bytes.starts(with: [0x4D, 0x54, 0x68, 0x64]) else {
            return ParsedSMF(
                mtrkRanges: [],
                musicMTrkIndices: [],
                headerBytes: Data(),
                division: 480,
                musicTrackNoteCounts: [],
                musicTrackNotes: [],
                lyricsTrackIndex: nil,
                beatsPerMeasure: 4
            )
        }
        let headerLen = Int(
            UInt32(bytes[4]) << 24
                | UInt32(bytes[5]) << 16
                | UInt32(bytes[6]) << 8
                | UInt32(bytes[7])
        )
        let headerEnd = 8 + headerLen
        let division: UInt16
        if headerLen >= 6, headerEnd <= bytes.count {
            division = UInt16(bytes[12]) << 8 | UInt16(bytes[13])
        } else {
            division = 480
        }
        let header = Data(bytes[0..<min(headerEnd, bytes.count)])

        var mtrkRanges: [Range<Int>] = []
        var musicIndices: [Int] = []
        var musicNoteCounts: [Int] = []
        var musicNotes: [[NoteEvent]] = []
        var lyricsTrackIdx: Int?
        var beatsPerMeasure = 4

        var i = headerEnd
        while i + 8 <= bytes.count {
            // Find next MTrk; bail if not found.
            guard bytes[i] == 0x4D, bytes[i + 1] == 0x54,
                bytes[i + 2] == 0x72, bytes[i + 3] == 0x6B
            else {
                i += 1
                continue
            }
            let length = Int(
                UInt32(bytes[i + 4]) << 24
                    | UInt32(bytes[i + 5]) << 16
                    | UInt32(bytes[i + 6]) << 8
                    | UInt32(bytes[i + 7])
            )
            let chunkStart = i
            let dataStart = i + 8
            let dataEnd = min(dataStart + length, bytes.count)
            mtrkRanges.append(chunkStart..<dataEnd)
            let parsed = parseTrackEvents(bytes: bytes, start: dataStart, end: dataEnd)
            if parsed.hasChannelVoice {
                let musicIdx = musicIndices.count
                musicIndices.append(mtrkRanges.count - 1)
                musicNoteCounts.append(parsed.notes.count)
                musicNotes.append(parsed.notes)
                if parsed.hasLyrics, lyricsTrackIdx == nil {
                    lyricsTrackIdx = musicIdx
                }
            }
            if let bpm = parsed.beatsPerMeasure, beatsPerMeasure == 4 {
                beatsPerMeasure = bpm
            }
            i = dataEnd
        }

        return ParsedSMF(
            mtrkRanges: mtrkRanges,
            musicMTrkIndices: musicIndices,
            headerBytes: header,
            division: division == 0 ? 480 : division,
            musicTrackNoteCounts: musicNoteCounts,
            musicTrackNotes: musicNotes,
            lyricsTrackIndex: lyricsTrackIdx,
            beatsPerMeasure: beatsPerMeasure
        )
    }

    private struct ParsedTrackEvents {
        var hasChannelVoice: Bool
        var notes: [NoteEvent]
        var hasLyrics: Bool
        var beatsPerMeasure: Int?
    }

    /// Read a variable-length quantity starting at `cursor`, advancing it
    /// past the consumed bytes. Returns the integer value.
    private static func readVarLen(
        _ bytes: [UInt8],
        _ cursor: inout Int,
        end: Int
    ) -> Int {
        var value = 0
        while cursor < end {
            let lb = bytes[cursor]
            cursor += 1
            value = (value << 7) | Int(lb & 0x7F)
            if lb & 0x80 == 0 { break }
        }
        return value
    }

    /// Walk one MTrk body, producing complete note-on/off pairs, plus
    /// flags for lyrics presence and the first time-signature numerator.
    private static func parseTrackEvents(
        bytes: [UInt8],
        start: Int,
        end: Int
    ) -> ParsedTrackEvents {
        var ctx = TrackParseCtx(j: start, absTick: 0, runningStatus: 0)
        var out = ParsedTrackEvents(
            hasChannelVoice: false,
            notes: [],
            hasLyrics: false,
            beatsPerMeasure: nil
        )
        var pending: [UInt8: Int] = [:]

        while ctx.j < end {
            ctx.absTick += readVarLen(bytes, &ctx.j, end: end)
            if ctx.j >= end { break }

            var status = bytes[ctx.j]
            if status & 0x80 != 0 {
                ctx.j += 1
                if status < 0xF0 { ctx.runningStatus = status }
            } else {
                status = ctx.runningStatus
            }

            if status == 0xFF {
                handleMeta(bytes: bytes, end: end, ctx: &ctx, out: &out)
            } else if status == 0xF0 || status == 0xF7 {
                let len = readVarLen(bytes, &ctx.j, end: end)
                ctx.j += len
            } else if status >= 0x80 && status < 0xF0 {
                out.hasChannelVoice = true
                if !handleChannelVoice(
                    status: status,
                    bytes: bytes,
                    end: end,
                    ctx: &ctx,
                    pending: &pending,
                    notes: &out.notes
                ) {
                    break
                }
            } else {
                break
            }
        }

        return out
    }

    /// Mutable cursor state shared by the MTrk-parsing helpers.
    private struct TrackParseCtx {
        var j: Int
        var absTick: Int
        var runningStatus: UInt8
    }

    /// Process a meta event (status 0xFF). Updates `out.hasLyrics` and
    /// `out.beatsPerMeasure` as a side effect.
    private static func handleMeta(
        bytes: [UInt8],
        end: Int,
        ctx: inout TrackParseCtx,
        out: inout ParsedTrackEvents
    ) {
        guard ctx.j < end else { return }
        let metaType = bytes[ctx.j]
        ctx.j += 1
        let len = readVarLen(bytes, &ctx.j, end: end)
        if metaType == 0x05, len > 0 {
            out.hasLyrics = true
        } else if metaType == 0x58, len >= 1, out.beatsPerMeasure == nil, ctx.j < end {
            out.beatsPerMeasure = Int(bytes[ctx.j])
        }
        ctx.j += len
    }

    /// Process one channel-voice event. Returns false if the buffer is
    /// truncated mid-event so the outer loop can bail.
    private static func handleChannelVoice(
        status: UInt8,
        bytes: [UInt8],
        end: Int,
        ctx: inout TrackParseCtx,
        pending: inout [UInt8: Int],
        notes: inout [NoteEvent]
    ) -> Bool {
        let high = status & 0xF0
        if high == 0xC0 || high == 0xD0 {
            if ctx.j < end { ctx.j += 1 }
            return true
        }
        guard ctx.j + 1 < end else { return false }
        let d1 = bytes[ctx.j]
        let d2 = bytes[ctx.j + 1]
        ctx.j += 2
        if high == 0x90 && d2 > 0 {
            pending[d1] = ctx.absTick
        } else if high == 0x80 || (high == 0x90 && d2 == 0) {
            if let onTick = pending.removeValue(forKey: d1) {
                notes.append(NoteEvent(pitch: d1, onTick: onTick, offTick: ctx.absTick))
            }
        }
        return true
    }

    // MARK: - SMF rewriting

    /// Rebuild a Format-1 SMF dropping the MTrk chunk corresponding to the
    /// learner music-track index. The conductor track and other music
    /// tracks are preserved bit-for-bit.
    private static func stripTracks(
        _ data: Data,
        droppingMusicTrack learnerMusicIdx: Int,
        parsed: ParsedSMF
    ) -> Data {
        guard learnerMusicIdx >= 0,
            learnerMusicIdx < parsed.musicMTrkIndices.count
        else {
            return data
        }
        let dropMTrkIdx = parsed.musicMTrkIndices[learnerMusicIdx]
        let bytes = [UInt8](data)

        // Build header with updated track count.
        guard parsed.headerBytes.count >= 14 else { return data }
        var header = [UInt8](parsed.headerBytes)
        let newTrackCount = UInt16(parsed.mtrkRanges.count - 1)
        header[10] = UInt8((newTrackCount >> 8) & 0xFF)
        header[11] = UInt8(newTrackCount & 0xFF)

        var out = Data()
        out.append(Data(header))
        for (idx, range) in parsed.mtrkRanges.enumerated() where idx != dropMTrkIdx {
            let lo = max(0, range.lowerBound)
            let hi = min(bytes.count, range.upperBound)
            if lo < hi {
                out.append(Data(bytes[lo..<hi]))
            }
        }
        return out
    }

    // MARK: - Expected-note construction

    /// Convert one music track's note events into `[ExpectedNote]` ordered
    /// by beat. Beats are computed from the SMF division (PPQ).
    private static func buildExpectedNotes(
        for musicTrackIdx: Int,
        parsed: ParsedSMF,
        beatsPerMeasure: Int
    ) -> [ExpectedNote] {
        guard musicTrackIdx >= 0, musicTrackIdx < parsed.musicTrackNotes.count else {
            return []
        }
        let division = Double(parsed.division == 0 ? 480 : parsed.division)
        let divisor = Double(max(beatsPerMeasure, 1))
        let raw = parsed.musicTrackNotes[musicTrackIdx]
        let sorted = raw.sorted { $0.onTick < $1.onTick }
        return sorted.map { note in
            let beat = Double(note.onTick) / division
            let dur = max(0.0, Double(note.offTick - note.onTick) / division)
            let measureNumber = Int(beat / divisor) + 1
            return ExpectedNote(
                beat: beat,
                durationBeats: dur,
                midiNote: note.pitch,
                measureNumber: measureNumber
            )
        }
    }
}
