// SurVibeTests/PlayAlong/Mocks/MockGraph.swift
import Foundation
import SVAudio

@testable import SurVibe

/// Test double for `MultiTrackSamplerGraphProtocol`. Records all call
/// invocations so tests can assert forwarding without spinning up
/// `AVAudioEngine`.
///
/// Extracted from `ArrangementPlayerTests.swift` (Wave 5 E1) so multiple
/// test files can share one mock.
@MainActor
final class SharedMockGraph: MultiTrackSamplerGraphProtocol {

    // Recorded state
    var loadMIDICalled = false
    var lastLoadedMIDI: RenderedMIDI?
    var lastSetTempoScale: Float?
    var scheduledMetronomeClicks: [(Double, UInt8)] = []
    var lastSeekBeat: Double?
    var mutedTrackIndices: Set<Int> = []
    var playCalled = false
    var pauseCalled = false
    var resumeCalled = false
    var stopCalled = false

    // Stubbed properties
    var currentPositionInBeats: Double = 0
    private var internalIsPlaying = false
    var isPlaying: Bool { internalIsPlaying }

    func loadMIDI(_ rendered: RenderedMIDI) throws {
        loadMIDICalled = true
        lastLoadedMIDI = rendered
    }

    func setTempoScale(_ rate: Float) {
        lastSetTempoScale = rate
    }

    func play() throws {
        playCalled = true
        internalIsPlaying = true
    }

    func pause() {
        pauseCalled = true
        internalIsPlaying = false
    }

    func stop() {
        stopCalled = true
        internalIsPlaying = false
    }

    func resume() throws {
        resumeCalled = true
        internalIsPlaying = true
    }

    func seek(toBeat beat: Double) {
        lastSeekBeat = beat
    }

    func setMutedTracks(_ indices: Set<Int>) {
        mutedTrackIndices = indices
    }

    func scheduleMetronomeClick(at beat: Double, channel: UInt8) {
        scheduledMetronomeClicks.append((beat, channel))
    }
}

/// Build a minimal `PartSplit` with `measureCount` measures (4/4) for
/// E1 wiring tests. The accompaniment is the canonical 14-byte SMF
/// header, matching `ArrangementPlayerTests.makeSplit()`.
@MainActor
func makeE1Split(measureCount: Int = 4, multiStaff: Bool = false) -> PartSplit {
    // Minimal SMF header: "MThd" + length(6) + format(0) + tracks(0) + division(480)
    let bytes: [UInt8] = [
        0x4D, 0x54, 0x68, 0x64,
        0x00, 0x00, 0x00, 0x06,
        0x00, 0x00,
        0x00, 0x00,
        0x01, 0xE0,
    ]
    var notes: [ExpectedNote] = []
    for i in 0..<measureCount {
        notes.append(
            ExpectedNote(
                beat: Double(i * 4),
                durationBeats: 1.0,
                midiNote: 60,
                measureNumber: i + 1
            )
        )
    }
    let learner = LearnerScore(
        notes: notes,
        originalBPM: 120,
        beatsPerMeasure: 4
    )
    let staves: [StaffSpec]
    let trackIndices: [Int]
    if multiStaff {
        staves = [
            StaffSpec(staffNumber: 1, role: .rightHand, noteIDs: notes.map(\.id)),
            StaffSpec(staffNumber: 2, role: .leftHand, noteIDs: []),
        ]
        trackIndices = [0, 1]
    } else {
        staves =
            notes.isEmpty
            ? []
            : [StaffSpec(staffNumber: 1, role: .singleStaff, noteIDs: notes.map(\.id))]
        trackIndices = [0]
    }
    return PartSplit(
        learner: learner,
        accompaniment: Data(bytes),
        learnerInstrumentLabel: "Piano",
        accompanimentInstruments: [],
        learnerTrackIndices: trackIndices,
        learnerStaves: staves,
        lyricsStaffTrackIndex: nil
    )
}
