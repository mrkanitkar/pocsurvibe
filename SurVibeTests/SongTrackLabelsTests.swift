import Testing

@testable import SurVibe

struct SongTrackLabelsTests {
    @Test
    func noSummaryReturnsPiano() {
        let song = Song(
            slugId: "test",
            title: "Test",
            artist: "",
            language: "en",
            difficulty: 1,
            category: "",
            ragaName: "",
            tempo: 80,
            durationSeconds: 60
        )
        let labels = Song.trackLabels(for: song)
        #expect(labels == ["Piano"])
    }

    @Test
    func emptySummaryReturnsPiano() {
        let song = Song(
            slugId: "test",
            title: "Test",
            artist: "",
            language: "en",
            difficulty: 1,
            category: "",
            ragaName: "",
            tempo: 80,
            durationSeconds: 60
        )
        song.accompanimentInstrumentSummary = ""
        let labels = Song.trackLabels(for: song)
        #expect(labels == ["Piano"])
    }

    @Test
    func multiTrackParsesCorrectly() {
        let song = Song(
            slugId: "test",
            title: "Test",
            artist: "",
            language: "en",
            difficulty: 1,
            category: "",
            ragaName: "",
            tempo: 80,
            durationSeconds: 60
        )
        song.accompanimentInstrumentSummary = "Harmonium · Tabla · Strings"
        let labels = Song.trackLabels(for: song)
        #expect(labels == ["Learner", "Harmonium", "Tabla", "Strings"])
    }

    @Test
    func singleTrackSummary() {
        let song = Song(
            slugId: "test",
            title: "Test",
            artist: "",
            language: "en",
            difficulty: 1,
            category: "",
            ragaName: "",
            tempo: 80,
            durationSeconds: 60
        )
        song.accompanimentInstrumentSummary = "Piano"
        let labels = Song.trackLabels(for: song)
        #expect(labels == ["Learner", "Piano"])
    }
}
