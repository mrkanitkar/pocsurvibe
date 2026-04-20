import SVCore
import SVLearning
import SwiftData
import SwiftUI

/// Full edit sheet for a user-imported song.
///
/// Presents metadata fields and notation text editors pre-populated from the
/// existing song. On save, the notation is re-run through the full 5-stage
/// import pipeline (parse → normalise → validate → synthesise MIDI) and the
/// result is applied to the Song in place via `SongLibraryViewModel.updateSongFromDTO()`.
///
/// Only shown for songs where `source == "user"`. Admin content is not editable.
struct SongEditView: View {

    // MARK: - Properties

    /// The user-imported song to edit. Injected from the caller.
    let song: Song

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SongLibraryViewModel.self) private var libraryViewModel

    @State private var viewModel: SongImportViewModel?

    // MARK: - Body

    var body: some View {
        Group {
            if let vm = viewModel {
                editContent(vm: vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Edit Song")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityLabel(Text("Cancel edit"))
                    .accessibilityHint(Text("Double tap to discard changes and close"))
            }
        }
        .task {
            let vm = SongImportViewModel(modelContext: modelContext)
            vm.loadForEditing(song)
            viewModel = vm
        }
    }

    // MARK: - Edit Content

    @ViewBuilder
    private func editContent(vm: SongImportViewModel) -> some View {
        TabView(selection: Binding(
            get: { vm.selectedTab },
            set: { vm.selectedTab = $0 }
        )) {
            sargamTab(vm: vm)
                .tag(SongImportViewModel.ImportTab.sargam)
                .tabItem { Label("Sargam", systemImage: "music.note") }

            westernTab(vm: vm)
                .tag(SongImportViewModel.ImportTab.western)
                .tabItem { Label("Western", systemImage: "music.note.list") }

            musicXMLTab(vm: vm)
                .tag(SongImportViewModel.ImportTab.musicXML)
                .tabItem { Label("MusicXML", systemImage: "doc.text") }
        }
        .presentationDetents([.large])
        .onChange(of: vm.importSucceeded) { _, succeeded in
            if succeeded { dismiss() }
        }
        .sheet(isPresented: Binding(get: { vm.showWarnings }, set: { vm.showWarnings = $0 })) {
            warningsSheet(vm: vm)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Edit Error", isPresented: Binding(
            get: { vm.importError != nil },
            set: { if !$0 { vm.importError = nil } }
        )) {
            Button("OK") { vm.importError = nil }
        } message: {
            Text(vm.importError ?? "")
        }
    }

    // MARK: - Metadata Fields

    @ViewBuilder
    private func metadataFields(vm: SongImportViewModel) -> some View {
        @Bindable var vm = vm
        Section("Song Details") {
            TextField("Title", text: $vm.title)
                .accessibilityLabel(Text("Song title"))
                .accessibilityHint(Text("Enter the name of the song"))

            TextField("Artist / Composer", text: $vm.artist)
                .accessibilityLabel(Text("Artist or composer"))
                .accessibilityHint(Text("Enter the name of the composer or artist"))

            Picker("Language", selection: $vm.language) {
                Text("Hindi").tag("hi")
                Text("Marathi").tag("mr")
                Text("English").tag("en")
            }
            .accessibilityLabel(Text("Song language"))

            Stepper("Difficulty: \(vm.difficulty)", value: $vm.difficulty, in: 1...5)
                .accessibilityLabel(Text("Difficulty level \(vm.difficulty) of 5"))
                .accessibilityHint(Text("Swipe up or down to adjust difficulty"))

            Picker("Category", selection: $vm.category) {
                Text("Folk").tag("folk")
                Text("Classical").tag("classical")
                Text("Devotional").tag("devotional")
                Text("Film").tag("film")
                Text("Nursery").tag("nursery")
                Text("Popular").tag("popular")
            }
            .accessibilityLabel(Text("Song category"))
        }
    }

    // MARK: - Save Button

    @ViewBuilder
    private func saveButton(vm: SongImportViewModel) -> some View {
        Section {
            if vm.isImporting {
                VStack(spacing: 8) {
                    ProgressView(value: vm.progress)
                        .accessibilityLabel(Text("Save progress \(Int(vm.progress * 100)) percent"))
                    Text(vm.progressStageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Save Changes") {
                    vm.startEdit { [song] dto in
                        libraryViewModel.updateSongFromDTO(song, dto: dto)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("Save changes"))
                .accessibilityHint(Text("Double tap to re-parse the notation and save all changes"))
            }
        }
    }

    // MARK: - Tabs

    private func sargamTab(vm: SongImportViewModel) -> some View {
        @Bindable var vm = vm
        return Form {
            metadataFields(vm: vm)

            Section("Sargam Notation") {
                TextEditor(text: $vm.sargamText)
                    .frame(minHeight: 120)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel(Text("Sargam notation text"))
                    .accessibilityHint(Text("Edit notes like Sa Re Ga Ma Pa Dha Ni"))

                Text("Example: Sa Re Ga Ma Pa Dha Ni Sa")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            saveButton(vm: vm)
        }
    }

    private func westernTab(vm: SongImportViewModel) -> some View {
        @Bindable var vm = vm
        return Form {
            metadataFields(vm: vm)

            Section("Western Notation") {
                TextEditor(text: $vm.westernText)
                    .frame(minHeight: 120)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel(Text("Western notation text"))
                    .accessibilityHint(Text("Edit notes like C4 D4 E4 F4 G4 A4 B4 C5"))

                Text("Example: C4 D4 E4 F4 G4 A4 B4 C5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            saveButton(vm: vm)
        }
    }

    private func musicXMLTab(vm: SongImportViewModel) -> some View {
        @Bindable var vm = vm
        return Form {
            metadataFields(vm: vm)

            Section("MusicXML") {
                TextEditor(text: $vm.musicXMLText)
                    .frame(minHeight: 120)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel(Text("MusicXML document text"))
                    .accessibilityHint(Text("Paste a replacement MusicXML document here"))

                Text("Paste a MusicXML document to replace the existing notation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            saveButton(vm: vm)
        }
    }

    // MARK: - Warnings Sheet

    private func warningsSheet(vm: SongImportViewModel) -> some View {
        NavigationStack {
            List {
                ForEach(vm.pendingWarnings) { warning in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: warningIcon(warning.severity))
                            .foregroundStyle(warningColor(warning.severity))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(warning.message)
                                .font(.body)
                            Text(warning.severity.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("\(warning.severity.rawValue) warning: \(warning.message)"))
                }
            }
            .navigationTitle("Save Warnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Anyway") {
                        vm.showWarnings = false
                    }
                    .accessibilityLabel(Text("Save despite warnings"))
                    .accessibilityHint(Text("Double tap to save the song with these warnings"))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.showWarnings = false
                        vm.reset()
                    }
                    .accessibilityLabel(Text("Cancel save"))
                }
            }
        }
    }

    // MARK: - Warning Helpers

    private func warningIcon(_ severity: ParseWarning.Severity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    private func warningColor(_ severity: ParseWarning.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
