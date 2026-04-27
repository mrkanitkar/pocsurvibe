import Foundation
import Testing

@testable import SVAudio

@Suite("AuditionEngine + Factory")
struct AuditionEngineFactoryTests {

    @Test("EngineKind has both expected cases with stable rawValues")
    func engineKindCases() {
        #expect(EngineKind.allCases.count == 2)
        #expect(EngineKind.apple.rawValue == "apple")
        #expect(EngineKind.fluidsynth.rawValue == "fluidsynth")
    }

    @Test("EngineKind has display names suitable for the picker")
    func engineKindDisplayNames() {
        #expect(EngineKind.apple.displayName == "Apple AVAudioUnitSampler")
        #expect(EngineKind.fluidsynth.displayName == "FluidSynth 2.5")
    }

    @Test("RealtimeMIDIEvent stores all five MIDI bytes")
    func realtimeMIDIEventStoresBytes() {
        let event = RealtimeMIDIEvent(
            timestamp: 1234, channel: 9, status: 0x90, data1: 60, data2: 100
        )
        #expect(event.timestamp == 1234)
        #expect(event.channel == 9)
        #expect(event.status == 0x90)
        #expect(event.data1 == 60)
        #expect(event.data2 == 100)
    }
}
