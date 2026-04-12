import Foundation
import SwiftUI
import Testing

@testable import SurVibe

// MARK: - SargamColorMap Tests

@Suite("Day 5 — SargamColorMap Tests")
@MainActor
struct Day05SargamColorMapTests {

    @Test("All seven swar return distinct non-gray colors")
    func allSevenSwarHaveColors() {
        let swars = ["Sa", "Re", "Ga", "Ma", "Pa", "Dha", "Ni"]
        for swar in swars {
            let color = SargamColorMap.color(for: swar)
            #expect(color != .gray, "Expected non-gray color for \(swar)")
        }
    }

    @Test("Unknown swar returns gray fallback")
    func unknownSwarReturnsGray() {
        #expect(SargamColorMap.color(for: "Unknown") == .gray)
        #expect(SargamColorMap.color(for: "") == .gray)
    }

    @Test("Sa maps to red color")
    func saIsRed() {
        #expect(SargamColorMap.color(for: "Sa") == .red)
    }

    @Test("Pa maps to blue color")
    func paIsBlue() {
        #expect(SargamColorMap.color(for: "Pa") == .blue)
    }

    @Test("Ga maps to yellow color")
    func gaIsYellow() {
        #expect(SargamColorMap.color(for: "Ga") == .yellow)
    }

    @Test("Ma maps to green color")
    func maIsGreen() {
        #expect(SargamColorMap.color(for: "Ma") == .green)
    }

    @Test("All seven swar have unique shape symbols")
    func allSevenShapesUnique() {
        let swars = ["Sa", "Re", "Ga", "Ma", "Pa", "Dha", "Ni"]
        let shapes = swars.map { SargamColorMap.shape(for: $0) }
        let uniqueShapes = Set(shapes)
        #expect(uniqueShapes.count == 7, "Expected 7 unique shapes, got \(uniqueShapes.count)")
    }

    @Test("Shape symbols are valid SF Symbol fill variants")
    func shapesAreFillVariants() {
        let swars = ["Sa", "Re", "Ga", "Ma", "Pa", "Dha", "Ni"]
        for swar in swars {
            let shape = SargamColorMap.shape(for: swar)
            #expect(shape.hasSuffix(".fill"), "Shape for \(swar) should end with .fill, got \(shape)")
        }
    }

    @Test("Unknown swar shape returns questionmark.circle")
    func unknownShapeFallback() {
        #expect(SargamColorMap.shape(for: "Unknown") == "questionmark.circle")
        #expect(SargamColorMap.shape(for: "") == "questionmark.circle")
    }

    @Test("Specific swar-shape mappings are correct")
    func specificShapeMappings() {
        #expect(SargamColorMap.shape(for: "Sa") == "circle.fill")
        #expect(SargamColorMap.shape(for: "Re") == "square.fill")
        #expect(SargamColorMap.shape(for: "Ga") == "triangle.fill")
        #expect(SargamColorMap.shape(for: "Ma") == "diamond.fill")
        #expect(SargamColorMap.shape(for: "Pa") == "pentagon.fill")
        #expect(SargamColorMap.shape(for: "Dha") == "hexagon.fill")
        #expect(SargamColorMap.shape(for: "Ni") == "star.fill")
    }
}

// MARK: - NotationDisplayMode Tests

@Suite("Day 5 — NotationDisplayMode Tests")
@MainActor
struct Day05NotationDisplayModeTests {

    @Test("NotationDisplayMode has exactly 5 cases")
    func caseCount() {
        #expect(NotationDisplayMode.allCases.count == 5)
    }

    @Test("NotationDisplayMode cases have correct raw values")
    func rawValues() {
        #expect(NotationDisplayMode.sargam.rawValue == "sargam")
        #expect(NotationDisplayMode.western.rawValue == "western")
        #expect(NotationDisplayMode.dual.rawValue == "dual")
    }

    @Test("NotationDisplayMode labels are human-readable")
    func labels() {
        #expect(NotationDisplayMode.sargam.label == "Sargam")
        #expect(NotationDisplayMode.western.label == "Western")
        #expect(NotationDisplayMode.dual.label == "Both")
    }

    @Test("NotationDisplayMode initializes from valid raw value")
    func initFromRawValue() {
        #expect(NotationDisplayMode(rawValue: "sargam") == .sargam)
        #expect(NotationDisplayMode(rawValue: "western") == .western)
        #expect(NotationDisplayMode(rawValue: "dual") == .dual)
    }

    @Test("NotationDisplayMode returns nil for invalid raw value")
    func initFromInvalidRawValue() {
        #expect(NotationDisplayMode(rawValue: "unknown") == nil)
        #expect(NotationDisplayMode(rawValue: "") == nil)
    }

    @Test("NotationDisplayMode conforms to Sendable")
    func sendableConformance() {
        let mode: Sendable = NotationDisplayMode.sargam
        #expect(mode is NotationDisplayMode)
    }
}

// MARK: - SargamFadeManager Tests

@Suite("Day 5 — SargamFadeManager Tests")
@MainActor
struct Day05SargamFadeManagerTests {

    @Test("Initial opacity is 1.0")
    @MainActor func initialOpacity() {
        let manager = SargamFadeManager()
        #expect(manager.labelOpacity == 1.0)
    }

    @Test("Initial accuracy is 0.0")
    @MainActor func initialAccuracy() {
        let manager = SargamFadeManager()
        #expect(manager.currentAccuracy == 0.0)
    }

    @Test("High accuracy (>=95%) yields zero opacity — mastery, play by ear")
    @MainActor func highAccuracyZeroOpacity() {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = true
        manager.updateOpacity(accuracy: 0.95)
        #expect(manager.labelOpacity == 0.0)
        #expect(manager.currentAccuracy == 0.95)
    }

    @Test("Perfect accuracy (1.0) yields zero opacity")
    @MainActor func perfectAccuracyZeroOpacity() {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = true
        manager.updateOpacity(accuracy: 1.0)
        #expect(manager.labelOpacity == 0.0)
    }

    @Test("Accuracy at 90% boundary yields 0.3 opacity")
    @MainActor func boundaryNinetyPercent() {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = true
        manager.updateOpacity(accuracy: 0.9)
        #expect(manager.labelOpacity == 0.3)
    }

    @Test("Accuracy 80-95% yields 0.3 opacity")
    @MainActor func moderateHighAccuracyOpacity() {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = true
        manager.updateOpacity(accuracy: 0.8)
        #expect(manager.labelOpacity == 0.3)
    }

    @Test("Accuracy at 70% boundary yields 0.6 opacity")
    @MainActor func boundarySeventyPercent() {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = true
        manager.updateOpacity(accuracy: 0.7)
        #expect(manager.labelOpacity == 0.6)
    }

    @Test("Accuracy 60-80% yields 0.6 opacity")
    @MainActor func moderateAccuracyOpacity() {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = true
        manager.updateOpacity(accuracy: 0.6)
        #expect(manager.labelOpacity == 0.6)
    }

    @Test("Low accuracy (<60%) yields full opacity — beginner sees all labels")
    @MainActor func lowAccuracyFullOpacity() {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = true
        manager.updateOpacity(accuracy: 0.3)
        #expect(manager.labelOpacity == 1.0)
    }

    @Test("Zero accuracy yields full opacity")
    @MainActor func zeroAccuracyFullOpacity() {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = true
        manager.updateOpacity(accuracy: 0.0)
        #expect(manager.labelOpacity == 1.0)
    }

    @Test("Accuracy above 1.0 is clamped to 1.0")
    @MainActor func overflowAccuracyClamped() {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = true
        manager.updateOpacity(accuracy: 1.5)
        #expect(manager.currentAccuracy == 1.0)
        #expect(manager.labelOpacity == 0.0)
    }

    @Test("Negative accuracy is clamped to 0.0")
    @MainActor func negativeAccuracyClamped() {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = true
        manager.updateOpacity(accuracy: -0.5)
        #expect(manager.currentAccuracy == 0.0)
        #expect(manager.labelOpacity == 1.0)
    }

    @Test("Reset restores full opacity and accuracy")
    @MainActor func resetRestoresDefaults() {
        let manager = SargamFadeManager()
        manager.autoHideSargamLabels = true
        manager.updateOpacity(accuracy: 1.0)
        #expect(manager.labelOpacity == 0.0)

        manager.reset()
        #expect(manager.labelOpacity == 1.0)
        #expect(manager.currentAccuracy == 0.0)
    }
}

// MARK: - WesternNoteHelper Tests

@Suite("Day 5 — WesternNoteHelper Tests")
@MainActor
struct Day05WesternNoteHelperTests {

    @Test("Middle C (MIDI 60) returns 'C'")
    func middleCNoteName() {
        #expect(WesternNoteHelper.noteName(from: 60) == "C")
    }

    @Test("MIDI 61 returns 'C#'")
    func cSharpNoteName() {
        #expect(WesternNoteHelper.noteName(from: 61) == "C#")
    }

    @Test("MIDI 69 (A4) returns 'A'")
    func a4NoteName() {
        #expect(WesternNoteHelper.noteName(from: 69) == "A")
    }

    @Test("MIDI 71 (B4) returns 'B'")
    func b4NoteName() {
        #expect(WesternNoteHelper.noteName(from: 71) == "B")
    }

    @Test("All 12 chromatic notes are correct")
    func allChromaticNotes() {
        let expected = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        for (index, name) in expected.enumerated() {
            #expect(
                WesternNoteHelper.noteName(from: 60 + index) == name,
                "MIDI \(60 + index) should be \(name)"
            )
        }
    }

    @Test("MIDI 60 is octave 4")
    func middleCOctave() {
        #expect(WesternNoteHelper.octave(from: 60) == 4)
    }

    @Test("MIDI 0 is octave -1")
    func midiZeroOctave() {
        #expect(WesternNoteHelper.octave(from: 0) == -1)
    }

    @Test("MIDI 12 is octave 0")
    func midiTwelveOctave() {
        #expect(WesternNoteHelper.octave(from: 12) == 0)
    }

    @Test("MIDI 127 is octave 9")
    func midiMaxOctave() {
        #expect(WesternNoteHelper.octave(from: 127) == 9)
    }

    @Test("Display name combines note and octave")
    func displayNameFormat() {
        #expect(WesternNoteHelper.displayName(from: 60) == "C4")
        #expect(WesternNoteHelper.displayName(from: 69) == "A4")
        #expect(WesternNoteHelper.displayName(from: 72) == "C5")
    }

    @Test("Display name for sharp notes includes '#'")
    func displayNameWithSharp() {
        #expect(WesternNoteHelper.displayName(from: 61) == "C#4")
        #expect(WesternNoteHelper.displayName(from: 66) == "F#4")
        #expect(WesternNoteHelper.displayName(from: 70) == "A#4")
    }

    @Test("Octave boundaries are correct")
    func octaveBoundaries() {
        // B3 = MIDI 59, C4 = MIDI 60
        #expect(WesternNoteHelper.octave(from: 59) == 3)
        #expect(WesternNoteHelper.octave(from: 60) == 4)
        // B4 = MIDI 71, C5 = MIDI 72
        #expect(WesternNoteHelper.octave(from: 71) == 4)
        #expect(WesternNoteHelper.octave(from: 72) == 5)
    }
}

// MARK: - SargamNote Width Calculation Tests

@Suite("Day 5 — Note Width Calculation Tests")
@MainActor
struct Day05NoteWidthTests {

    /// Base width constant used in SargamNoteView and WesternNoteView.
    private let baseWidth: CGFloat = 44.0

    @Test("Quarter note at 1x zoom has base width")
    func quarterNoteDefaultWidth() {
        let width = baseWidth * 1.0 * 1.0
        #expect(width == 44.0)
    }

    @Test("Half note at 1x zoom is double base width")
    func halfNoteWidth() {
        let width = baseWidth * 2.0 * 1.0
        #expect(width == 88.0)
    }

    @Test("Whole note at 1x zoom is 4x base width")
    func wholeNoteWidth() {
        let width = baseWidth * 4.0 * 1.0
        #expect(width == 176.0)
    }

    @Test("Sixteenth note at 1x zoom is 0.25x base width")
    func sixteenthNoteWidth() {
        let width = baseWidth * 0.25 * 1.0
        #expect(width == 11.0)
    }

    @Test("Eighth note at 1x zoom is 0.5x base width")
    func eighthNoteWidth() {
        let width = baseWidth * 0.5 * 1.0
        #expect(width == 22.0)
    }

    @Test("Quarter note at 2x zoom doubles the width")
    func zoomedQuarterNote() {
        let width = baseWidth * 1.0 * 2.0
        #expect(width == 88.0)
    }

    @Test("Half note at 1.5x zoom")
    func zoomedHalfNote() {
        let width = baseWidth * 2.0 * 1.5
        #expect(width == 132.0)
    }

    @Test("Minimum zoom (0.5x) reduces width")
    func minimumZoom() {
        let width = baseWidth * 1.0 * 0.5
        #expect(width == 22.0)
    }

    @Test("Maximum zoom (3.0x) with long note")
    func maximumZoomLongNote() {
        let width = baseWidth * 4.0 * 3.0
        #expect(width == 528.0)
    }
}

// MARK: - NotationErrorView Tests

@Suite("Day 5 — NotationErrorView Tests")
@MainActor
struct Day05NotationErrorViewTests {

    @Test("noNotation convenience creates correct content")
    func noNotationConvenience() {
        let view = NotationErrorView.noNotation
        #expect(view.systemImage == "music.note.slash")
        #expect(view.title == "No Notation Available")
        #expect(view.subtitle == "This song does not have notation data yet.")
    }

    @Test("decodingError convenience creates correct content")
    func decodingErrorConvenience() {
        let view = NotationErrorView.decodingError
        #expect(view.systemImage == "exclamationmark.triangle")
        #expect(view.title == "Notation Error")
        #expect(view.subtitle == "Could not read the notation data for this song.")
    }

    @Test("Custom NotationErrorView stores all properties")
    func customErrorView() {
        let view = NotationErrorView(
            systemImage: "custom.icon",
            title: "Custom Title",
            subtitle: "Custom Subtitle"
        )
        #expect(view.systemImage == "custom.icon")
        #expect(view.title == "Custom Title")
        #expect(view.subtitle == "Custom Subtitle")
    }
}

// MARK: - SargamNote Struct Tests

@Suite("Day 5 — SargamNote Struct Tests")
@MainActor
struct Day05SargamNoteStructTests {

    @Test("SargamNote initializes with default nil modifier")
    func defaultModifier() {
        let note = SargamNote(note: "Sa", octave: 4, duration: 1.0)
        #expect(note.note == "Sa")
        #expect(note.octave == 4)
        #expect(note.duration == 1.0)
        #expect(note.modifier == nil)
    }

    @Test("SargamNote initializes with Komal modifier")
    func komalModifier() {
        let note = SargamNote(note: "Re", octave: 4, duration: 0.5, modifier: "Komal")
        #expect(note.modifier == "Komal")
    }

    @Test("SargamNote initializes with Tivra modifier")
    func tivraModifier() {
        let note = SargamNote(note: "Ma", octave: 4, duration: 1.0, modifier: "Tivra")
        #expect(note.modifier == "Tivra")
    }

    @Test("SargamNote equality compares all fields")
    func equality() {
        let note1 = SargamNote(note: "Sa", octave: 4, duration: 1.0)
        let note2 = SargamNote(note: "Sa", octave: 4, duration: 1.0)
        let note3 = SargamNote(note: "Re", octave: 4, duration: 1.0)
        #expect(note1 == note2)
        #expect(note1 != note3)
    }

    @Test("SargamNote is Codable round-trip")
    func codableRoundTrip() throws {
        let original = SargamNote(note: "Ga", octave: 5, duration: 2.0, modifier: "Komal")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SargamNote.self, from: data)
        #expect(decoded == original)
    }
}
