#if DEBUG
import AVFoundation
import AudioKit
import SVAudio
import SwiftUI
import os

private let sectionLogger = Logger(
    subsystem: "com.survibe", category: "AuditionPipelineSection"
)

/// DEBUG-only audition page section. Hosts a song picker and the
/// multi-channel pipeline lifecycle (graph, transport, tempo). Bank A/B
/// pickers and the Active selector live in the parent view.
@MainActor
struct AuditionPipelineSection: View {

    let bankA: URL?
    let bankB: URL?
    let activeSlot: SoundFontAuditionView.Slot

    @State private var graph: MultiTrackSamplerGraph?
    @State private var rendered: RenderedMIDI?
    @State private var statusText: String = ""
    @State private var loadError: String?
    @State private var tempo: Float = 1.0
    @State private var loadedSlot: SoundFontAuditionView.Slot?
    @State private var selectedSong: BundledSong?
    @State private var isLoadingSong = false

    var body: some View {
        Section("Song") {
            Picker("Song", selection: $selectedSong) {
                Text("— pick a song —").tag(BundledSong?.none)
                ForEach(BundledSong.all) { song in
                    Text(song.displayName).tag(BundledSong?.some(song))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Audition song")
            .disabled(isLoadingSong || (bankA == nil && bankB == nil))
            .onChange(of: selectedSong) { _, newValue in
                guard let newValue else { return }
                Task { await loadSong(newValue) }
            }
        }
        Section("Pipeline") {
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
            if graph != nil {
                tempoControl
                transportControls
            }
        }
        .onChange(of: activeSlot) { oldValue, newValue in
            // Diagnostic: confirm the parent's top A/B selector is propagating.
            PipelineFileLog.shared.log(
                "AuditionPipelineSection.onChange(activeSlot): \(oldValue.rawValue) → \(newValue.rawValue)"
            )
            Task { await applyActiveBank(newValue) }
        }
        // In a Form, a Section's .onDisappear fires on scroll-out as well as
        // navigation-away. Don't tear down the engine here; just log.
        .onDisappear {
            PipelineFileLog.shared.log(
                "AuditionPipelineSection.onDisappear (scroll OR navigate; engine NOT torn down)"
            )
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
            .onChange(of: tempo) { _, newValue in
                graph?.setTempoScale(newValue)
                PipelineFileLog.shared.log(
                    "setTempo: rate=\(String(format: "%.2f", newValue))"
                )
            }
        }
    }

    private var transportControls: some View {
        // CRITICAL: every Button needs `.buttonStyle(.borderless)` (Form-row
        // gesture-sharing fix from prior QA).
        HStack(spacing: 16) {
            Button {
                do {
                    try graph?.play()
                } catch {
                    loadError = error.localizedDescription
                }
            } label: { Label("Play", systemImage: "play.fill") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Play pipeline")
                .disabled(graph == nil || isLoadingSong)
            Button {
                graph?.pause()
            } label: { Label("Pause", systemImage: "pause.fill") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Pause pipeline")
                .disabled(graph == nil || isLoadingSong)
            Button {
                graph?.stop()
            } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Stop pipeline and reset")
                .disabled(graph == nil || isLoadingSong)
        }
    }

    // MARK: - Lifecycle

    /// Starts the shared AVAudioEngine for song loading.
    ///
    /// Calls `AudioEngineManager.shared.startForPlayback()` to configure the
    /// manager mode, then explicitly restarts the underlying engine when it is
    /// paused. `startForPlayback` short-circuits when the manager is already in
    /// `playbackOnly` mode, so the engine must be restarted directly after
    /// `unloadCurrentSong` pauses it for the clean graph-swap.
    ///
    /// - Throws: Any error from `AudioEngineManager.startForPlayback()` or
    ///   `AVAudioEngine.start()`.
    private func startEngineForLoad() throws {
        try AudioEngineManager.shared.startForPlayback()
        sectionLogger.info("loadSong: engine started for playback")
        PipelineFileLog.shared.log("loadSong: engine startForPlayback OK")
        // If unloadCurrentSong paused the engine, restart it now so the
        // new MultiTrackSamplerGraph's isRunning guard passes and its
        // attach/connect calls run against a freshly-started engine.
        let engine = AudioEngineManager.shared.engine
        if !engine.isRunning {
            try engine.start()
            PipelineFileLog.shared.log("loadSong: engine restarted post-pause")
        }
    }

    private func loadSong(_ song: BundledSong) async {
        guard !isLoadingSong else {
            PipelineFileLog.shared.log("loadSong SKIP: already loading another song")
            return
        }
        // Need at least one bank loaded.
        guard bankA != nil || bankB != nil else {
            loadError = "Load a SF2 bank first"
            PipelineFileLog.shared.log(
                "loadSong SKIP id=\(song.id): no SF2 bank loaded"
            )
            return
        }

        isLoadingSong = true
        defer { isLoadingSong = false }

        // Tear down any previous song before loading the new one.
        await unloadCurrentSong()

        // Append a session marker (don't truncate) so multiple song-cycles
        // in one app run all land in the same log — needed to diagnose
        // mid-playback song-switch behavior.
        PipelineFileLog.shared.start(truncate: false)
        let startTime = Date()
        PipelineFileLog.shared.log(
            "=== loadSong START id=\(song.id) activeSlot=\(activeSlot.rawValue) ==="
        )
        statusText = "Loading \(song.displayName)…"
        loadError = nil

        do {
            try startEngineForLoad()

            guard let mxlURL = Bundle.main.url(
                forResource: song.id, withExtension: "mxl"
            ) else {
                throw PipelineError.resourceMissing(name: "\(song.id).mxl")
            }
            let mxlData = try Data(contentsOf: mxlURL)
            PipelineFileLog.shared.log(
                "loadSong: mxl loaded \(mxlData.count)B id=\(song.id)"
            )
            let xml = try MXLLoader.loadMusicXML(from: mxlData)
            PipelineFileLog.shared.log(
                "loadSong: MusicXML extracted \(xml.utf8.count)B id=\(song.id)"
            )

            let renderStart = Date()
            let bridge = VerovioBridge()
            let renderedMIDI = try bridge.render(musicXML: xml)
            let renderElapsed = Date().timeIntervalSince(renderStart)
            PipelineFileLog.shared.log(
                "VerovioBridge.render: elapsed=\(String(format: "%.2f", renderElapsed))s"
            )
            self.rendered = renderedMIDI

            let partCount = min(
                renderedMIDI.trackInfo.count, MultiTrackSamplerGraph.maxTracks
            )
            let g = try MultiTrackSamplerGraph(trackCount: partCount)

            // Pick the SF2 to load. Active slot wins; fall back to whichever
            // bank URL is non-nil if the active slot is empty.
            let activeURL: URL? = (activeSlot == .a) ? bankA : bankB
            let resolvedURL: URL?
            let resolvedSlot: SoundFontAuditionView.Slot
            if let activeURL {
                resolvedURL = activeURL
                resolvedSlot = activeSlot
            } else if let bankA {
                resolvedURL = bankA
                resolvedSlot = .a
            } else if let bankB {
                resolvedURL = bankB
                resolvedSlot = .b
            } else {
                resolvedURL = nil
                resolvedSlot = activeSlot
            }
            guard let bankURL = resolvedURL else {
                throw PipelineError.resourceMissing(name: "active SF2 bank")
            }
            let presets = derivedPresets(samplerCount: partCount)
            let presetList = presets.map { String($0) }.joined(separator: ",")
            try g.loadBank(at: bankURL, presets: presets)
            loadedSlot = resolvedSlot
            PipelineFileLog.shared.log(
                "applyActiveBank(\(resolvedSlot.rawValue)) → \(bankURL.lastPathComponent) presets=[\(presetList)]"
            )

            try g.loadMIDI(renderedMIDI)
            self.graph = g

            let totalElapsed = Date().timeIntervalSince(startTime)
            let chList = renderedMIDI.channels.map { String($0) }.joined(separator: ", ")
            statusText = "✓ \(song.displayName) · \(partCount) parts · channels [\(chList)]"
            PipelineFileLog.shared.log(
                "=== loadSong DONE id=\(song.id) parts=\(partCount) elapsed=\(String(format: "%.2f", totalElapsed))s ==="
            )
        } catch let pipelineError as PipelineError {
            loadError = pipelineError.localizedDescription
            statusText = ""
            PipelineFileLog.shared.log(
                "loadSong FAILED id=\(song.id) reason=\(pipelineError.localizedDescription)"
            )
        } catch {
            loadError = "Pipeline failed: \(error.localizedDescription)"
            statusText = ""
            PipelineFileLog.shared.log(
                "loadSong FAILED (other) id=\(song.id) reason=\(error.localizedDescription)"
            )
        }
    }

    private func unloadCurrentSong() async {
        let prevId = selectedSong?.id ?? "nil"
        let wasPlaying = graph?.isPlaying ?? false
        let hadGraph = graph != nil
        PipelineFileLog.shared.log(
            "unloadCurrentSong: previous=\(prevId) graph=\(hadGraph ? "present" : "nil") wasPlaying=\(wasPlaying)"
        )
        graph?.stop()
        graph?.teardown()
        graph = nil
        rendered = nil
        loadedSlot = nil
        statusText = ""
        // Stop the engine (not just pause) so AU instances release their
        // hardware/kernel resources before the next graph attaches. pause()
        // preserves AU state, which let CoreAudio kernel residue from the
        // prior song carry over and degrade the next song's audio quality
        // even after explicit Stop between songs. stop() forces AUs to
        // reinitialize on the next engine.start(), giving the new graph
        // a clean kernel state. loadSong's startForPlayback short-circuits
        // when the manager mode is already playbackOnly, so it explicitly
        // calls engine.start() to bring the engine back up before init.
        if hadGraph {
            let engine = AudioEngineManager.shared.engine
            if engine.isRunning {
                engine.stop()
                PipelineFileLog.shared.log("unloadCurrentSong: engine stopped for clean swap")
            }
        }
    }

    private func applyActiveBank(_ slot: SoundFontAuditionView.Slot) async {
        let graphStr = graph == nil ? "nil" : "present"
        let loadedStr = loadedSlot?.rawValue ?? "nil"
        PipelineFileLog.shared.log(
            """
            applyActiveBank(\(slot.rawValue)) ENTRY: \
            graph=\(graphStr) isLoadingSong=\(isLoadingSong) loadedSlot=\(loadedStr)
            """
        )
        guard let g = graph else {
            PipelineFileLog.shared.log(
                "applyActiveBank(\(slot.rawValue)) BAIL: graph=nil"
            )
            return
        }
        // Don't run mid-load (loadSong itself sets up the bank).
        guard !isLoadingSong else {
            PipelineFileLog.shared.log(
                "applyActiveBank(\(slot.rawValue)) DEFERRED (loading song)"
            )
            return
        }
        let url: URL? = (slot == .a) ? bankA : bankB
        guard let url else {
            PipelineFileLog.shared.log(
                "applyActiveBank(\(slot.rawValue)) ABORT: no URL for slot"
            )
            return
        }
        let presets = derivedPresets(samplerCount: g.samplers.count)
        let presetList = presets.map { String($0) }.joined(separator: ",")
        PipelineFileLog.shared.log(
            "applyActiveBank(\(slot.rawValue)) → \(url.lastPathComponent) presets=[\(presetList)]"
        )
        do {
            try g.loadBank(at: url, presets: presets)
            loadedSlot = slot
            PipelineFileLog.shared.log("applyActiveBank(\(slot.rawValue)) DONE")
        } catch {
            loadError = "Bank load failed: \(error.localizedDescription)"
            PipelineFileLog.shared.log(
                "applyActiveBank(\(slot.rawValue)) FAILED: \(error.localizedDescription)"
            )
        }
    }

    /// Derive per-sampler GM presets from `rendered.trackInfo`. Falls back
    /// to GM 0 (Acoustic Grand) if a track had no Program Change.
    private func derivedPresets(samplerCount: Int) -> [UInt8] {
        let trackInfo = rendered?.trackInfo ?? []
        var result: [UInt8] = []
        for index in 0..<samplerCount {
            if index < trackInfo.count, let program = trackInfo[index].program {
                result.append(program)
            } else {
                result.append(0)
            }
        }
        return result
    }
}
#endif
