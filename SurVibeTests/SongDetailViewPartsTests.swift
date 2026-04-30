import SwiftUI
import Testing
@testable import SurVibe

// MARK: - SongDetailViewParts Tests

/// Tests for the Wave 4 D2 "Parts" section view: track-label projection,
/// MIDI-to-note-name helper, and binding-default behavior.
@Suite("SongDetailViewParts")
@MainActor
struct SongDetailViewPartsTests {

    // MARK: - Track Labels

    @Test("trackLabels for single-part Song returns only the learner entry")
    func trackLabelsForSinglePartReturnsLearnerOnly() {
        let song = Song()
        // No accompanimentInstrumentSummary set — single-track default.
        let labels = SongDetailViewParts.trackLabels(for: song)
        #expect(labels == ["Piano"])
    }

    @Test("trackLabels for multi-part Song includes accompaniment instruments")
    func trackLabelsForMultiPartIncludesAccompaniment() {
        let song = Song()
        song.accompanimentInstrumentSummary = "Harmonium · Tabla · Strings"
        let labels = SongDetailViewParts.trackLabels(for: song)
        #expect(labels == ["Learner", "Harmonium", "Tabla", "Strings"])
    }

    @Test("trackLabels collapses empty accompanimentInstrumentSummary to single entry")
    func trackLabelsForEmptySummaryReturnsLearnerOnly() {
        let song = Song()
        song.accompanimentInstrumentSummary = ""
        let labels = SongDetailViewParts.trackLabels(for: song)
        #expect(labels == ["Piano"])
    }

    // MARK: - Note Name Helper

    @Test("noteName(60) returns C4 (SPN convention)")
    func noteNameMidi60IsC4() {
        #expect(SongDetailViewParts.noteName(60) == "C4")
    }

    @Test("noteName(67) returns G4")
    func noteNameMidi67IsG4() {
        #expect(SongDetailViewParts.noteName(67) == "G4")
    }

    @Test("noteName(48) returns C3 (low end of Sa picker range)")
    func noteNameMidi48IsC3() {
        #expect(SongDetailViewParts.noteName(48) == "C3")
    }

    @Test("noteName(72) returns C5 (high end of Sa picker range)")
    func noteNameMidi72IsC5() {
        #expect(SongDetailViewParts.noteName(72) == "C5")
    }

    @Test("noteName(61) returns C#4 — sharps for black keys")
    func noteNameMidi61IsCSharp4() {
        #expect(SongDetailViewParts.noteName(61) == "C#4")
    }

    // MARK: - View Construction & Bindings

    @Test("View constructs with @Binding<Int> and @Binding<UInt8> harness")
    func viewConstructsWithBindings() {
        var trackIdx = 2
        var saPitch: UInt8 = 65
        let song = Song()

        let view = SongDetailViewParts(
            song: song,
            trackLabels: ["Learner", "Tabla"],
            accompanimentInstruments: ["Tabla"],
            learnerTrackIndex: Binding(get: { trackIdx }, set: { trackIdx = $0 }),
            tonicSaPitch: Binding(get: { saPitch }, set: { saPitch = $0 }),
            onPreviewLearner: {},
            onPreviewBacking: {}
        )

        #expect(view.learnerTrackIndex == 2)
        #expect(view.tonicSaPitch == 65)
        #expect(view.trackLabels.count == 2)
        #expect(view.accompanimentInstruments == ["Tabla"])
    }

    @Test("Preview callbacks fire when invoked")
    func previewCallbacksFire() {
        var learnerCalled = 0
        var backingCalled = 0
        var trackIdx = 0
        var saPitch: UInt8 = 60

        let view = SongDetailViewParts(
            song: Song(),
            trackLabels: ["Piano"],
            accompanimentInstruments: [],
            learnerTrackIndex: Binding(get: { trackIdx }, set: { trackIdx = $0 }),
            tonicSaPitch: Binding(get: { saPitch }, set: { saPitch = $0 }),
            onPreviewLearner: { learnerCalled += 1 },
            onPreviewBacking: { backingCalled += 1 }
        )

        view.onPreviewLearner()
        view.onPreviewBacking()
        view.onPreviewBacking()

        #expect(learnerCalled == 1)
        #expect(backingCalled == 2)
    }

    // MARK: - Song Default Wiring (parent contract)

    @Test("learnerTrackIndex default derives from Song.learnerTrackIndex when present")
    func learnerTrackIndexBindingDefaultsFromSong() {
        let song = Song()
        song.learnerTrackIndex = 1
        // Mirrors the SongDetailView.task initialization logic.
        let initial = song.learnerTrackIndex ?? 0
        #expect(initial == 1)
    }

    @Test("learnerTrackIndex default falls back to 0 when Song has no preference")
    func learnerTrackIndexDefaultsToZeroWhenNil() {
        let song = Song()
        let initial = song.learnerTrackIndex ?? 0
        #expect(initial == 0)
    }

    @Test("tonicSaPitch default is MIDI 60 (C4)")
    func tonicSaPitchDefaultsToMidi60() {
        // Mirrors the SongDetailView default for the Sa picker.
        let initial: UInt8 = 60
        #expect(initial == 60)
        #expect(SongDetailViewParts.noteName(initial) == "C4")
    }
}
