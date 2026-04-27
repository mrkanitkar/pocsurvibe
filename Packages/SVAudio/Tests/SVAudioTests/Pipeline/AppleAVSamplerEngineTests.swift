import AVFoundation
import Testing

@testable import SVAudio

@Suite("AppleAVSamplerEngine")
@MainActor
struct AppleAVSamplerEngineTests {

    @Test("New engine reports correct display name and not playing")
    func initialState() {
        let engine = AppleAVSamplerEngine()
        #expect(engine.displayName == "Apple AVAudioUnitSampler")
        #expect(engine.isPlaying == false)
    }

    @Test("output is a valid AVAudioNode after setup; sequenceDuration is positive")
    func outputIsValidAfterSetup() throws {
        try AudioEngineManager.shared.startForPlayback()

        // Minimal RenderedMIDI: 2 music tracks (+ conductor) with program changes + notes
        let bytes: [UInt8] = makeTrivialMultiTrackSMF()
        let rendered = RenderedMIDI(
            data: Data(bytes),
            trackCount: 3,  // including conductor
            channels: [0, 1],
            trackInfo: [
                TrackInfo(channel: 0, program: 0, isPercussion: false),
                TrackInfo(channel: 1, program: 33, isPercussion: false),
            ]
        )
        guard let sf2URL = Bundle.main.url(
            forResource: "MuseScore_General", withExtension: "sf2"
        ) else {
            Issue.record("MuseScore_General.sf2 missing from test bundle — skipping integration test")
            return
        }

        let engine = AppleAVSamplerEngine()
        try engine.setup(rendered: rendered, bankURL: sf2URL)
        #expect(engine.output.engine === AudioEngineManager.shared.engine)
        // Code review C-2 invariant: bounce relies on this returning > 0.
        #expect(engine.sequenceDuration > 0)
        engine.tearDown()
    }

    /// Builds a minimal Type 1 MIDI: header + conductor + 2 music tracks.
    private func makeTrivialMultiTrackSMF() -> [UInt8] {
        let vlq0: UInt8 = 0x00
        let eot: [UInt8] = [vlq0, 0xFF, 0x2F, 0x00]
        let conductor: [UInt8] = eot
        let music0: [UInt8] = [vlq0, 0xC0, 0x00,
                                vlq0, 0x90, 0x3C, 0x64,
                                0x40, 0x80, 0x3C, 0x00] + eot
        let music1: [UInt8] = [vlq0, 0xC1, 0x21,
                                vlq0, 0x91, 0x30, 0x50,
                                0x40, 0x81, 0x30, 0x00] + eot

        func mtrk(_ data: [UInt8]) -> [UInt8] {
            let len = UInt32(data.count)
            return [0x4D, 0x54, 0x72, 0x6B,
                    UInt8((len >> 24) & 0xFF), UInt8((len >> 16) & 0xFF),
                    UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)] + data
        }
        let header: [UInt8] = [0x4D, 0x54, 0x68, 0x64,
                                0x00, 0x00, 0x00, 0x06,
                                0x00, 0x01,
                                0x00, 0x03,
                                0x00, 0x60]
        return header + mtrk(conductor) + mtrk(music0) + mtrk(music1)
    }
}
