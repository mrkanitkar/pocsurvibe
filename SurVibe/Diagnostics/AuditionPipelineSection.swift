#if DEBUG
import AVFoundation
import AudioKit
import SVAudio
import SwiftUI
import os

private let sectionLogger = Logger(
    subsystem: "com.survibe", category: "AuditionPipelineSection"
)

/// DEBUG-only section embedded inside `SoundFontAuditionView`.
/// Owns the multi-channel pipeline lifecycle (graph + bouncer) and renders
/// the toggle, status, tempo slider, transport, and bounce UI.
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

    /// Fix C2 (review 2026-04-26): if the user toggles A/B during a bounce we
    /// skip the immediate `loadBank` (which would pause the engine and corrupt
    /// the m4a) and stash the requested slot here. The `bounce()` defer block
    /// flushes the pending slot once the capture completes.
    @State private var deferredSlot: SoundFontAuditionView.Slot?

    /// Tracks which slot was actually loaded into the samplers, so the
    /// deferred-flush can decide whether a re-apply is needed.
    @State private var loadedSlot: SoundFontAuditionView.Slot?

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
        .onChange(of: activeSlot) { oldValue, newValue in
            // Diagnostic 2026-04-28: confirm the parent's top A/B selector is
            // actually propagating into this child's view tree. Logs here
            // unconditionally so even guarded-out applyActiveBank calls show
            // the trigger fired.
            PipelineFileLog.shared.log(
                "AuditionPipelineSection.onChange(activeSlot): \(oldValue.rawValue) → \(newValue.rawValue)"
            )
            Task { await applyActiveBank(newValue) }
        }
        // Bug 2026-04-28 (diagnostic-confirmed): in a Form, a Section's
        // `.onDisappear` fires when the section scrolls OUT of the visible
        // viewport — not only on real navigation-away. The previous
        // implementation called `disablePipeline()` here per Fix I4 (cleanup
        // on navigate-away), but that caused the engine to be torn down
        // every time the user scrolled up to the top "Active" selector, so
        // taps on that selector then bailed with `graph=nil`.
        //
        // Trade-off accepted: do NOT tear down the engine here. Samplers
        // stay attached to the shared `AVAudioEngine` until the user
        // toggles the pipeline OFF. For a DEBUG-only POC this is acceptable
        // (a few MB of sampler state per session). The original Fix I4
        // concern about an in-flight bounce continuing on navigate-away is
        // now mitigated by the deterministic-duration bounce (commit
        // 1f0d21e) which finalises cleanly within `sequenceDuration`s
        // anyway. We still abort an in-flight bouncer here as a belt-and-
        // braces safeguard.
        .onDisappear {
            PipelineFileLog.shared.log(
                "AuditionPipelineSection.onDisappear (scroll OR navigate; engine NOT torn down)"
            )
            if isBouncing { bouncer?.abort() }
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
        // CRITICAL: every Button needs `.buttonStyle(.borderless)`. Without
        // it, multiple Buttons inside the same Form-row HStack share the
        // row's tap gesture — tapping any one fires ALL of them. Confirmed
        // by pipeline_log.txt 2026-04-27: every Play tap was followed by
        // pause+stop within the same millisecond.
        // QA finding 2026-04-28: tapping Stop/Play during a bounce
        // contaminated the m4a (5–6 s of music + silence + restart artifacts).
        // The bouncer is independent of the sequencer, so transport taps
        // mid-bounce keep capturing whatever (or no) audio comes out. Lock
        // out transport while bouncing so the user can't accidentally
        // sabotage their own capture.
        HStack(spacing: 16) {
            Button {
                do { try graph?.play() } catch { loadError = error.localizedDescription }
            } label: { Label("Play", systemImage: "play.fill") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Play pipeline")
                .disabled(graph == nil || isBouncing)
            Button {
                graph?.pause()
            } label: { Label("Pause", systemImage: "pause.fill") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Pause pipeline")
                .disabled(graph == nil || isBouncing)
            Button {
                graph?.stop()
            } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Stop pipeline and reset")
                .disabled(graph == nil || isBouncing)
        }
    }

    private var bounceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Same .buttonStyle(.borderless) requirement as transportControls
            // — without it, both Bounce buttons fire on a single tap.
            HStack(spacing: 16) {
                Button {
                    Task { await bounce(slot: .a) }
                } label: { Label("Bounce A → m4a", systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Bounce bank A to m4a file")
                    .disabled(isBouncing || bankA == nil)
                Button {
                    Task { await bounce(slot: .b) }
                } label: { Label("Bounce B → m4a", systemImage: "arrow.down.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Bounce bank B to m4a file")
                    .disabled(isBouncing || bankB == nil)
            }
            if let bounceURLA {
                bounceResultRow(label: bounceURLA.lastPathComponent, url: bounceURLA)
            }
            if let bounceURLB {
                bounceResultRow(label: bounceURLB.lastPathComponent, url: bounceURLB)
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
        PipelineFileLog.shared.start()  // truncate + open log file
        PipelineFileLog.shared.log("=== enablePipeline START ===")
        statusText = "Loading bond.mxl..."
        loadError = nil
        do {
            try AudioEngineManager.shared.startForPlayback()
            sectionLogger.info("enablePipeline: engine started for playback")
            PipelineFileLog.shared.log("AuditionPipelineSection.enablePipeline: engine startForPlayback OK")

            guard let mxlURL = Bundle.main.url(
                forResource: "james-bond-theme", withExtension: "mxl"
            ) else {
                PipelineFileLog.shared.log("ERROR: james-bond-theme.mxl missing from bundle")
                throw PipelineError.resourceMissing(name: "james-bond-theme.mxl")
            }
            let mxlData = try Data(contentsOf: mxlURL)
            let xml = try MXLLoader.loadMusicXML(from: mxlData)
            let bridge = VerovioBridge()
            let renderedMIDI = try bridge.render(musicXML: xml)
            self.rendered = renderedMIDI

            // QA finding 2026-04-28: a probe AVAudioSequencer attached to
            // the SHARED AVAudioEngine to count tracks caused the graph's
            // own sequencer to silently produce only ~95 KB / 2.25 Kbps of
            // audio (versus the expected 1.9 MB / 119 Kbps). Two sequencers
            // on the same engine compete for MIDI dispatch in a way that
            // silently breaks routing. Use `rendered.trackInfo.count`
            // directly — Verovio's music-only count excludes the conductor
            // track, matching the prior working AppleAVSamplerEngine path.
            let partCount = min(renderedMIDI.trackInfo.count, MultiTrackSamplerGraph.maxTracks)

            let g = try MultiTrackSamplerGraph(trackCount: partCount)
            // Load SF2 BEFORE setting self.graph or routing MIDI (Bug-2
            // ordering: AudioKit's MIDISampler may not have a live CoreMIDI
            // virtual destination until the underlying AVAudioUnitSampler
            // has loaded a SoundFont program).
            let activeURL: URL? = (activeSlot == .a) ? bankA : bankB
            if let activeURL {
                let presets = derivedPresets(samplerCount: partCount)
                try g.loadBank(at: activeURL, presets: presets)
                loadedSlot = activeSlot
                let presetList = presets.map { String($0) }.joined(separator: ",")
                PipelineFileLog.shared.log(
                    "applyActiveBank(\(activeSlot.rawValue)) → \(activeURL.lastPathComponent) presets=[\(presetList)]"
                )
            }
            try g.loadMIDI(renderedMIDI)
            self.graph = g

            let chList = renderedMIDI.channels.map { String($0) }.joined(separator: ", ")
            statusText = "✓ \(partCount) parts · channels [\(chList)]"
            PipelineFileLog.shared.log("=== enablePipeline DONE — \(partCount) parts ready ===")
        } catch let pipelineError as PipelineError {
            loadError = pipelineError.localizedDescription
            PipelineFileLog.shared.log("enablePipeline FAILED: \(pipelineError.localizedDescription)")
            disablePipeline()
        } catch {
            loadError = "Pipeline failed: \(error.localizedDescription)"
            PipelineFileLog.shared.log("enablePipeline FAILED (other): \(error.localizedDescription)")
            disablePipeline()
        }
    }

    private func disablePipeline() {
        // Fix I4 (review 2026-04-26): if a bounce is mid-flight when the user
        // disables the pipeline, abort it so the tap is removed from the
        // sub-mixer before we tear that node down. Resetting `isBouncing`
        // here unblocks the `bounce()` task body, which observes
        // `graph == nil` and short-circuits.
        if isBouncing {
            bouncer?.abort()
        }
        bouncer = nil
        isBouncing = false
        deferredSlot = nil
        loadedSlot = nil
        graph?.stop()
        graph?.teardown()
        graph = nil
        rendered = nil
        statusText = ""
    }

    private func applyActiveBank(_ slot: SoundFontAuditionView.Slot) async {
        // Diagnostic 2026-04-28: log entry unconditionally so we can see
        // both the call and the reason for any silent bail-out.
        let engineStr = graph == nil ? "nil" : "present"
        let loadedStr = loadedSlot?.rawValue ?? "nil"
        PipelineFileLog.shared.log(
            """
            applyActiveBank(\(slot.rawValue)) ENTRY: \
            graph=\(engineStr) isBouncing=\(isBouncing) loadedSlot=\(loadedStr)
            """
        )
        guard let g = graph else {
            PipelineFileLog.shared.log("applyActiveBank(\(slot.rawValue)) BAIL: graph=nil")
            return
        }
        // Fix C2 (review 2026-04-26): a bank swap pauses the engine for
        // ~N×300 ms (Mode 2 sequential reload) — running this mid-bounce
        // silences the tap and leaves the m4a write head out of position,
        // producing a corrupt file. Defer the slot and surface a transient
        // status so the user sees why the swap didn't take immediately; the
        // bounce()'s defer block flushes the pending slot once it ends.
        guard !isBouncing else {
            deferredSlot = slot
            loadError = "Bank swap deferred until bounce completes"
            PipelineFileLog.shared.log("applyActiveBank(\(slot.rawValue)) DEFERRED (bouncing)")
            return
        }
        let url: URL? = (slot == .a) ? bankA : bankB
        guard let url else {
            PipelineFileLog.shared.log("applyActiveBank(\(slot.rawValue)) ABORT: no URL for slot")
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
            if loadError == "Bank swap deferred until bounce completes" {
                loadError = nil
            }
        } catch {
            loadError = "Bank load failed: \(error.localizedDescription)"
            PipelineFileLog.shared.log("applyActiveBank(\(slot.rawValue)) FAILED: \(error.localizedDescription)")
        }
    }

    /// Derive per-sampler GM presets from `rendered.trackInfo`. Falls back
    /// to GM 0 (Acoustic Grand Piano) if a track had no Program Change.
    private func derivedPresets(samplerCount: Int) -> [UInt8] {
        let trackInfo = rendered?.trackInfo ?? []
        var result: [UInt8] = []
        for i in 0..<samplerCount {
            if i < trackInfo.count, let program = trackInfo[i].program {
                result.append(program)
            } else {
                result.append(0)
            }
        }
        return result
    }

    private func bounce(slot: SoundFontAuditionView.Slot) async {
        guard let g = graph else { return }

        // Bug fix (2026-04-27): Bounce A/B button labels imply slot-specific
        // capture, but the previous implementation only used `slot` for the
        // output filename — both bounces actually used whichever SF2 was
        // currently loaded. Fix: explicitly load the requested slot's bank
        // before bouncing.
        if loadedSlot != slot {
            let url: URL? = (slot == .a) ? bankA : bankB
            if let url {
                let presets = derivedPresets(samplerCount: g.samplers.count)
                let presetList = presets.map { String($0) }.joined(separator: ",")
                PipelineFileLog.shared.log(
                    "bounce[\(slot.rawValue)]: pre-load bank=\(url.lastPathComponent) presets=[\(presetList)]"
                )
                do {
                    try g.loadBank(at: url, presets: presets)
                    loadedSlot = slot
                } catch {
                    let msg = error.localizedDescription
                    loadError = "Bank load before bounce failed: \(msg)"
                    PipelineFileLog.shared.log("bounce[\(slot.rawValue)]: pre-load FAILED: \(msg)")
                    return
                }
            }
        }

        isBouncing = true
        // Fix C2 (review 2026-04-26): when the bounce ends — success, throw,
        // or task cancellation — flush any A/B slot the user requested while
        // the bounce was running, but only if it actually differs from what's
        // currently loaded.
        defer {
            isBouncing = false
            if let pending = deferredSlot {
                deferredSlot = nil
                if pending != loadedSlot {
                    Task { await applyActiveBank(pending) }
                }
            }
        }

        let filename = "audition_bond_\(slot.rawValue).m4a"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)

        let b = RealtimeTapBouncer(source: g.subMixer, outputURL: url)
        bouncer = b
        sectionLogger.info(
            "bounce[\(slot.rawValue, privacy: .public)] start → \(url.lastPathComponent, privacy: .public)"
        )
        do {
            g.stop()
            try b.start()
            try g.play()
            // QA finding 2026-04-27: AVAudioSequencer.isPlaying transitions to
            // false when events have been dispatched, not when audio finishes
            // rendering. Polling it truncated bounces to ~4–9 s on a 127 s
            // song. Wait the explicit sequence duration instead.
            let duration = sequenceDuration(for: g)
            // Code review C-2 (2026-04-27): a zero duration would silently
            // produce a near-empty m4a. Surface as an error instead.
            guard duration > 0 else {
                PipelineFileLog.shared.log("bounce[\(slot.rawValue)] ABORT: sequenceDuration=0")
                loadError = "Bounce aborted: sequence duration is zero"
                g.stop()
                b.abort()
                return
            }
            PipelineFileLog.shared.log(
                "bounce[\(slot.rawValue)] waiting duration=\(String(format: "%.2f", duration))s"
            )
            let deadline = Date().addingTimeInterval(duration)
            var ticks = 0
            while Date() < deadline {
                try await Task.sleep(nanoseconds: 200_000_000)
                ticks += 1
                if ticks % 25 == 0 {  // every ~5s
                    let remaining = max(0, deadline.timeIntervalSinceNow)
                    sectionLogger.info(
                        """
                        bounce[\(slot.rawValue, privacy: .public)] still playing \
                        ticks=\(ticks, privacy: .public) \
                        remaining=\(remaining, privacy: .public)s
                        """
                    )
                }
            }
            sectionLogger.info(
                "bounce[\(slot.rawValue, privacy: .public)] sequence elapsed ticks=\(ticks, privacy: .public)"
            )
            PipelineFileLog.shared.log(
                "bounce[\(slot.rawValue)] sequence elapsed ticks=\(ticks) duration=\(String(format: "%.2f", duration))s"
            )
            // Fix I5 (review 2026-04-26): drain TimePitch buffering + SF2
            // release tails before stopping the tap. 300 ms is generous for
            // both the TimePitch latency and a typical SF2 release tail.
            try? await Task.sleep(nanoseconds: 300_000_000)
            g.stop()
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

    /// Wall-clock duration of the loaded sequence (longest non-empty track).
    private func sequenceDuration(for graph: MultiTrackSamplerGraph) -> TimeInterval {
        guard let tracks = graph.sequencer?.tracks, !tracks.isEmpty else { return 0 }
        return tracks.map(\.lengthInSeconds).max() ?? 0
    }
}
#endif
