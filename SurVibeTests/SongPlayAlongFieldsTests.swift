import Testing
import SwiftData
@testable import SurVibe

// MARK: - Song Play-Along Fields Tests

/// Tests for the four play-along optional fields added to Song (A6 gap).
///
/// Verifies default nil values and round-trip read-back for
/// `learnerTrackIndex`, `accompanimentInstrumentSummary`,
/// `defaultPracticeMode`, and `lastUsedTempoScale`.
@Suite("Song Play-Along Fields")
@MainActor
struct SongPlayAlongFieldsTests {

    // MARK: - Default nil values

    @Test("learnerTrackIndex defaults to nil on fresh Song")
    func learnerTrackIndexDefaultsToNil() {
        let song = Song()
        #expect(song.learnerTrackIndex == nil)
    }

    @Test("accompanimentInstrumentSummary defaults to nil on fresh Song")
    func accompanimentInstrumentSummaryDefaultsToNil() {
        let song = Song()
        #expect(song.accompanimentInstrumentSummary == nil)
    }

    @Test("defaultPracticeMode defaults to nil on fresh Song")
    func defaultPracticeModeDefaultsToNil() {
        let song = Song()
        #expect(song.defaultPracticeMode == nil)
    }

    @Test("lastUsedTempoScale defaults to nil on fresh Song")
    func lastUsedTempoScaleDefaultsToNil() {
        let song = Song()
        #expect(song.lastUsedTempoScale == nil)
    }

    // MARK: - Set and read back

    @Test("learnerTrackIndex can be set and read back")
    func learnerTrackIndexRoundTrip() {
        let song = Song()
        song.learnerTrackIndex = 2
        #expect(song.learnerTrackIndex == 2)
    }

    @Test("accompanimentInstrumentSummary can be set and read back")
    func accompanimentInstrumentSummaryRoundTrip() {
        let song = Song()
        song.accompanimentInstrumentSummary = "Harmonium · Tabla · Strings"
        #expect(song.accompanimentInstrumentSummary == "Harmonium · Tabla · Strings")
    }

    @Test("defaultPracticeMode can be set and read back")
    func defaultPracticeModeRoundTrip() {
        let song = Song()
        song.defaultPracticeMode = "rightHand"
        #expect(song.defaultPracticeMode == "rightHand")
    }

    @Test("lastUsedTempoScale can be set and read back")
    func lastUsedTempoScaleRoundTrip() {
        let song = Song()
        song.lastUsedTempoScale = 0.75
        #expect(song.lastUsedTempoScale == 0.75)
    }

    @Test("all four play-along fields nil simultaneously on fresh Song")
    func allPlayAlongFieldsNilOnFreshSong() {
        let song = Song(slugId: "test-song", title: "Test", artist: "Tester")
        #expect(song.learnerTrackIndex == nil)
        #expect(song.accompanimentInstrumentSummary == nil)
        #expect(song.defaultPracticeMode == nil)
        #expect(song.lastUsedTempoScale == nil)
    }

    @Test("play-along fields can be cleared back to nil after being set")
    func playAlongFieldsClearedToNil() {
        let song = Song()
        song.learnerTrackIndex = 1
        song.accompanimentInstrumentSummary = "Tabla"
        song.defaultPracticeMode = "leftHand"
        song.lastUsedTempoScale = 0.5

        song.learnerTrackIndex = nil
        song.accompanimentInstrumentSummary = nil
        song.defaultPracticeMode = nil
        song.lastUsedTempoScale = nil

        #expect(song.learnerTrackIndex == nil)
        #expect(song.accompanimentInstrumentSummary == nil)
        #expect(song.defaultPracticeMode == nil)
        #expect(song.lastUsedTempoScale == nil)
    }
}
