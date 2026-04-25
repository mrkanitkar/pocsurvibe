import Foundation
import Testing

@testable import SVAudio

@Suite("PipelineError + RenderedMIDI")
struct PipelineErrorTests {

    @Test("RenderedMIDI initializer captures all fields")
    func renderedMIDIInit() {
        let bytes = Data([0x4D, 0x54, 0x68, 0x64])
        let rendered = RenderedMIDI(data: bytes, trackCount: 7, channels: [0, 1, 2, 9])
        #expect(rendered.data == bytes)
        #expect(rendered.trackCount == 7)
        #expect(rendered.channels == [0, 1, 2, 9])
    }

    @Test("PipelineError has localizedDescription for every case")
    func errorMessages() {
        let cases: [PipelineError] = [
            .resourceMissing(name: "x.mxl"),
            .mxlUnzipFailed(reason: "container.xml missing"),
            .verovioRenderFailed(reason: "invalid xml"),
            .midiDecodeFailed,
            .tooManyTracks(found: 23, max: 16),
            .engineNotRunning,
            .bounceFailed(reason: "disk full"),
        ]
        for error in cases {
            #expect(!error.localizedDescription.isEmpty)
        }
    }
}
