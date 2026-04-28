// Packages/SVAudio/Tests/SVAudioTests/MIDISourceTests.swift
import Foundation
import Testing

@testable import SVAudio

@Suite("MIDISource")
struct MIDISourceTests {

    @Test("midi case carries raw MIDI data")
    func midiCarriesData() {
        let bytes = Data([0x4D, 0x54, 0x68, 0x64])  // "MThd"
        let s = MIDISource.midi(bytes)
        switch s {
        case .midi(let d): #expect(d == bytes)
        case .musicXML: Issue.record("expected .midi case")
        }
    }

    @Test("musicXML case carries raw bytes")
    func musicXMLCarriesData() {
        let bytes = Data([0x50, 0x4B, 0x03, 0x04])  // "PK\x03\x04" — ZIP magic
        let s = MIDISource.musicXML(bytes)
        switch s {
        case .musicXML(let d): #expect(d == bytes)
        case .midi: Issue.record("expected .musicXML case")
        }
    }

    @Test("isLikelyMXLZip recognizes PK header")
    func zipDetection() {
        let zipBytes = Data([0x50, 0x4B, 0x03, 0x04, 0x00])
        #expect(MIDISource.isLikelyMXLZip(zipBytes))

        let xmlBytes = Data("<?xml".utf8)
        #expect(!MIDISource.isLikelyMXLZip(xmlBytes))

        let empty = Data()
        #expect(!MIDISource.isLikelyMXLZip(empty))
    }
}
