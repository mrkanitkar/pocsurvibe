import Foundation
import SwiftUI
import Testing
@testable import SurVibe

@MainActor
struct FallingNotesLayoutEngineTests {

    // MARK: - pixelsPerSecond

    @Test func pixelsPerSecondBasicCalculation() {
        let pps = FallingNotesLayoutEngine.pixelsPerSecond(
            viewportHeight: 800,
            visibleDuration: 4.0
        )
        #expect(pps == 200.0)
    }

    @Test func pixelsPerSecondWithSmallViewport() {
        let pps = FallingNotesLayoutEngine.pixelsPerSecond(
            viewportHeight: 400,
            visibleDuration: 4.0
        )
        #expect(pps == 100.0)
    }

    @Test func pixelsPerSecondWithLargeVisibleDuration() {
        let pps = FallingNotesLayoutEngine.pixelsPerSecond(
            viewportHeight: 800,
            visibleDuration: 8.0
        )
        #expect(pps == 100.0)
    }

    @Test func pixelsPerSecondWithOneDuration() {
        let pps = FallingNotesLayoutEngine.pixelsPerSecond(
            viewportHeight: 600,
            visibleDuration: 1.0
        )
        #expect(pps == 600.0)
    }

    @Test func pixelsPerSecondWithZeroDurationReturnsZero() {
        let pps = FallingNotesLayoutEngine.pixelsPerSecond(
            viewportHeight: 800,
            visibleDuration: 0
        )
        #expect(pps == 0)
    }

    // MARK: - noteY

    @Test func noteYAtCurrentTimeIsAtBottom() {
        // A note whose timestamp equals currentTime should be at the bottom (viewportHeight).
        let y = FallingNotesLayoutEngine.noteY(
            noteTimestamp: 2.0,
            currentTime: 2.0,
            pixelsPerSecond: 200,
            viewportHeight: 800
        )
        #expect(y == 800.0)
    }

    @Test func noteYInFutureIsAboveBottom() {
        // A note 2 seconds in the future should be 400 points above the bottom.
        let y = FallingNotesLayoutEngine.noteY(
            noteTimestamp: 4.0,
            currentTime: 2.0,
            pixelsPerSecond: 200,
            viewportHeight: 800
        )
        // y = 800 - (4.0 - 2.0) * 200 = 800 - 400 = 400
        #expect(y == 400.0)
    }

    @Test func noteYInPastIsBelowViewport() {
        // A note 1 second in the past should be below the viewport.
        let y = FallingNotesLayoutEngine.noteY(
            noteTimestamp: 1.0,
            currentTime: 2.0,
            pixelsPerSecond: 200,
            viewportHeight: 800
        )
        // y = 800 - (1.0 - 2.0) * 200 = 800 - (-200) = 1000
        #expect(y == 1000.0)
    }

    @Test func noteYAtTopOfViewport() {
        // A note exactly visibleDuration (4s) in the future at the top.
        let y = FallingNotesLayoutEngine.noteY(
            noteTimestamp: 6.0,
            currentTime: 2.0,
            pixelsPerSecond: 200,
            viewportHeight: 800
        )
        // y = 800 - (6.0 - 2.0) * 200 = 800 - 800 = 0
        #expect(y == 0.0)
    }

    @Test func noteYFarInFutureIsNegative() {
        // A note well beyond the visible window.
        let y = FallingNotesLayoutEngine.noteY(
            noteTimestamp: 10.0,
            currentTime: 2.0,
            pixelsPerSecond: 200,
            viewportHeight: 800
        )
        // y = 800 - (10.0 - 2.0) * 200 = 800 - 1600 = -800
        #expect(y == -800.0)
    }

    // MARK: - noteHeight

    @Test func noteHeightBasicDuration() {
        let height = FallingNotesLayoutEngine.noteHeight(
            duration: 0.5,
            pixelsPerSecond: 200
        )
        #expect(height == 100.0)
    }

    @Test func noteHeightLongDuration() {
        let height = FallingNotesLayoutEngine.noteHeight(
            duration: 2.0,
            pixelsPerSecond: 200
        )
        #expect(height == 400.0)
    }

    @Test func noteHeightEnforcesMinimum() {
        // Very short note: 0.01s * 200 = 2 points, below minimum of 24.
        let height = FallingNotesLayoutEngine.noteHeight(
            duration: 0.01,
            pixelsPerSecond: 200
        )
        #expect(height == 24.0)
    }

    @Test func noteHeightWithCustomMinimum() {
        let height = FallingNotesLayoutEngine.noteHeight(
            duration: 0.01,
            pixelsPerSecond: 200,
            minimumHeight: 20
        )
        #expect(height == 20.0)
    }

    @Test func noteHeightZeroDurationUsesMinimum() {
        let height = FallingNotesLayoutEngine.noteHeight(
            duration: 0,
            pixelsPerSecond: 200
        )
        #expect(height == 24.0)
    }

    @Test func noteHeightExactlyAtMinimumIsNotBoosted() {
        // 0.12s * 200 = 24.0, exactly the new minimum.
        let height = FallingNotesLayoutEngine.noteHeight(
            duration: 0.12,
            pixelsPerSecond: 200
        )
        #expect(height == 24.0)
    }

    // MARK: - isNoteVisible

    @Test func fullyVisibleNoteIsVisible() {
        let visible = FallingNotesLayoutEngine.isNoteVisible(
            noteY: 300,
            noteHeight: 100,
            viewportHeight: 800
        )
        #expect(visible == true)
    }

    @Test func noteAboveViewportWithinPaddingIsVisible() {
        // Note top edge at -30, height 50 -> bottom at 20.
        // With default padding 50, bottom 20 > -50 and top -30 < 850.
        let visible = FallingNotesLayoutEngine.isNoteVisible(
            noteY: -30,
            noteHeight: 50,
            viewportHeight: 800
        )
        #expect(visible == true)
    }

    @Test func noteWellAboveViewportIsNotVisible() {
        // Note top at -200, height 50 -> bottom at -150. -150 < -50 (padding).
        let visible = FallingNotesLayoutEngine.isNoteVisible(
            noteY: -200,
            noteHeight: 50,
            viewportHeight: 800
        )
        #expect(visible == false)
    }

    @Test func noteBelowViewportWithinPaddingIsVisible() {
        // Note top at 830, within padding (830 < 800 + 50 = 850).
        let visible = FallingNotesLayoutEngine.isNoteVisible(
            noteY: 830,
            noteHeight: 50,
            viewportHeight: 800
        )
        #expect(visible == true)
    }

    @Test func noteWellBelowViewportIsNotVisible() {
        // Note top at 900, 900 < 850 is false.
        let visible = FallingNotesLayoutEngine.isNoteVisible(
            noteY: 900,
            noteHeight: 50,
            viewportHeight: 800
        )
        #expect(visible == false)
    }

    @Test func notePartiallyAboveIsVisible() {
        // Note top at -40, height 100, bottom at 60 -> visible.
        let visible = FallingNotesLayoutEngine.isNoteVisible(
            noteY: -40,
            noteHeight: 100,
            viewportHeight: 800
        )
        #expect(visible == true)
    }

    @Test func noteAtExactPaddingBoundaryAboveIsNotVisible() {
        // Note top at -100, height 50, bottom at -50.
        // Bottom (-50) > -50 is false, so not visible.
        let visible = FallingNotesLayoutEngine.isNoteVisible(
            noteY: -100,
            noteHeight: 50,
            viewportHeight: 800
        )
        #expect(visible == false)
    }

    @Test func isNoteVisibleWithCustomPadding() {
        // Note at -150, height 50, bottom at -100.
        // With padding 200, bottom -100 > -200 is true.
        let visible = FallingNotesLayoutEngine.isNoteVisible(
            noteY: -150,
            noteHeight: 50,
            viewportHeight: 800,
            padding: 200
        )
        #expect(visible == true)
    }

    @Test func isNoteVisibleWithZeroPadding() {
        // Note at -10, height 50, bottom at 40.
        // With padding 0: bottom 40 > 0, top -10 < 800 -> visible.
        let visible = FallingNotesLayoutEngine.isNoteVisible(
            noteY: -10,
            noteHeight: 50,
            viewportHeight: 800,
            padding: 0
        )
        #expect(visible == true)
    }

    // MARK: - noteX

    @Test func noteXFindsMatchingKey() {
        let positions = [
            KeyPosition(midiNote: 60, centerX: 100),
            KeyPosition(midiNote: 62, centerX: 150),
            KeyPosition(midiNote: 64, centerX: 200),
        ]
        let x = FallingNotesLayoutEngine.noteX(midiNote: 62, keyPositions: positions)
        #expect(x == 150)
    }

    @Test func noteXReturnsNilForMissingKey() {
        // MIDI 20 is outside the fallback range (36–96), so nil is returned
        // when there is no matching position entry.
        let positions = [
            KeyPosition(midiNote: 60, centerX: 100),
            KeyPosition(midiNote: 62, centerX: 150),
        ]
        let x = FallingNotesLayoutEngine.noteX(midiNote: 20, keyPositions: positions)
        #expect(x == nil)
    }

    @Test func noteXWithEmptyPositionsFallsBackToGeometry() {
        // MIDI 60 (C4) is within range 36–96, so the fallback geometry should return a value.
        let x = FallingNotesLayoutEngine.noteX(midiNote: 60, keyPositions: [], viewWidth: 390)
        #expect(x != nil)
    }

    @Test func noteXWithEmptyPositionsOutOfRangeReturnsNil() {
        // MIDI 20 is outside the 61-key range (36–96), so even the fallback returns nil.
        let x = FallingNotesLayoutEngine.noteX(midiNote: 20, keyPositions: [], viewWidth: 390)
        #expect(x == nil)
    }

    @Test func noteXReturnsFirstMatchForDuplicates() {
        let positions = [
            KeyPosition(midiNote: 60, centerX: 100),
            KeyPosition(midiNote: 60, centerX: 200),
        ]
        let x = FallingNotesLayoutEngine.noteX(midiNote: 60, keyPositions: positions)
        #expect(x == 100)
    }

    // MARK: - noteColor

    @Test func noteColorUpcoming() {
        // Upcoming notes use SargamColorMap at 60% opacity for Swar identity.
        let color = FallingNotesLayoutEngine.noteColor(state: .upcoming, swarName: "Sa")
        #expect(color == SargamColorMap.color(for: "Sa").opacity(0.6))
    }

    @Test func noteColorActive() {
        // Active notes use SargamColorMap at full opacity.
        let color = FallingNotesLayoutEngine.noteColor(state: .active, swarName: "Ma")
        #expect(color == SargamColorMap.color(for: "Ma"))
    }

    @Test func noteColorCorrect() {
        // Scored notes use traffic-light feedback colors regardless of Swar.
        let color = FallingNotesLayoutEngine.noteColor(state: .correct, swarName: "Sa")
        #expect(color == .green)
    }

    @Test func noteColorWrong() {
        let color = FallingNotesLayoutEngine.noteColor(state: .wrong, swarName: "Sa")
        #expect(color == .red)
    }

    @Test func noteColorMissed() {
        let color = FallingNotesLayoutEngine.noteColor(state: .missed, swarName: "Sa")
        #expect(color == .gray.opacity(0.4))
    }

    // MARK: - noteLabel

    @Test func noteLabelSargamMode() {
        let label = FallingNotesLayoutEngine.noteLabel(
            swarName: "Komal Re",
            westernName: "Db4",
            mode: .sargam
        )
        #expect(label == "Komal Re")
    }

    @Test func noteLabelWesternMode() {
        let label = FallingNotesLayoutEngine.noteLabel(
            swarName: "Sa",
            westernName: "C4",
            mode: .western
        )
        #expect(label == "C4")
    }

    @Test func noteLabelDualMode() {
        let label = FallingNotesLayoutEngine.noteLabel(
            swarName: "Pa",
            westernName: "G4",
            mode: .dual
        )
        #expect(label == "Pa\nG4")
    }

    @Test func noteLabelSheetMusicMode() {
        let label = FallingNotesLayoutEngine.noteLabel(
            swarName: "Ga",
            westernName: "E4",
            mode: .sheetMusic
        )
        #expect(label == "E4")
    }

    @Test func noteLabelSargamPlusSheetMode() {
        let label = FallingNotesLayoutEngine.noteLabel(
            swarName: "Dha",
            westernName: "A4",
            mode: .sargamPlusSheet
        )
        #expect(label == "Dha")
    }

    // MARK: - NoteState Equatable

    @Test func noteStateEquality() {
        #expect(FallingNotesLayoutEngine.NoteState.upcoming == .upcoming)
        #expect(FallingNotesLayoutEngine.NoteState.active == .active)
        #expect(FallingNotesLayoutEngine.NoteState.correct != .wrong)
        #expect(FallingNotesLayoutEngine.NoteState.missed != .upcoming)
    }

    // MARK: - Integration: End-to-End Layout

    @Test func endToEndNotePositioning() {
        // Viewport: 800pt, 4s visible -> 200 pps.
        // Note at t=3.0s, current time=2.0s -> 1s in future -> y = 800 - 200 = 600.
        // Duration 0.5s -> height = 100pt.
        let viewportHeight: CGFloat = 800
        let visibleDuration: TimeInterval = 4.0
        let pps = FallingNotesLayoutEngine.pixelsPerSecond(
            viewportHeight: viewportHeight,
            visibleDuration: visibleDuration
        )

        let y = FallingNotesLayoutEngine.noteY(
            noteTimestamp: 3.0,
            currentTime: 2.0,
            pixelsPerSecond: pps,
            viewportHeight: viewportHeight
        )
        let height = FallingNotesLayoutEngine.noteHeight(
            duration: 0.5,
            pixelsPerSecond: pps
        )

        #expect(pps == 200.0)
        #expect(y == 600.0)
        #expect(height == 100.0)

        let visible = FallingNotesLayoutEngine.isNoteVisible(
            noteY: y,
            noteHeight: height,
            viewportHeight: viewportHeight
        )
        #expect(visible == true)
    }

    @Test func endToEndNoteOffScreenCulled() {
        let viewportHeight: CGFloat = 800
        let pps = FallingNotesLayoutEngine.pixelsPerSecond(
            viewportHeight: viewportHeight,
            visibleDuration: 4.0
        )

        // Note 10 seconds in the future: y = 800 - 8*200 = -800.
        let y = FallingNotesLayoutEngine.noteY(
            noteTimestamp: 12.0,
            currentTime: 2.0,
            pixelsPerSecond: pps,
            viewportHeight: viewportHeight
        )
        let height = FallingNotesLayoutEngine.noteHeight(
            duration: 0.5,
            pixelsPerSecond: pps
        )

        // y = -1200, height = 100. Bottom = -1100, far above -50 padding.
        // Actually: y = 800 - (12-2)*200 = 800 - 2000 = -1200
        // bottom = -1200 + 100 = -1100. -1100 > -50 is false.
        let visible = FallingNotesLayoutEngine.isNoteVisible(
            noteY: y,
            noteHeight: height,
            viewportHeight: viewportHeight
        )
        #expect(visible == false)
    }
}
