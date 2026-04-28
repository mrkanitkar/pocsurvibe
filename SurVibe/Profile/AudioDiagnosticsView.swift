import SVAudio
import SwiftUI

/// User-facing toggle for saving production audio diagnostic logs to
/// disk, plus share / delete actions.
///
/// Reachable via `ProfileTab` → "Audio Logs" row.
///
/// In Release builds the file mirror defaults OFF and the user opts in
/// here; the toggle's value is persisted via `@AppStorage` and re-applied
/// to `MultiChannelLog.shared` at app launch (in `SurVibeApp.init`).
/// In DEBUG builds the file mirror defaults ON for development; flipping
/// the toggle still works the same way.
struct AudioDiagnosticsView: View {

    @AppStorage("audioLogsEnabled")
    private var audioLogsEnabled: Bool = false

    @State private var logFileSize: Int?
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            Section {
                Toggle("Save audio logs to disk", isOn: $audioLogsEnabled)
                    .onChange(of: audioLogsEnabled) { _, newValue in
                        MultiChannelLog.shared.isFileMirrorEnabled = newValue
                    }
                    .accessibilityLabel("Save audio logs to disk")
                    .accessibilityHint(
                        Text("When enabled, audio events are saved to a log file you can share with support.")
                    )
            } header: {
                Text("Audio Diagnostic Logs")
            } footer: {
                Text("Off by default. Useful for diagnosing audio issues with support.")
            }

            if audioLogsEnabled {
                Section("Log File") {
                    HStack {
                        Text("Size")
                        Spacer()
                        if let size = logFileSize {
                            Text(verbatim: formatBytes(size))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not yet written")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    ShareLink(item: MultiChannelLog.shared.logFileURL) {
                        Label("Share logs", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share audio logs")
                    .accessibilityHint("Open the share sheet for the audio diagnostic log file.")
                    .disabled(logFileSize == nil)

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete logs", systemImage: "trash")
                    }
                    .accessibilityLabel("Delete audio logs")
                    .accessibilityHint("Removes the on-disk audio log file.")
                    .disabled(logFileSize == nil)
                    .confirmationDialog(
                        "Delete audio logs?",
                        isPresented: $showDeleteConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            MultiChannelLog.shared.purge()
                            // Briefly delay to allow async purge to complete, then refresh size.
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(120))
                                refreshLogSize()
                            }
                        }
                        Button("Cancel", role: .cancel) { }
                    }
                }
            }
        }
        .navigationTitle("Audio Diagnostics")
        .onAppear {
            refreshLogSize()
        }
        .onChange(of: audioLogsEnabled) { _, _ in
            refreshLogSize()
        }
    }

    private func refreshLogSize() {
        let url = MultiChannelLog.shared.logFileURL
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > 0 {
            logFileSize = size
        } else {
            logFileSize = nil
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    NavigationStack {
        AudioDiagnosticsView()
    }
}
