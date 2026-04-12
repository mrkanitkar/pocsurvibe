import Testing

@testable import SVAudio

@Suite("TanpuraEngine Tests")
struct TanpuraEngineTests {
    @Test("Default state is not playing")
    @MainActor
    func defaultStateIsNotPlaying() {
        let engine = TanpuraEngine()
        #expect(engine.isPlaying == false)
    }

    @Test("Volume defaults to 0.3")
    @MainActor
    func volumeDefaultsTo0_3() {
        let engine = TanpuraEngine()
        #expect(engine.volume == 0.3)
    }

    @Test("Sa frequency defaults to 261.63")
    @MainActor
    func saFrequencyDefaultsToC4() {
        let engine = TanpuraEngine()
        #expect(engine.saFrequency == 261.63)
    }

    @Test("Custom init sets values correctly")
    @MainActor
    func customInitSetsValues() {
        let engine = TanpuraEngine(saFrequency: 440.0, volume: 0.7)
        #expect(engine.saFrequency == 440.0)
        #expect(engine.volume == 0.7)
    }

    @Test("Update volume clamps to valid range")
    @MainActor
    func updateVolumeClamps() {
        let engine = TanpuraEngine()

        engine.updateVolume(0.5)
        #expect(engine.volume == 0.5)

        engine.updateVolume(-0.5)
        #expect(engine.volume == 0.0)

        engine.updateVolume(1.5)
        #expect(engine.volume == 1.0)

        engine.updateVolume(0.0)
        #expect(engine.volume == 0.0)

        engine.updateVolume(1.0)
        #expect(engine.volume == 1.0)
    }

    @Test("Stop sets not playing")
    @MainActor
    func stopSetsNotPlaying() {
        let engine = TanpuraEngine()
        engine.stop()
        #expect(engine.isPlaying == false)
    }

    @Test("Update Sa frequency stores new value")
    @MainActor
    func updateSaFrequencyStoresValue() throws {
        let engine = TanpuraEngine()
        try engine.updateSaFrequency(440.0)
        #expect(engine.saFrequency == 440.0)
    }
}
