// swiftlint:disable function_body_length line_length
import Foundation
import Testing

@testable import SVAudio

/// Tests for `PartSplitter` (Wave 2 / Task B1).
///
/// Synthesises Format-1 SMF byte streams in-memory so we can exercise the
/// rule cascade, percussion guard, override path, lyrics detection, and
/// staff identification without depending on Verovio.
struct PartSplitterTests {

    // MARK: - Rule 1: name match

    @Test
    func rule1MatchesPianoTrackName() throws {
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 40, trackName: "Violin"),
            TrackSpec(channel: 1, program: 0, trackName: "Piano"),
        ])
        let split = try PartSplitter().split(rendered)
        #expect(split.learnerTrackIndices == [1])
        #expect(split.learnerInstrumentLabel == "Piano")
        #expect(split.accompanimentInstruments.count == 1)
    }

    @Test
    func rule1MatchesInstrumentName() throws {
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 40, instrumentName: "Violin"),
            TrackSpec(channel: 1, program: 19, instrumentName: "Pianoforte"),
        ])
        let split = try PartSplitter().split(rendered)
        #expect(split.learnerTrackIndices == [1])
        #expect(split.learnerInstrumentLabel == "Piano")
    }

    // MARK: - Rule 2: GM Piano program

    @Test
    func rule2FallsBackToGMPianoProgram() throws {
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 40),  // Violin
            TrackSpec(channel: 1, program: 0),  // Acoustic Grand Piano
        ])
        let split = try PartSplitter().split(rendered)
        #expect(split.learnerTrackIndices == [1])
        #expect(split.learnerInstrumentLabel == "Acoustic Grand Piano")
    }

    // MARK: - Rule 3: voice/vocal/melody/lead by name

    @Test
    func rule3PicksVoiceWithLabel() throws {
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 40),
            TrackSpec(channel: 1, program: 52, trackName: "Voice"),
        ])
        let split = try PartSplitter().split(rendered)
        #expect(split.learnerTrackIndices == [1])
        #expect(split.learnerInstrumentLabel.contains("Voice"))
    }

    @Test
    func rule3PicksMelodyByName() throws {
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 40, trackName: "Strings"),
            TrackSpec(channel: 1, program: 73, trackName: "Lead Melody"),
        ])
        let split = try PartSplitter().split(rendered)
        #expect(split.learnerTrackIndices == [1])
    }

    // MARK: - Rule 4: most-notes fallback

    @Test
    func rule4FallbackPicksMostNotes() throws {
        // Two melodic tracks (no piano name, no GM-piano program, no voice).
        // Track 0 has 1 note; track 1 has 4 notes — track 1 wins.
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 40, noteCount: 1),
            TrackSpec(channel: 1, program: 41, noteCount: 4),
        ])
        let split = try PartSplitter().split(rendered)
        #expect(split.learnerTrackIndices == [1])
    }

    // MARK: - Percussion guard

    @Test
    func percussionNeverLearner() throws {
        // Track 0 is percussion (channel 9) with most notes; track 1 is
        // melodic with fewer. Even fallback rule 4 must not pick track 0.
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 9, program: 0, isPercussion: true, noteCount: 10),
            TrackSpec(channel: 0, program: 40, noteCount: 2),
        ])
        let split = try PartSplitter().split(rendered)
        #expect(!split.learnerTrackIndices.contains(0))
        #expect(split.learnerTrackIndices == [1])
    }

    @Test
    func userOverrideToPercussionThrows() throws {
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 0, trackName: "Piano"),
            TrackSpec(channel: 9, program: 0, isPercussion: true),
        ])
        #expect(throws: PipelineError.self) {
            try PartSplitter().split(rendered, selection: .trackIndex(1))
        }
    }

    // MARK: - User override

    @Test
    func userOverridePicksTrackIndex() throws {
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 0, trackName: "Piano"),
            TrackSpec(
                channel: 1,
                program: 19,
                trackName: "Harmonium",
                instrumentName: "Reed Organ"
            ),
        ])
        let split = try PartSplitter().split(rendered, selection: .trackIndex(1))
        #expect(split.learnerTrackIndices == [1])
        // Override label uses instrumentName when available.
        #expect(split.learnerInstrumentLabel == "Reed Organ")
    }

    @Test
    func userOverrideOutOfRangeThrows() throws {
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 0, trackName: "Piano")
        ])
        #expect(throws: PipelineError.self) {
            try PartSplitter().split(rendered, selection: .trackIndex(5))
        }
    }

    // MARK: - Staff identification

    @Test
    func staffIdentificationFromSingleTrack() throws {
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 0, trackName: "Piano", noteCount: 3)
        ])
        let split = try PartSplitter().split(rendered)
        // SMF input lacks MusicXML <staff> — splitter returns one staff.
        #expect(split.learnerStaves.count == 1)
        #expect(split.learnerStaves[0].role == .singleStaff)
        #expect(split.learnerStaves[0].noteIDs.count == split.learner.notes.count)
    }

    @Test
    func emptyTracksProduceNoStaff() throws {
        // Force fallback by giving a single non-piano track with no notes;
        // the splitter should still pick it (rule 4 most-notes among the
        // non-percussion set returns 0) and produce zero staves.
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 40, noteCount: 0)
        ])
        let split = try PartSplitter().split(rendered)
        #expect(split.learner.notes.isEmpty)
        #expect(split.learnerStaves.isEmpty)
    }

    // MARK: - Expected-note construction

    @Test
    func expectedNotesAreOrderedByBeat() throws {
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 0, trackName: "Piano", noteCount: 4)
        ])
        let split = try PartSplitter().split(rendered)
        let notes = split.learner.notes
        #expect(notes.count == 4)
        for i in 1..<notes.count {
            #expect(notes[i - 1].beat <= notes[i].beat)
        }
        // Default time signature → 4 beats per measure.
        #expect(split.learner.beatsPerMeasure == 4)
    }

    // MARK: - Accompaniment SMF

    @Test
    func accompanimentDropsLearnerTrack() throws {
        let rendered = makeRenderedMIDI(tracks: [
            TrackSpec(channel: 0, program: 40, trackName: "Violin"),
            TrackSpec(channel: 1, program: 0, trackName: "Piano"),
        ])
        let split = try PartSplitter().split(rendered)
        // Accompaniment should still parse as a valid SMF and contain
        // the conductor + remaining music track (i.e. one fewer MTrk).
        #expect(split.accompaniment.count > 14)
        let originalMTrk = countMTrkChunks(rendered.data)
        let accompMTrk = countMTrkChunks(split.accompaniment)
        #expect(accompMTrk == originalMTrk - 1)
    }

    // MARK: - Bundled MXL E2E (skipped if asset not in test bundle)

    @Test(
        .disabled(
            "Bundled MXLs ship with the app target, not the SVAudio test bundle. Re-enable once a fixture loader is added."
        )
    )
    @MainActor
    func sukhkartaDukhhartaPicksMelodyAsLearner() async throws {
        let bridge = VerovioBridge()
        guard
            let url = Bundle.main.url(
                forResource: "Sukhkarta_Dukhharta",
                withExtension: "mxl"
            )
        else { return }
        let mxl = try Data(contentsOf: url)
        let xml = try MXLLoader.loadMusicXML(from: mxl)
        let rendered = try bridge.render(musicXML: xml)
        let split = try PartSplitter().split(rendered)
        #expect(!split.learnerTrackIndices.isEmpty)
        #expect(split.accompanimentInstruments.count >= 1)
    }
}

// MARK: - Test fixtures

/// Description of one track for the in-memory SMF fixture.
private struct TrackSpec {
    var channel: UInt8
    var program: UInt8?
    var isPercussion: Bool = false
    var trackName: String?
    var instrumentName: String?
    var noteCount: Int = 1
}

/// Build a synthetic `RenderedMIDI` from `TrackSpec`s. Each music track gets
/// a Program Change followed by `noteCount` quarter-note pairs (480 ticks
/// each at division 480) starting at tick 0 and an end-of-track meta.
private func makeRenderedMIDI(tracks: [TrackSpec]) -> RenderedMIDI {
    var data = Data()

    // Header — Format 1, ntrks = tracks.count + 1 (conductor), division 480.
    data.append(contentsOf: "MThd".utf8)
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x06])
    data.append(contentsOf: [0x00, 0x01])
    let ntrks = UInt16(tracks.count + 1)
    data.append(contentsOf: [UInt8((ntrks >> 8) & 0xFF), UInt8(ntrks & 0xFF)])
    data.append(contentsOf: [0x01, 0xE0])  // 480 PPQ

    // Conductor track: tempo + time signature + EOT.
    var conductor = Data()
    // Set Tempo 500_000 µs/qn (120 BPM).
    conductor.append(contentsOf: [0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20])
    // Time Signature 4/4 (numerator=4, denom=2 (=>4), 24 ticks/click, 8 32nds/qn).
    conductor.append(contentsOf: [0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08])
    conductor.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])  // EOT
    appendMTrk(into: &data, payload: conductor)

    // Music tracks.
    for spec in tracks {
        var trk = Data()
        // Track Name (meta-0x03)
        if let name = spec.trackName {
            let bytes = Array(name.utf8)
            trk.append(contentsOf: [0x00, 0xFF, 0x03])
            trk.append(UInt8(bytes.count))
            trk.append(contentsOf: bytes)
        }
        // Instrument Name (meta-0x04)
        if let instr = spec.instrumentName {
            let bytes = Array(instr.utf8)
            trk.append(contentsOf: [0x00, 0xFF, 0x04])
            trk.append(UInt8(bytes.count))
            trk.append(contentsOf: bytes)
        }
        // Program Change (skip for percussion to keep channel 9).
        if let prog = spec.program {
            trk.append(contentsOf: [0x00, 0xC0 | (spec.channel & 0x0F), prog])
        }
        // Note pairs.
        for i in 0..<spec.noteCount {
            let pitch = UInt8(60 + (i % 8))
            if i == 0 {
                trk.append(0x00)
            } else {
                // Variable-length 480 = 0x83, 0x60.
                trk.append(0x83)
                trk.append(0x60)
            }
            trk.append(0x90 | (spec.channel & 0x0F))
            trk.append(pitch)
            trk.append(0x40)  // velocity
            // Note Off after 240 ticks (half a quarter).
            trk.append(0x81)
            trk.append(0x70)  // 240 = 0x81 0x70
            trk.append(0x80 | (spec.channel & 0x0F))
            trk.append(pitch)
            trk.append(0x40)
        }
        // EOT.
        trk.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])
        appendMTrk(into: &data, payload: trk)
    }

    // Build TrackInfo array — order matches music tracks.
    let trackInfo: [TrackInfo] = tracks.map { spec in
        TrackInfo(
            channel: spec.channel,
            program: spec.program,
            isPercussion: spec.isPercussion,
            trackName: spec.trackName,
            instrumentName: spec.instrumentName
        )
    }
    return RenderedMIDI(
        data: data,
        trackCount: tracks.count + 1,
        channels: Array(Set(tracks.map { $0.channel })).sorted(),
        trackInfo: trackInfo,
        originalBPM: 120.0
    )
}

private func appendMTrk(into data: inout Data, payload: Data) {
    data.append(contentsOf: "MTrk".utf8)
    let len = UInt32(payload.count)
    data.append(contentsOf: [
        UInt8((len >> 24) & 0xFF),
        UInt8((len >> 16) & 0xFF),
        UInt8((len >> 8) & 0xFF),
        UInt8(len & 0xFF),
    ])
    data.append(payload)
}

private func countMTrkChunks(_ data: Data) -> Int {
    let bytes = [UInt8](data)
    var i = 0
    var count = 0
    while i + 4 <= bytes.count {
        if bytes[i] == 0x4D, bytes[i + 1] == 0x54,
            bytes[i + 2] == 0x72, bytes[i + 3] == 0x6B
        {
            count += 1
            guard i + 8 <= bytes.count else { break }
            let length = Int(
                UInt32(bytes[i + 4]) << 24
                    | UInt32(bytes[i + 5]) << 16
                    | UInt32(bytes[i + 6]) << 8
                    | UInt32(bytes[i + 7])
            )
            i += 8 + length
        } else {
            i += 1
        }
    }
    return count
}
