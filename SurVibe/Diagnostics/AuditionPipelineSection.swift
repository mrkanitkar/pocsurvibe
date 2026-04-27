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

    /// Fix C2 (review 2026-04-26): if the user toggles A/B during a bounce we
    /// skip the immediate `loadBank` (which would pause the engine and corrupt
    /// the m4a) and stash the requested slot here. The `bounce()` defer block
    /// flushes the pending slot once the capture completes.
    @State private var deferredSlot: SoundFontAuditionView.Slot?

    /// Tracks which slot was actually loaded into the samplers, so the
    /// deferred-flush can decide whether a re-apply is needed.
    @State private var loadedSlot: SoundFontAuditionView.Slot?

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
        // Fix I4 (review 2026-04-26): tear down the pipeline when the parent
        // view disappears. Without this the samplers stay attached to the
        // shared engine indefinitely after the user navigates away, and any
        // in-flight bounce keeps writing to disk in the background.
        .onDisappear {
            disablePipeline()
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
        HStack(spacing: 16) {
            Button {
                do { try graph?.play() } catch { loadError = error.localizedDescription }
            } label: { Label("Play", systemImage: "play.fill") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Play pipeline")
                .disabled(graph?.sequencer == nil)
            Button {
                graph?.pause()
            } label: { Label("Pause", systemImage: "pause.fill") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Pause pipeline")
            Button {
                graph?.stop()
            } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Stop pipeline and reset")
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
            let mxlSize = mxlData.count
            sectionLogger.info("enablePipeline: mxl loaded, \(mxlSize, privacy: .public) bytes")
            PipelineFileLog.shared.log("AuditionPipelineSection.enablePipeline: mxl loaded \(mxlSize)B")
            let xml = try MXLLoader.loadMusicXML(from: mxlData)
            let xmlSize = xml.utf8.count
            sectionLogger.info("enablePipeline: MusicXML extracted, \(xmlSize, privacy: .public) bytes")
            PipelineFileLog.shared.log("AuditionPipelineSection.enablePipeline: MusicXML extracted \(xmlSize)B")
            let bridge = VerovioBridge()
            let renderedMIDI = try bridge.render(musicXML: xml)
            self.rendered = renderedMIDI

            // Fix C1 (review 2026-04-26): VerovioBridge.summarize counts every
            // MTrk chunk in the SMF, including the conductor track 0
            // (tempo/time-sig metadata, no notes) that Verovio emits as a Type
            // 1 SMF. AVAudioSequencer.tracks excludes the conductor track
            // (Apple exposes it separately as `tempoTrack`), so probing a
            // throwaway sequencer gives us the true AVF-visible part count.
            // Sizing the graph off `renderedMIDI.trackCount` instead would
            // create one extra (silent) sampler at index 0 and shift every
            // subsequent part by one. Chose the temporary-sequencer probe over
            // adding a `partCount` field to RenderedMIDI to keep the SVAudio
            // type pure (no AVFoundation timing coupling).
            let probeSeq = AVAudioSequencer(audioEngine: AudioEngineManager.shared.engine)
            try probeSeq.load(from: renderedMIDI.data, options: [])
            let partCount = min(probeSeq.tracks.count, MultiTrackSamplerGraph.maxTracks)

            let g = try MultiTrackSamplerGraph(trackCount: partCount)
            self.graph = g

            // Bug 2 fix (2026-04-27): load SF2 BEFORE MIDI routing. AudioKit's
            // MIDISampler may not have a live CoreMIDI virtual destination until
            // the underlying AVAudioUnitSampler has loaded a SoundFont program.
            // If we set track.destinationMIDIEndpoint = samplers[i].midiIn before
            // the SF2 is loaded, the route silently binds to a stale endpoint and
            // MIDI events never reach the sampler — playback is silent. Load the
            // SF2 first, then route.
            PipelineFileLog.shared.log("AuditionPipelineSection.enablePipeline: graph created partCount=\(partCount)")
            await applyActiveBank(activeSlot)

            // Now route (CoreMIDI endpoints are live because samplers have programs loaded).
            try g.loadMIDI(renderedMIDI)

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
        // disables the pipeline (or navigates away), abort it so the tap is
        // removed from the sub-mixer before we tear that node down. Resetting
        // `isBouncing` here unblocks the `bounce()` task body, which observes
        // `g == nil` and short-circuits.
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
        guard let g = graph else { return }
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

    /// Derive per-sampler GM preset numbers from the rendered MIDI's
    /// per-track Program Change events. Falls back to the static
    /// `defaultPresets` table for tracks Verovio didn't write a program
    /// change on (or where the track is percussion — channel 9 is
    /// special-cased to GM "Standard Drum Kit" preset 0 here, since
    /// `loadMelodicSoundFont` cannot address the percussion bank).
    ///
    /// **Caveat:** percussion played through a melodic preset 0 still
    /// sounds wrong (it pitches drums by note number). Proper percussion
    /// requires `loadSoundBankInstrument` with bankMSB=128, which is a
    /// follow-up; flagged in the deferred items.
    private func derivedPresets(samplerCount: Int) -> [UInt8] {
        let trackInfo = rendered?.trackInfo ?? []
        var result: [UInt8] = []
        for i in 0..<samplerCount {
            if i < trackInfo.count, let program = trackInfo[i].program {
                result.append(program)
            } else {
                result.append(Self.defaultPresets[i])
            }
        }
        return result
    }

    private func bounce(slot: SoundFontAuditionView.Slot) async {
        guard let g = graph else { return }

        // Bug fix (2026-04-27): Bounce A/B button labels imply slot-specific
        // capture, but the previous implementation only used `slot` for the
        // output filename — both bounces actually used whichever SF2 was
        // currently loaded. Confirmed by pipeline_log: A and B m4a files
        // captured the same audio because no loadBank ran between them.
        // Fix: explicitly load the requested slot's bank before bouncing.
        if loadedSlot != slot {
            let url: URL? = (slot == .a) ? bankA : bankB
            if let url {
                let presets = derivedPresets(samplerCount: g.samplers.count)
                let presetList = presets.map { String($0) }.joined(separator: ",")
                PipelineFileLog.shared.log(
                    "bounce[\(slot.rawValue)]: pre-load bank \(url.lastPathComponent) presets=[\(presetList)]"
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
        // currently loaded. Re-applying the same slot would needlessly pause
        // the engine again.
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
            // Wait until the sequencer reports it's no longer playing.
            // Diagnostic: log every second so we can see if/when the
            // sequencer goes inactive prematurely.
            var ticks = 0
            while g.isPlaying {
                try await Task.sleep(nanoseconds: 200_000_000)
                ticks += 1
                if ticks % 5 == 0 {  // every ~1s
                    let pos = g.sequencer?.currentPositionInSeconds ?? -1
                    sectionLogger.info(
                        "bounce[\(slot.rawValue, privacy: .public)] still playing pos=\(pos, privacy: .public)s"
                    )
                }
            }
            let endPos = g.sequencer?.currentPositionInSeconds ?? -1
            sectionLogger.info(
                """
                bounce[\(slot.rawValue, privacy: .public)] sequencer done \
                pos=\(endPos, privacy: .public)s ticks=\(ticks, privacy: .public)
                """
            )
            PipelineFileLog.shared.log(
                "bounce[\(slot.rawValue)] sequencer done pos=\(endPos)s ticks=\(ticks)"
            )
            // Fix I5 (review 2026-04-26): AVAudioUnitTimePitch carries
            // ~50–100 ms of overlap-add buffering and SF2 voices can have
            // release/reverb tails that are still rendering when the
            // sequencer flips `isPlaying` to false. Without this pause the
            // m4a ends abruptly mid-decay. 300 ms is generous for both the
            // TimePitch latency and a typical SF2 release tail.
            try? await Task.sleep(nanoseconds: 300_000_000)
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
