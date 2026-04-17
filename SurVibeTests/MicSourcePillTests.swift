import SwiftUI
import Testing
@testable import SurVibe

struct MicSourcePillTests {
    @Test func micSourceInitializes() {
        _ = MicSourcePill(source: .mic, backgroundColor: .black, foregroundColor: .white)
    }

    @Test func midiSourceWithNameInitializes() {
        _ = MicSourcePill(source: .midi(deviceName: "Test Keyboard"), backgroundColor: .black, foregroundColor: .white)
    }

    @Test func midiSourceWithoutNameInitializes() {
        _ = MicSourcePill(source: .midi(deviceName: nil), backgroundColor: .black, foregroundColor: .white)
    }

    @Test func sourceEquatableWorks() {
        #expect(MicSourcePill.Source.mic == MicSourcePill.Source.mic)
        #expect(MicSourcePill.Source.midi(deviceName: "x") != MicSourcePill.Source.midi(deviceName: "y"))
    }
}
