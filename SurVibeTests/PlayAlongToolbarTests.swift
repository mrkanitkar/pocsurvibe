import Testing

@testable import SurVibe

// MARK: - Play/Pause Icon Tests

@MainActor
struct PlayAlongToolbarIconTests {

    @Test func idleStateShowsPlayIcon() {
        let icon = PlayAlongToolbar.playPauseIcon(for: .idle)
        #expect(icon == "play.fill")
    }

    @Test func playingStateShowsPauseIcon() {
        let icon = PlayAlongToolbar.playPauseIcon(for: .playing)
        #expect(icon == "pause.fill")
    }

    @Test func pausedStateShowsPlayIcon() {
        let icon = PlayAlongToolbar.playPauseIcon(for: .paused)
        #expect(icon == "play.fill")
    }

    @Test func stoppedStateShowsPlayIcon() {
        let icon = PlayAlongToolbar.playPauseIcon(for: .stopped)
        #expect(icon == "play.fill")
    }

    @Test func loadingStateShowsPlayIcon() {
        let icon = PlayAlongToolbar.playPauseIcon(for: .loading)
        #expect(icon == "play.fill")
    }

    @Test func errorStateShowsPlayIcon() {
        let icon = PlayAlongToolbar.playPauseIcon(for: .error("Something went wrong"))
        #expect(icon == "play.fill")
    }
}

// MARK: - Tempo Scale Tests

// formatTempoScale returns a percentage string, e.g. "75%".
@MainActor
struct PlayAlongToolbarTempoTests {

    @Test func formatTempoScaleShowsPercentForFullSpeed() {
        let formatted = PlayAlongToolbar.formatTempoScale(1.0)
        #expect(formatted == "100%")
    }

    @Test func formatTempoScaleShowsPercentForFraction() {
        let formatted = PlayAlongToolbar.formatTempoScale(0.75)
        #expect(formatted == "75%")
    }

    @Test func formatTempoScaleShowsPercentAtMinimum() {
        let formatted = PlayAlongToolbar.formatTempoScale(0.4)
        #expect(formatted == "40%")
    }

    @Test func formatTempoScaleShowsPercentAt60() {
        let formatted = PlayAlongToolbar.formatTempoScale(0.6)
        #expect(formatted == "60%")
    }
}

// MARK: - View Mode Tests

@MainActor
struct PlayAlongViewModeTests {

    @Test func allCasesContainsAllModes() {
        // fallingNotes, scrollingSheet, hide
        #expect(PlayAlongViewMode.allCases.count == 3)
        #expect(PlayAlongViewMode.allCases.contains(.fallingNotes))
        #expect(PlayAlongViewMode.allCases.contains(.scrollingSheet))
        #expect(PlayAlongViewMode.allCases.contains(.hide))
    }

    @Test func fallingNotesHasLabel() {
        #expect(!PlayAlongViewMode.fallingNotes.label.isEmpty)
    }

    @Test func scrollingSheetHasLabel() {
        #expect(!PlayAlongViewMode.scrollingSheet.label.isEmpty)
    }

    @Test func fallingNotesHasIcon() {
        #expect(!PlayAlongViewMode.fallingNotes.iconName.isEmpty)
    }

    @Test func scrollingSheetHasIcon() {
        #expect(!PlayAlongViewMode.scrollingSheet.iconName.isEmpty)
    }

    @Test func hideHasLabel() {
        #expect(!PlayAlongViewMode.hide.label.isEmpty)
    }

    @Test func hideHasIcon() {
        #expect(!PlayAlongViewMode.hide.iconName.isEmpty)
    }

    @Test func rawValueRoundTrips() {
        for mode in PlayAlongViewMode.allCases {
            #expect(PlayAlongViewMode(rawValue: mode.rawValue) == mode)
        }
    }
}

// MARK: - Notation Mode Cycling Tests

@MainActor
struct NotationModeCyclingTests {

    @Test func allNotationModesAvailable() {
        #expect(NotationDisplayMode.allCases.count == 5)
    }

    @Test func notationModeRawValueRoundTrips() {
        for mode in NotationDisplayMode.allCases {
            #expect(NotationDisplayMode(rawValue: mode.rawValue) == mode)
        }
    }

    @Test func eachNotationModeHasNonEmptyLabel() {
        for mode in NotationDisplayMode.allCases {
            #expect(!mode.label.isEmpty, "Mode \(mode) should have a non-empty label")
        }
    }

    @Test func eachNotationModeHasNonEmptyIcon() {
        for mode in NotationDisplayMode.allCases {
            #expect(!mode.iconName.isEmpty, "Mode \(mode) should have a non-empty icon name")
        }
    }
}
