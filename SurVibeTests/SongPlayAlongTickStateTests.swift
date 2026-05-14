// SurVibeTests/SongPlayAlongTickStateTests.swift
import Foundation
import Testing
@testable import SurVibe

@MainActor
struct SongPlayAlongTickStateTests {

    @Test
    func defaultsAreEmpty() {
        let s = SongPlayAlongTickState()
        #expect(s.currentNoteIndex == nil)
        #expect(s.currentTime == 0)
        #expect(s.activeMidiNotes.isEmpty)
        #expect(s.userPressedNotes.isEmpty)
        #expect(s.detectedPitch == nil)
    }

    @Test
    func resetClearsEverything() {
        let s = SongPlayAlongTickState()
        s.currentNoteIndex = 5
        s.currentTime = 3.14
        s.activeMidiNotes = [60, 64, 67]
        s.userPressedNotes = [72]
        s.reset()
        #expect(s.currentNoteIndex == nil)
        #expect(s.currentTime == 0)
        #expect(s.activeMidiNotes.isEmpty)
        #expect(s.userPressedNotes.isEmpty)
        #expect(s.detectedPitch == nil)
    }
}
