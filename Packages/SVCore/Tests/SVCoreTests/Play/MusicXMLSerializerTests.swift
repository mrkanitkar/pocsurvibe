import Foundation
import Testing
@testable import SVCore

struct MusicXMLSerializerTests {
    @Test func emitsXMLDeclarationAndDoctype() throws {
        let score = QuantizedScore(bpm: 80, timeSignature: .fourFour, measures: [])
        let xml = MusicXMLSerializer.serialize(score: score)
        #expect(xml.hasPrefix(#"<?xml version="1.0" encoding="UTF-8" standalone="no"?>"#))
        #expect(xml.contains(#"<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">"#))
        #expect(xml.contains(#"<score-partwise version="4.0">"#))
        // No namespace per W3C MusicXML 4.0.
        #expect(!xml.contains("xmlns="))
    }

    @Test func twoStaffPianoPartList() throws {
        let score = QuantizedScore(bpm: 80, timeSignature: .fourFour, measures: [])
        let xml = MusicXMLSerializer.serialize(score: score)
        #expect(xml.contains(#"<score-part id="P1">"#))
        #expect(xml.contains("<part-name>Piano</part-name>"))
    }

    @Test func firstMeasureHasDivisionsKeyTimeAndStaves() throws {
        let measure = QuantizedMeasure(number: 1, notes: [
            QuantizedNote(midi: 60, startBeat: 0, duration: .quarter, velocity: 90, staff: .treble, voice: 1),
        ])
        let score = QuantizedScore(bpm: 80, timeSignature: .fourFour, measures: [measure])
        let xml = MusicXMLSerializer.serialize(score: score)
        #expect(xml.contains("<divisions>"))
        #expect(xml.contains("<staves>2</staves>"))
        #expect(xml.contains(#"<clef number="1">"#))
        #expect(xml.contains(#"<clef number="2">"#))
        #expect(xml.contains("<sign>G</sign>"))
        #expect(xml.contains("<sign>F</sign>"))
        #expect(xml.contains("<beats>4</beats>"))
        #expect(xml.contains("<beat-type>4</beat-type>"))
    }

    @Test func goldenSaReGaMaMatches() throws {
        let measure = QuantizedMeasure(number: 1, notes: [
            QuantizedNote(midi: 60, startBeat: 0, duration: .quarter, velocity: 90, staff: .treble, voice: 1),
            QuantizedNote(midi: 62, startBeat: 1, duration: .quarter, velocity: 90, staff: .treble, voice: 1),
            QuantizedNote(midi: 64, startBeat: 2, duration: .quarter, velocity: 90, staff: .treble, voice: 1),
            QuantizedNote(midi: 65, startBeat: 3, duration: .quarter, velocity: 90, staff: .treble, voice: 1),
        ])
        let score = QuantizedScore(bpm: 80, timeSignature: .fourFour, measures: [measure])
        let actual = MusicXMLSerializer.serialize(score: score)
        let url = Bundle.module.url(
            forResource: "sa-re-ga-ma",
            withExtension: "musicxml",
            subdirectory: "Play"
        )
        let unwrappedURL = try #require(url)
        let expected = try String(contentsOf: unwrappedURL, encoding: .utf8)
        #expect(actual == expected)
    }
}
