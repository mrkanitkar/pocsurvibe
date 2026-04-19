import Testing
@testable import SVCore

@Suite("AnalyticsEvent Tests")
struct AnalyticsEventTests {
    @Test("Event raw values use snake_case format")
    func testRawValueFormat() {
        let events: [AnalyticsEvent] = [
            .appScaffoldingLoaded, .audioPocPitchDetected, .cloudKitSyncCompleted,
            .tabSelected, .sessionStarted, .sessionEnded
        ]
        for event in events {
            // Verify snake_case: only lowercase letters, digits, and underscores
            let isSnakeCase = event.rawValue.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" }
            #expect(isSnakeCase, "Event '\(event.rawValue)' should be snake_case")
        }
    }

    @Test("Sprint 0 verification events exist")
    func testSprint0Events() {
        #expect(AnalyticsEvent.appScaffoldingLoaded.rawValue == "app_scaffolding_loaded")
        #expect(AnalyticsEvent.audioPocPitchDetected.rawValue == "audio_poc_pitch_detected")
        #expect(AnalyticsEvent.cloudKitSyncCompleted.rawValue == "cloudkit_sync_completed")
    }

    @Test("Song Import events have correct raw values")
    func songImportEventsHaveCorrectRawValues() {
        #expect(AnalyticsEvent.songImportStarted.rawValue == "song_import_started")
        #expect(AnalyticsEvent.songImportCompleted.rawValue == "song_import_completed")
        #expect(AnalyticsEvent.songImportFailed.rawValue == "song_import_failed")
        #expect(AnalyticsEvent.importMidiPlaybackStarted.rawValue == "import_midi_playback_started")
        #expect(AnalyticsEvent.songImportSynced.rawValue == "song_import_synced")
        #expect(AnalyticsEvent.songImportWarningDisplayed.rawValue == "song_import_warning_displayed")
    }

    @Test("Play-Along toolbar interaction events have correct raw values")
    func playAlongToolbarEventsHaveCorrectRawValues() {
        #expect(AnalyticsEvent.playAlongTempoChanged.rawValue == "play_along_tempo_changed")
        #expect(AnalyticsEvent.playAlongViewModeChanged.rawValue == "play_along_view_mode_changed")
        #expect(AnalyticsEvent.playAlongNotationToggled.rawValue == "play_along_notation_toggled")
        #expect(AnalyticsEvent.playAlongSoundToggled.rawValue == "play_along_sound_toggled")
        #expect(AnalyticsEvent.playAlongRestarted.rawValue == "play_along_restarted")
    }

    @Test func tanpuraToggledHasExpectedRawValue() {
        #expect(AnalyticsEvent.tanpuraToggled.rawValue == "play_along_tanpura_toggled")
    }

    @Test func tanpuraSaChangedHasExpectedRawValue() {
        #expect(AnalyticsEvent.tanpuraSaChanged.rawValue == "play_along_tanpura_sa_changed")
    }

    @Test func tanpuraResetToDefaultHasExpectedRawValue() {
        #expect(AnalyticsEvent.tanpuraResetToDefault.rawValue == "play_along_tanpura_reset_to_default")
    }

    @Test func tanpuraSheetOpenedHasExpectedRawValue() {
        #expect(AnalyticsEvent.tanpuraSheetOpened.rawValue == "play_along_tanpura_sheet_opened")
    }
}
