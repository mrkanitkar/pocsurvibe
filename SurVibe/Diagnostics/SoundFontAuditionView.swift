#if DEBUG
import AudioKit
import AVFoundation
import AudioToolbox
import SVAudio
import SwiftUI

/// On-device A/B audition tool for comparing two SoundFont banks side-by-side
/// through the multi-channel `MultiTrackSamplerGraph` pipeline.
///
/// Loads two user-selected `.sf2` files into `AuditionPipelineSection` and
/// routes them through the shared `AudioEngineManager.shared.engine`.
/// The Active segmented control delegates bank-switching to the pipeline
/// section's own `onChange(of: activeSlot)` handler.
///
/// What it produces is exactly what students will hear in the production
/// playback path: same AU, same engine, same audio session.
///
/// ## Usage
///
/// 1. Slot A auto-loads with the production bank `MuseScore_General.sf2`
///    (SVAudio package resource).
/// 2. Slot B auto-loads with the diagnostics-only `GeneralUser-GS.sf2`
///    (DEBUG-bundled in `Diagnostics/AuditionAssets/`). Either slot can
///    be overridden by tapping the slot row to pick any `.sf2` from
///    the Files app.
/// 3. Toggle A ↔ B to compare timbres through the multi-channel pipeline.
struct SoundFontAuditionView: View {

    // MARK: - Types

    /// One of the two A/B audition slots.
    enum Slot: String, CaseIterable, Identifiable {
        case a = "A"
        case b = "B"
        var id: String { rawValue }
    }

    // MARK: - State

    /// URL for bank A, retained so `AuditionPipelineSection` can re-bank on slot switch.
    @State private var urlA: URL?
    /// URL for bank B, retained so `AuditionPipelineSection` can re-bank on slot switch.
    @State private var urlB: URL?
    @State private var fileNameA: String?
    @State private var fileNameB: String?
    @State private var loadErrorA: String?
    @State private var loadErrorB: String?
    /// Which slot is currently active. Passed to `AuditionPipelineSection`;
    /// the pipeline section's own `onChange(of: activeSlot)` drives the re-bank.
    @State private var activeSlot: Slot = .a
    /// The slot whose file-picker sheet is currently open.
    @State private var pickerSlot: Slot?
    @State private var isFileImporterPresented = false

    // MARK: - Body

    var body: some View {
        Form {
            Section("Bank A") {
                slotRow(for: .a, fileName: fileNameA, error: loadErrorA)
            }
            Section("Bank B") {
                slotRow(for: .b, fileName: fileNameB, error: loadErrorB)
            }
            Section("Active") {
                Picker("Active bank", selection: $activeSlot) {
                    ForEach(Slot.allCases) { slot in
                        Text(slot.rawValue).tag(slot)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Active sampler bank")
            }
            AuditionPipelineSection(
                bankA: urlA,
                bankB: urlB,
                activeSlot: activeSlot
            )
        }
        .navigationTitle("SoundFont A/B Audition")
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.init(filenameExtension: "sf2") ?? .data]
        ) { result in
            handleFileImport(result)
        }
        .task {
            await ensureEngineRunning()
            autoLoadBundledBanksIfPresent()
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func slotRow(for slot: Slot, fileName: String?, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                pickerSlot = slot
                isFileImporterPresented = true
            } label: {
                Label(
                    fileName ?? "Pick .sf2 for slot \(slot.rawValue)",
                    systemImage: fileName != nil ? "checkmark.circle.fill" : "doc.badge.plus"
                )
            }
            .accessibilityLabel("Pick SoundFont for slot \(slot.rawValue)")
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Load error for slot \(slot.rawValue): \(error)")
            }
        }
    }

    // MARK: - Engine Setup

    /// Ensure the shared production engine is running before the pipeline
    /// section attaches its multi-channel sampler graph. Reuses
    /// `AudioEngineManager`'s engine to honor the project-wide single-engine
    /// rule (see `.claude/rules/audio.md`).
    private func ensureEngineRunning() async {
        do {
            try AudioEngineManager.shared.startForPlayback()
        } catch {
            loadErrorA = "Engine start failed: \(error.localizedDescription)"
        }
    }

    // MARK: - File Loading

    /// Auto-load the two bundled audition banks into the A/B slots.
    ///
    /// Slot A receives the production bank `MuseScore_General.sf2` from
    /// the SVAudio package (`Bundle.module`). Slot B receives the
    /// diagnostics-only `GeneralUser-GS.sf2` from the main app bundle —
    /// shipped in DEBUG builds only via `Diagnostics/AuditionAssets/`,
    /// excluded from Release. Slot B is the historical reference bank
    /// for A/B comparison; production playback never resolves to it.
    /// Manual file picks (slot row buttons) override these defaults.
    private func autoLoadBundledBanksIfPresent() {
        if fileNameA == nil,
           let url = MultiTrackSamplerGraph.bundledMuseScoreGeneralSF2URL {
            loadSoundFont(at: url, into: .a)
        }
        if fileNameB == nil,
           let url = MultiTrackSamplerGraph.bundledGeneralUserGSSF2URL {
            loadSoundFont(at: url, into: .b)
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard let slot = pickerSlot else { return }
        defer { pickerSlot = nil }
        switch result {
        case .success(let url):
            loadSoundFont(at: url, into: slot)
        case .failure(let error):
            switch slot {
            case .a: loadErrorA = error.localizedDescription
            case .b: loadErrorB = error.localizedDescription
            }
        }
    }

    /// Load an SF2 into the given slot. Stores the URL and filename for the
    /// slot so `AuditionPipelineSection` can pick it up via the `bankA`/`bankB`
    /// bindings. The pipeline section's own `onChange(of: activeSlot)` drives
    /// the actual bank load into the multi-channel sampler graph.
    private func loadSoundFont(at url: URL, into slot: Slot) {
        switch slot {
        case .a:
            fileNameA = url.lastPathComponent
            urlA = url
            loadErrorA = nil
        case .b:
            fileNameB = url.lastPathComponent
            urlB = url
            loadErrorB = nil
        }
    }
}

#Preview {
    NavigationStack {
        SoundFontAuditionView()
    }
}

#endif
