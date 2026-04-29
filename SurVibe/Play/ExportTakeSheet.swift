// SurVibe/Play/ExportTakeSheet.swift
import SVAudio
import SVCore
import SwiftUI
import os

/// Export sheet for a saved ``RecordedTake``.
///
/// Per Play tab v2 spec §4.8, the user picks any combination of MusicXML,
/// MXL, and SMF. Notation formats route through ``QuantizeSheet`` so the
/// quantizer has BPM / time-signature / grid context; SMF preserves the raw
/// timing via ``MIDISerializer.serializeType0`` and skips quantization.
///
/// Files are written to ``FileManager.temporaryDirectory`` and presented via
/// a system ``ShareLink`` once generation completes. The temp files are
/// cleaned up best-effort on dismiss.
///
/// The view is intentionally one screen deep — toggle the formats, hit
/// **Continue** (or **Export** if only SMF is selected), and SwiftUI presents
/// either the quantize sub-sheet or jumps straight to the share sheet.
struct ExportTakeSheet: View {
    let take: RecordedTake

    @Environment(\.dismiss) private var dismiss

    @State private var includeMusicXML: Bool = true
    @State private var includeMXL: Bool = false
    @State private var includeMIDI: Bool = true

    @State private var quantizeSheetPresented: Bool = false
    @State private var exportedFiles: [URL] = []
    @State private var exportError: String?
    @State private var isExporting: Bool = false

    private static let log = Logger.survibe(category: "ExportTakeSheet")

    private var atLeastOneFormatSelected: Bool {
        includeMusicXML || includeMXL || includeMIDI
    }

    private var needsQuantization: Bool {
        includeMusicXML || includeMXL
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("MusicXML (.musicxml)", isOn: $includeMusicXML)
                    Toggle("Compressed MusicXML (.mxl)", isOn: $includeMXL)
                    Toggle("Standard MIDI File (.mid)", isOn: $includeMIDI)
                } header: {
                    Text("Formats")
                } footer: {
                    Text("MusicXML and MXL require a tempo + time signature for notation. "
                         + "MIDI preserves your original timing.")
                }

                if let exportError {
                    Section {
                        Label(exportError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if !exportedFiles.isEmpty {
                    Section("Ready to share") {
                        ForEach(exportedFiles, id: \.self) { url in
                            HStack {
                                Image(systemName: "doc")
                                    .accessibilityHidden(true)
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .accessibilityLabel(url.lastPathComponent)
                        }
                        ShareLink(items: exportedFiles) {
                            Label("Share files", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share exported files")
                    }
                }
            }
            .navigationTitle("Export \"\(take.title)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(continueButtonTitle) {
                        startExport()
                    }
                    .disabled(!atLeastOneFormatSelected || isExporting)
                    .accessibilityLabel(continueButtonTitle)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $quantizeSheetPresented) {
                QuantizeSheet { bpm, timeSignature, grid in
                    Task { await runExport(bpm: bpm, timeSignature: timeSignature, grid: grid) }
                }
            }
            .onDisappear { cleanupExportedFiles() }
        }
        .presentationDetents([.medium, .large])
    }

    private var continueButtonTitle: String {
        needsQuantization ? "Continue" : "Export"
    }

    // MARK: - Export

    private func startExport() {
        // Reset prior output so re-running with different toggles doesn't
        // mix stale files into the share sheet.
        cleanupExportedFiles()
        exportError = nil
        if needsQuantization {
            quantizeSheetPresented = true
        } else {
            // SMF only — no quantization needed; serialise immediately.
            Task { await runExport(bpm: 60, timeSignature: .fourFour, grid: .sixteenth) }
        }
    }

    private func runExport(bpm: Int, timeSignature: TimeSignature, grid: QuantizeGrid) async {
        await MainActor.run { isExporting = true }
        defer { Task { @MainActor in isExporting = false } }

        let notes = take.loadNotes()
        let sustain = take.loadSustain()
        let stem = sanitisedFilename(from: take.title)
        let tmp = FileManager.default.temporaryDirectory
        var urls: [URL] = []

        if includeMIDI {
            do {
                urls.append(try writeMIDI(notes: notes, sustain: sustain, stem: stem, tmp: tmp))
            } catch {
                await MainActor.run { exportError = "Couldn't write MIDI file." }
                return
            }
        }

        if includeMusicXML || includeMXL {
            let settings = QuantizeSettings(bpm: bpm, timeSignature: timeSignature, grid: grid)
            let outcome = await writeNotation(
                notes: notes, sustain: sustain, stem: stem, tmp: tmp, settings: settings
            )
            if let message = outcome.errorMessage {
                await MainActor.run { exportError = message }
                return
            }
            urls.append(contentsOf: outcome.urls)
        }

        await MainActor.run { exportedFiles = urls }
    }

    private func writeMIDI(
        notes: [RecordedNote], sustain: [RecordedSustainEvent],
        stem: String, tmp: URL
    ) throws -> URL {
        let bytes = MIDISerializer.serializeType0(
            notes: notes, sustain: sustain, program: take.instrumentProgram
        )
        let url = tmp.appendingPathComponent("\(stem).mid")
        do {
            try bytes.write(to: url, options: .atomic)
            return url
        } catch {
            Self.log.error("MIDI write failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private struct QuantizeSettings {
        let bpm: Int
        let timeSignature: TimeSignature
        let grid: QuantizeGrid
    }

    private struct NotationOutcome {
        let urls: [URL]
        let errorMessage: String?

        static func success(_ urls: [URL]) -> NotationOutcome {
            NotationOutcome(urls: urls, errorMessage: nil)
        }

        static func failure(_ message: String) -> NotationOutcome {
            NotationOutcome(urls: [], errorMessage: message)
        }
    }

    private func writeNotation(
        notes: [RecordedNote], sustain: [RecordedSustainEvent],
        stem: String, tmp: URL, settings: QuantizeSettings
    ) async -> NotationOutcome {
        let result = Quantizer.quantize(
            notes: notes, sustain: sustain,
            bpm: settings.bpm, timeSignature: settings.timeSignature, grid: settings.grid
        )
        switch result {
        case .failure(let qerr):
            Self.log.error("Quantize failed: \(String(describing: qerr), privacy: .public)")
            return .failure("Couldn't quantize this take. Try a different tempo.")
        case .success(let score):
            let xml = MusicXMLSerializer.serialize(score: score)
            var urls: [URL] = []
            if includeMusicXML {
                let url = tmp.appendingPathComponent("\(stem).musicxml")
                do {
                    try Data(xml.utf8).write(to: url, options: .atomic)
                    urls.append(url)
                } catch {
                    Self.log.error("MusicXML write failed: \(error.localizedDescription, privacy: .public)")
                    return .failure("Couldn't write MusicXML file.")
                }
            }
            if includeMXL {
                do {
                    let mxl = try MXLPackager.package(musicXML: xml)
                    let url = tmp.appendingPathComponent("\(stem).mxl")
                    try mxl.write(to: url, options: .atomic)
                    urls.append(url)
                } catch {
                    Self.log.error("MXL packaging failed: \(error.localizedDescription, privacy: .public)")
                    return .failure("Couldn't package MXL archive.")
                }
            }
            return .success(urls)
        }
    }

    // MARK: - Helpers

    /// Returns a filesystem-safe version of `title` suitable for a temp file
    /// stem. Spaces become underscores; non-alphanumeric / non-dash / non-dot
    /// characters are stripped. Empty results fall back to "take".
    private func sanitisedFilename(from title: String) -> String {
        let collapsed = title.replacingOccurrences(of: " ", with: "_")
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")
        let filtered = String(collapsed.filter { allowed.contains($0) })
        return filtered.isEmpty ? "take" : filtered
    }

    /// Removes any temp files this sheet wrote on its way out so we don't
    /// litter the temp directory between sessions.
    private func cleanupExportedFiles() {
        for url in exportedFiles {
            try? FileManager.default.removeItem(at: url)
        }
        exportedFiles = []
    }
}

#Preview {
    ExportTakeSheet(take: RecordedTake(
        title: "Yaman alaap",
        instrumentProgram: 0,
        saPitchMidi: 60,
        notes: [],
        sustain: []
    ))
}
