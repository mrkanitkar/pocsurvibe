import AVFoundation
import Testing

@testable import SVAudio

@Suite("FluidSynthEngine")
@MainActor
struct FluidSynthEngineTests {

    @Test("New engine reports correct display name and not playing")
    func initialState() {
        let engine = FluidSynthEngine()
        #expect(engine.displayName == "FluidSynth 2.5")
        #expect(engine.isPlaying == false)
    }

    @Test("Setup attaches sub-mixer, teardown detaches")
    func setupTeardownLifecycle() throws {
        try AudioEngineManager.shared.startForPlayback()
        guard let sf2URL = Bundle.main.url(
            forResource: "MuseScore_General", withExtension: "sf2"
        ) else { return }
        let rendered = RenderedMIDI(
            data: makeTrivialSMF(), trackCount: 2, channels: [0],
            trackInfo: [TrackInfo(channel: 0, program: 0, isPercussion: false)]
        )
        let engine = FluidSynthEngine()
        try engine.setup(rendered: rendered, bankURL: sf2URL)
        #expect(engine.output.engine === AudioEngineManager.shared.engine)

        engine.tearDown()
        #expect(engine.output.engine == nil)
    }

    @Test("loadBank swaps SF2 without reattaching nodes")
    func loadBankSwapsSoundFont() throws {
        try AudioEngineManager.shared.startForPlayback()
        guard let sf2A = Bundle.main.url(
            forResource: "MuseScore_General", withExtension: "sf2"
        ), let sf2B = Bundle.main.url(
            forResource: "GeneralUser-GS", withExtension: "sf2"
        ) else { return }
        let rendered = RenderedMIDI(
            data: makeTrivialSMF(), trackCount: 2, channels: [0],
            trackInfo: [TrackInfo(channel: 0, program: 0, isPercussion: false)]
        )
        let engine = FluidSynthEngine()
        try engine.setup(rendered: rendered, bankURL: sf2A)
        try engine.loadBank(sf2B)
        engine.tearDown()
    }

    private func makeTrivialSMF() -> Data {
        let conductor: [UInt8] = [0x00, 0xFF, 0x2F, 0x00]
        let music: [UInt8] = [0x00, 0xC0, 0x00,
                               0x00, 0x90, 0x3C, 0x64,
                               0x40, 0x80, 0x3C, 0x00,
                               0x00, 0xFF, 0x2F, 0x00]
        func mtrk(_ d: [UInt8]) -> [UInt8] {
            let len = UInt32(d.count)
            return [0x4D, 0x54, 0x72, 0x6B,
                    UInt8((len >> 24) & 0xFF), UInt8((len >> 16) & 0xFF),
                    UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)] + d
        }
        let header: [UInt8] = [0x4D, 0x54, 0x68, 0x64,
                                0x00, 0x00, 0x00, 0x06,
                                0x00, 0x01, 0x00, 0x02, 0x00, 0x60]
        return Data(header + mtrk(conductor) + mtrk(music))
    }
}
