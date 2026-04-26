#if DEBUG
import AVFoundation
import AudioKit
import SVAudio
import SwiftUI

/// DEBUG-only section embedded inside `SoundFontAuditionView`.
/// Owns the multi-channel pipeline lifecycle (graph + bouncer) and
/// renders the toggle, status, tempo slider, transport, and bounce UI.
@MainActor
struct AuditionPipelineSection: View {

    /// The two SF2 banks the parent audition view exposes.
    let bankA: URL?
    let bankB: URL?

    /// Which bank the parent's segmented control currently shows.
    let activeSlot: SoundFontAuditionView.Slot

    @State private var pipelineEnabled = false
    @State private var graph: MultiTrackSamplerGraph?
    @State private var rendered: RenderedMIDI?
    @State private var statusText: String = ""
    @State private var loadError: String?
    @State private var tempo: Float = 1.0
    @State private var bounceURLA: URL?
    @State private var bounceURLB: URL?
    @State private var bouncer: RealtimeTapBouncer?
    @State private var isBouncing = false

    /// Default per-track GM presets, indexed by track index.
    /// Track 0=melody, 1=bass, 2=brass, 3=strings, 4=organ, 5=lead,
    /// 6=pad, then GM 0 (acoustic grand) for tracks 7-15.
    ///
    /// **Known gap (deferred to follow-up):** the spec also asks for
    /// honoring embedded `<midi-program>` Program Change events and
    /// auto-overriding tracks on MIDI channel 9 to the SF2 percussion
    /// bank. v1 of the POC ships these hardcoded defaults only.
    private static let defaultPresets: [UInt8] = [0, 33, 61, 48, 18, 80, 88, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    var body: some View {
        Section("Multi-instrument Pipeline") {
            Toggle("Use multi-channel pipeline", isOn: $pipelineEnabled)
                .accessibilityLabel("Enable multi-channel audition pipeline")
                .onChange(of: pipelineEnabled) { _, newValue in
                    if newValue {
                        Task { await enablePipeline() }
                    } else {
                        disablePipeline()
                    }
                }
            if !statusText.isEmpty {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Pipeline status: \(statusText)")
            }
            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Pipeline error: \(loadError)")
            }
            if pipelineEnabled, graph != nil {
                tempoControl
                transportControls
                bounceControls
            }
        }
        .onChange(of: activeSlot) { _, newValue in
            Task { await applyActiveBank(newValue) }
        }
    }

    private var tempoControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "Tempo")
                Spacer()
                Text(verbatim: String(format: "%.2f×", tempo))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $tempo, in: 0.5...1.5, step: 0.05) {
                Text("Tempo")
            } minimumValueLabel: {
                Text(verbatim: "0.5×").font(.caption2)
            } maximumValueLabel: {
                Text(verbatim: "1.5×").font(.caption2)
            }
            .accessibilityLabel("Pipeline playback tempo")
            .accessibilityValue(String(format: "%.2f times", tempo))
            .onChange(of: tempo) { _, newValue in graph?.setTempo(rate: newValue) }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 16) {
            Button {
                do { try graph?.play() } catch { loadError = error.localizedDescription }
            } label: { Label("Play", systemImage: "play.fill") }
                .accessibilityLabel("Play pipeline")
                .disabled(graph?.sequencer == nil)
            Button {
                graph?.pause()
            } label: { Label("Pause", systemImage: "pause.fill") }
                .accessibilityLabel("Pause pipeline")
            Button {
                graph?.stop()
            } label: { Label("Stop", systemImage: "stop.fill") }
                .accessibilityLabel("Stop pipeline and reset")
        }
    }

    private var bounceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Button {
                    Task { await bounce(slot: .a) }
                } label: { Label("Bounce A → m4a", systemImage: "arrow.down.circle") }
                    .accessibilityLabel("Bounce bank A to m4a file")
                    .disabled(isBouncing || bankA == nil)
                Button {
                    Task { await bounce(slot: .b) }
                } label: { Label("Bounce B → m4a", systemImage: "arrow.down.circle") }
                    .accessibilityLabel("Bounce bank B to m4a file")
                    .disabled(isBouncing || bankB == nil)
            }
            if let bounceURLA {
                bounceResultRow(label: "audition_bond_A.m4a", url: bounceURLA)
            }
            if let bounceURLB {
                bounceResultRow(label: "audition_bond_B.m4a", url: bounceURLB)
            }
        }
    }

    private func bounceResultRow(label: String, url: URL) -> some View {
        HStack {
            Text(verbatim: label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Lifecycle

    private func enablePipeline() async {
        statusText = "Loading bond.mxl..."
        loadError = nil
        do {
            try AudioEngineManager.shared.startForPlayback()

            guard let mxlURL = Bundle.main.url(
                forResource: "james-bond-theme", withExtension: "mxl"
            ) else {
                throw PipelineError.resourceMissing(name: "james-bond-theme.mxl")
            }
            let mxlData = try Data(contentsOf: mxlURL)
            let xml = try MXLLoader.loadMusicXML(from: mxlData)
            let bridge = VerovioBridge()
            let renderedMIDI = try bridge.render(musicXML: xml)
            self.rendered = renderedMIDI

            let trackCount = min(renderedMIDI.trackCount, MultiTrackSamplerGraph.maxTracks)
            let g = try MultiTrackSamplerGraph(trackCount: trackCount)
            try g.loadMIDI(renderedMIDI)
            self.graph = g

            // Initial bank load uses the parent's active slot.
            await applyActiveBank(activeSlot)

            let chList = renderedMIDI.channels.map { String($0) }.joined(separator: ", ")
            statusText = "✓ \(trackCount) tracks · channels [\(chList)]"
        } catch let pipelineError as PipelineError {
            loadError = pipelineError.localizedDescription
            disablePipeline()
        } catch {
            loadError = "Pipeline failed: \(error.localizedDescription)"
            disablePipeline()
        }
    }

    private func disablePipeline() {
        graph?.stop()
        graph?.teardown()
        graph = nil
        rendered = nil
        statusText = ""
    }

    private func applyActiveBank(_ slot: SoundFontAuditionView.Slot) async {
        guard let g = graph else { return }
        let url: URL? = (slot == .a) ? bankA : bankB
        guard let url else { return }
        let presets = Array(Self.defaultPresets.prefix(g.samplers.count))
        do {
            try g.loadBank(at: url, presets: presets)
        } catch {
            loadError = "Bank load failed: \(error.localizedDescription)"
        }
    }

    private func bounce(slot: SoundFontAuditionView.Slot) async {
        guard let g = graph else { return }
        isBouncing = true
        defer { isBouncing = false }

        let filename = "audition_bond_\(slot.rawValue).m4a"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)

        let b = RealtimeTapBouncer(source: g.subMixer, outputURL: url)
        bouncer = b
        do {
            g.stop()
            try b.start()
            try g.play()
            // Wait until the sequencer reports it's no longer playing.
            while g.isPlaying {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            b.stop()
            switch slot {
            case .a: bounceURLA = url
            case .b: bounceURLB = url
            }
        } catch {
            b.abort()
            loadError = "Bounce failed: \(error.localizedDescription)"
        }
    }
}
#endif
