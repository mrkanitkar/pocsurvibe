import SVCore
import SVLearning
import SwiftData
import SwiftUI

/// A sheet for importing user songs via text notation or MusicXML.
///
/// Presents four tabs:
/// - **Sargam**: Indian sargam notation text input
/// - **Western**: Western staff notation text input
/// - **MusicXML**: MusicXML document paste input
/// - **My Songs**: Previously imported user songs list
///
/// On successful import, the sheet dismisses automatically.
struct SongImportSheet: View {

    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppThemeManager.self) private var themeManager

    @State private var viewModel: SongImportViewModel?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    importContent(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Import Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityLabel(Text("Cancel import"))
                    .accessibilityHint(Text("Double tap to close this sheet without importing"))
                }
            }
        }
        .onAppear {
            viewModel = SongImportViewModel(modelContext: modelContext)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func importContent(vm: SongImportViewModel) -> some View {
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

            mySongsTab(vm: vm)
                .tag(SongImportViewModel.ImportTab.mySongs)
                .tabItem { Label("My Songs", systemImage: "person.crop.rectangle.stack") }
        }
        .onChange(of: vm.importSucceeded) { _, succeeded in
            if succeeded { dismiss() }
        }
        .sheet(isPresented: Binding(get: { vm.showWarnings }, set: { vm.showWarnings = $0 })) {
            warningsSheet(vm: vm)
        }
        .alert("Import Error", isPresented: Binding(
            get: { vm.importError != nil },
            set: { if !$0 { vm.importError = nil } }
        )) {
            Button("OK") { vm.importError = nil }
        } message: {
            Text(vm.importError ?? "")
        }
    }

    // MARK: - Metadata Fields (shared across tabs)

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

    // MARK: - Import Button

    @ViewBuilder
    private func importButton(vm: SongImportViewModel) -> some View {
        Section {
            if vm.isImporting {
                VStack(spacing: 8) {
                    ProgressView(value: vm.progress)
                        .accessibilityLabel(Text("Import progress \(Int(vm.progress * 100)) percent"))
                    Text(vm.progressStageName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Import Song") {
                    vm.startImport()
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("Import song"))
                .accessibilityHint(Text("Double tap to start importing the song"))
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
                    .accessibilityHint(Text("Enter notes like Sa Re Ga Ma Pa Dha Ni"))

                Text("Example: Sa Re Ga Ma Pa Dha Ni Sa")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            importButton(vm: vm)
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
                    .accessibilityHint(Text("Enter notes like C4 D4 E4 F4 G4 A4 B4 C5"))

                Text("Example: C4 D4 E4 F4 G4 A4 B4 C5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            importButton(vm: vm)
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
                    .accessibilityHint(Text("Paste a MusicXML document here"))

                Text("Paste a MusicXML document (<?xml ...><score-partwise>...)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            importButton(vm: vm)
        }
    }

    private func mySongsTab(vm: SongImportViewModel) -> some View {
        MySongsListView()
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
            .navigationTitle("Import Warnings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue Anyway") {
                        vm.showWarnings = false
                    }
                    .accessibilityLabel(Text("Continue import despite warnings"))
                    .accessibilityHint(Text("Double tap to proceed with import"))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.showWarnings = false
                        vm.reset()
                    }
                    .accessibilityLabel(Text("Cancel import"))
                }
            }
        }
    }

    // MARK: - Warning Helpers

    /// Returns the SF Symbol name for a given warning severity.
    ///
    /// - Parameter severity: The severity of the parse warning.
    /// - Returns: A system image name string.
    private func warningIcon(_ severity: ParseWarning.Severity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    /// Returns the display colour for a given warning severity.
    ///
    /// - Parameter severity: The severity of the parse warning.
    /// - Returns: A SwiftUI `Color` for the severity level.
    private func warningColor(_ severity: ParseWarning.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .warning: return themeManager.resolved.warningColor
        case .error: return themeManager.resolved.errorColor
        }
    }
}

// MARK: - MySongsListView

/// Lists previously imported user songs filtered by source == "user".
///
/// Each row has a swipe-to-delete trailing action and a context menu
/// with Edit and Delete options. Edit opens `SongEditView` as a sheet.
/// Delete shows a confirmation alert before calling `modelContext.delete`.
private struct MySongsListView: View {

    @Query(filter: #Predicate<Song> { $0.source == "user" }, sort: \Song.createdAt, order: .reverse)
    private var userSongs: [Song]

    @Environment(\.modelContext) private var modelContext
    @Environment(SongLibraryViewModel.self) private var libraryViewModel

    @State private var songToEdit: Song?
    @State private var songToDelete: Song?

    var body: some View {
        Group {
            if userSongs.isEmpty {
                ContentUnavailableView(
                    "No Imported Songs",
                    systemImage: "square.and.arrow.down",
                    description: Text("Songs you import will appear here.")
                )
            } else {
                List {
                    ForEach(userSongs) { song in
                        songRow(song)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    songToDelete = song
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .accessibilityLabel(Text("Delete \(song.title)"))

                                Button {
                                    songToEdit = song
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                                .accessibilityLabel(Text("Edit \(song.title)"))
                            }
                            .contextMenu {
                                Button {
                                    songToEdit = song
                                } label: {
                                    Label("Edit Song", systemImage: "pencil")
                                }
                                .accessibilityLabel(Text("Edit \(song.title)"))

                                Button(role: .destructive) {
                                    songToDelete = song
                                } label: {
                                    Label("Delete Song", systemImage: "trash")
                                }
                                .accessibilityLabel(Text("Delete \(song.title)"))
                            }
                    }
                }
            }
        }
        .sheet(item: $songToEdit) { song in
            SongEditView(song: song)
                .environment(libraryViewModel)
        }
        .alert("Delete Song", isPresented: Binding(
            get: { songToDelete != nil },
            set: { if !$0 { songToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let song = songToDelete {
                    libraryViewModel.deleteSong(song)
                }
                songToDelete = nil
            }
            Button("Cancel", role: .cancel) { songToDelete = nil }
        } message: {
            Text("\(songToDelete?.title ?? "") will be permanently deleted.")
        }
    }

    // MARK: - Row

    private func songRow(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.title)
                .font(.headline)
            HStack(spacing: 8) {
                if !song.artist.isEmpty {
                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                difficultyLabel(song.difficulty)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(song.title)\(song.artist.isEmpty ? "" : " by \(song.artist)"), difficulty \(song.difficulty)")
        )
        .accessibilityHint(Text("Swipe left to edit or delete"))
    }

    private func difficultyLabel(_ difficulty: Int) -> some View {
        Text(String(repeating: "★", count: difficulty))
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}
