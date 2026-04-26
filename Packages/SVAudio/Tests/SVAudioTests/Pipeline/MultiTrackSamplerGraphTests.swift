import AVFoundation
import AudioKit
import Foundation
import Testing

@testable import SVAudio

@Suite("MultiTrackSamplerGraph — graph topology")
@MainActor
struct MultiTrackSamplerGraphTests {

    @Test("Attaches N samplers + sub-mixer + TimePitch to engine")
    func attachesNodes() throws {
        try AudioEngineManager.shared.startForPlayback()
        let engine = AudioEngineManager.shared.engine
        let baselineNodes = countAttachedNodes(in: engine)

        let graph = try MultiTrackSamplerGraph(trackCount: 3)

        // Expect: +3 samplers, +1 sub-mixer, +1 TimePitch = +5 nodes.
        #expect(countAttachedNodes(in: engine) == baselineNodes + 5)

        graph.teardown()
        #expect(countAttachedNodes(in: engine) == baselineNodes)
    }

    @Test("Throws .tooManyTracks when N > 16")
    func capsAt16() throws {
        try AudioEngineManager.shared.startForPlayback()
        #expect(throws: PipelineError.self) {
            _ = try MultiTrackSamplerGraph(trackCount: 17)
        }
    }

    @Test("Throws .engineNotRunning when engine is stopped")
    func requiresRunningEngine() throws {
        AudioEngineManager.shared.stop()
        #expect(throws: PipelineError.self) {
            _ = try MultiTrackSamplerGraph(trackCount: 2)
        }
    }

    @Test("loadBank populates each sampler with the SF2 (Mode 2)")
    func loadBankSequential() throws {
        try AudioEngineManager.shared.startForPlayback()
        guard let sf2 = Bundle.main.url(
            forResource: "MuseScore_General", withExtension: "sf2"
        ) else { return /* skip if asset missing */ }

        let graph = try MultiTrackSamplerGraph(trackCount: 2)
        // Default presets: melody=0, bass=33
        try graph.loadBank(at: sf2, presets: [0, 33])
        // No assertion on audio output — just that no throw occurred.
        // A subsequent integration test on iPad covers audible verification.
        graph.teardown()
    }

    @Test("loadMIDI builds sequencer with N tracks routed by index")
    func loadsMIDIAndRoutes() throws {
        try AudioEngineManager.shared.startForPlayback()

        // Trivial 2-track MIDI rendered by Verovio so the fixture is
        // always in sync with what real Verovio output looks like:
        //   Part 1: 1 quarter note (C4)
        //   Part 2: 1 quarter note (E4)
        let midi = try Data(contentsOf: Self.fixtureMIDI())

        let graph = try MultiTrackSamplerGraph(trackCount: 2)
        try graph.loadMIDI(RenderedMIDI(data: midi, trackCount: 2, channels: [0, 1]))

        #expect(graph.sequencer != nil)
        #expect(graph.sequencer?.tracks.count == 2)

        graph.teardown()
    }

    @Test("setTempo clamps to 0.5–1.5 range")
    func tempoClamps() throws {
        try AudioEngineManager.shared.startForPlayback()
        let graph = try MultiTrackSamplerGraph(trackCount: 1)

        graph.setTempo(rate: 0.25)
        #expect(graph.timePitch.rate == 0.5)

        graph.setTempo(rate: 5.0)
        #expect(graph.timePitch.rate == 1.5)

        graph.setTempo(rate: 1.0)
        #expect(graph.timePitch.rate == 1.0)

        graph.teardown()
    }

    @Test("play/pause/stop round-trips without throwing")
    func transportRoundTrip() throws {
        try AudioEngineManager.shared.startForPlayback()
        guard let mxlURL = Bundle.main.url(forResource: "james-bond-theme", withExtension: "mxl")
        else { return }
        let xml = try MXLLoader.loadMusicXML(from: try Data(contentsOf: mxlURL))
        let bridge = VerovioBridge()
        let rendered = try bridge.render(musicXML: xml)

        let graph = try MultiTrackSamplerGraph(trackCount: min(rendered.trackCount, 4))
        try graph.loadMIDI(rendered)

        try graph.play()
        #expect(graph.isPlaying == true)

        graph.pause()
        #expect(graph.isPlaying == false)

        graph.stop()
        #expect(graph.isPlaying == false)
        #expect(graph.sequencer?.currentPositionInSeconds == 0)

        graph.teardown()
    }

    private func countAttachedNodes(in engine: AVAudioEngine) -> Int {
        // AVAudioEngine doesn't expose node count directly; use the
        // attachedNodes count via the private `attachedNodes` set is
        // not stable. Use mainMixer's input-bus count as a proxy.
        engine.mainMixerNode.numberOfInputs
    }

    /// Use Verovio to render a 2-part trivial score so the fixture is
    /// always in sync with what real Verovio output looks like.
    @MainActor
    private static func fixtureMIDI() throws -> URL {
        let xml = """
            <?xml version="1.0"?>
            <score-partwise version="3.1">
              <part-list>
                <score-part id="P1"/><score-part id="P2"/>
              </part-list>
              <part id="P1"><measure number="1">
                <attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
                <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              </measure></part>
              <part id="P2"><measure number="1">
                <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
              </measure></part>
            </score-partwise>
            """
        let bridge = VerovioBridge()
        let rendered = try bridge.render(musicXML: xml)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture.mid")
        try rendered.data.write(to: url)
        return url
    }
}
