import SVAudio
import SVCore
import SVLearning
import SwiftUI
import UniformTypeIdentifiers
import os.log

/// The main song library grid view with search, filters, and sort.
///
/// Displays songs in a 2-column adaptive grid with a search bar, filter bar,
/// sort menu, and song count badge. Premium-locked songs show a sign-in
/// prompt sheet when tapped.
///
/// Receives `SongLibraryViewModel` via the SwiftUI environment.
struct SongLibraryView: View {
    // MARK: - Properties

    @Environment(AppThemeManager.self)
    private var themeManager
    @Environment(SongLibraryViewModel.self)
    private var viewModel
    @Environment(AppRouter.self)
    private var router
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.modelContext)
    private var modelContext

    /// Tracks keyboard focus for hardware-keyboard navigation.
    @FocusState
    private var focusedSongID: Song.ID?

    /// Controls the sign-in prompt sheet for premium songs.
    @State
    private var signInTrigger: SignInTrigger?

    /// Song for which to show the detail sheet (via long-press context menu).
    /// TODO: Replace with inline Play Along preview (T4.3).
    @State
    private var detailSong: Song?

    /// Controls the song import sheet (paste / text-based flow).
    @State
    private var showImportSheet: Bool = false

    /// Controls the system file picker for `.mxl` / `.musicxml` / `.xml` upload (T8').
    @State
    private var showFilePicker: Bool = false

    /// Inline error surfaced to the user when a file picked via `fileImporter`
    /// fails to import (security-scope denial, unsupported format, parser error).
    @State
    private var fileImportError: String?

    /// True while `ContentImportManager.importMusicXMLAsSong` is running.
    /// Gates the import menu so the user can't kick off two imports at once.
    @State
    private var isImportingFile: Bool = false

    /// Song to open in the edit sheet (user songs only).
    @State
    private var songToEdit: Song?

    /// Song pending delete confirmation (user songs only).
    @State
    private var songToDelete: Song?

    /// Column count computed from measured grid width. Defaults to 2 until
    /// `GeometryReader` reports a real width on first layout.
    @State
    private var gridColumnCount: Int = 2

    // MARK: - Body

    var body: some View {
        @Bindable
        var vm = viewModel

        VStack(spacing: 0) {
            // Filter bar
            SongFilterBar()

            // Content area
            if viewModel.isLoading {
                loadingState
            } else if viewModel.filteredSongs.isEmpty {
                SongLibraryEmptyState(
                    hasActiveFilters: viewModel.hasActiveFilters,
                    clearFiltersAction: { viewModel.clearAllFilters() },
                    onTrySample: {
                        // TODO: Wire to bundled Sukhkarta_Dukhharta.mxl import (Wave 4 D2)
                    }
                )
            } else {
                songGrid
            }
        }
        .searchable(text: $vm.searchText, prompt: Text("Search songs, artists, ragas..."))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                uploadButton
            }

            ToolbarItem(placement: .topBarTrailing) {
                sortMenu
            }

            ToolbarItem(placement: .topBarTrailing) {
                songCountBadge
            }
        }
        .sheet(item: $signInTrigger) { trigger in
            SignInPromptView(trigger: trigger)
        }
        .sheet(item: $detailSong) { song in
            NavigationStack {
                LeanSongPlayAlongView(song: song)
            }
        }
        .sheet(isPresented: $showImportSheet) {
            SongImportSheet()
                .environment(viewModel)
        }
        // T8' — system file picker for user-supplied MusicXML uploads.
        // Filters to the UTIs registered in Info.plist (`org.musicxml.compressed`
        // for `.mxl`, `org.musicxml.score` for `.musicxml`) plus generic XML
        // for `.xml` exports. The picked URL is security-scoped — see
        // `handleFileImporterResult` for the bracketed access.
        // Apple docs:
        //   https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: ContentImportManager.acceptedMusicXMLTypes,
            allowsMultipleSelection: false,
            onCompletion: handleFileImporterResult
        )
        .alert(
            "Import Failed",
            isPresented: Binding(
                get: { fileImportError != nil },
                set: { if !$0 { fileImportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { fileImportError = nil }
        } message: {
            Text(fileImportError ?? "")
        }
        .sheet(item: $songToEdit) { song in
            NavigationStack {
                SongEditView(song: song)
                    .environment(viewModel)
            }
        }
        .alert(
            "Delete Song",
            isPresented: Binding(
                get: { songToDelete != nil },
                set: { if !$0 { songToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let song = songToDelete {
                    viewModel.deleteSong(song)
                    songToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                songToDelete = nil
            }
        } message: {
            if let song = songToDelete {
                Text("Are you sure you want to delete \"\(song.title)\"? This cannot be undone.")
            }
        }
        .task {
            await viewModel.loadSongs()
        }
        .onAppear {
            if focusedSongID == nil, let first = viewModel.filteredSongs.first {
                focusedSongID = first.id
            }
        }
    }

    // MARK: - Keyboard Focus

    /// Static column-count helper keyed by measured width. Used by both the
    /// grid layout and the arrow-key focus math so they stay in lockstep.
    ///
    /// Empirical breakpoints validated against iPhone / iPad portrait / iPad landscape:
    /// - <700pt: 2 columns (iPhone all sizes + split iPad regular)
    /// - 700..<1000pt: 3 columns (iPad portrait, iPad landscape split)
    /// - >=1000pt: 4 columns (iPad Pro landscape, Mac)
    nonisolated static func columnCount(for width: CGFloat) -> Int {
        switch width {
        case ..<700: return 2
        case 700..<1000: return 3
        default: return 4
        }
    }

    /// Moves keyboard focus to the next song card in the given direction.
    private func moveFocus(_ direction: LibraryFocusNavigator.FocusDirection, from currentID: Song.ID) {
        let songs = viewModel.filteredSongs
        guard let currentIndex = songs.firstIndex(where: { $0.id == currentID }) else { return }
        guard
            let nextIndex = LibraryFocusNavigator.nextIndex(
                for: direction,
                currentIndex: currentIndex,
                count: songs.count,
                columns: gridColumnCount
            )
        else { return }
        focusedSongID = songs[nextIndex].id
    }

    // MARK: - Subviews

    /// Song grid with width-responsive column count (2/3/4 depending on width).
    private var songGrid: some View {
        GeometryReader { proxy in
            let count = Self.columnCount(for: proxy.size.width)
            let gridColumnArray = Array(
                repeating: GridItem(.flexible(), spacing: 16),
                count: count
            )

            ScrollView {
                LazyVGrid(columns: gridColumnArray, spacing: 16) {
                    ForEach(viewModel.filteredSongs) { song in
                        songCard(for: song)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .onAppear {
                gridColumnCount = count
            }
            .onChange(of: proxy.size.width) { _, newWidth in
                gridColumnCount = Self.columnCount(for: newWidth)
            }
        }
    }

    /// Renders a single song card with focus, keyboard, and context-menu wiring.
    /// Extracted to keep `songGrid`'s GeometryReader body scannable.
    @ViewBuilder
    private func songCard(for song: Song) -> some View {
        if viewModel.isPremiumLocked(song) {
            SongCardView(song: song)
                .onTapGesture {
                    signInTrigger = .premiumSong
                }
                .focused($focusedSongID, equals: song.id)
                .focusRing(
                    itemID: song.id,
                    focusedID: focusedSongID,
                    accent: themeManager.resolved.accentColor
                )
                .onKeyPress(.return) {
                    signInTrigger = .premiumSong
                    return .handled
                }
                .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                    let direction: LibraryFocusNavigator.FocusDirection
                    switch press.key {
                    case .upArrow: direction = .up
                    case .downArrow: direction = .down
                    case .leftArrow: direction = .left
                    case .rightArrow: direction = .right
                    default: return .ignored
                    }
                    moveFocus(direction, from: song.id)
                    return .handled
                }
                .onKeyPress(.escape) {
                    focusedSongID = nil
                    return .handled
                }
        } else {
            NavigationLink(value: AppDestination.playAlong(song)) {
                SongCardView(song: song)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded {
                    MultiChannelLog.shared.log(.info, "==> SongLibraryView: NavigationLink tap on '\(song.title)' (slug=\(song.slugId))")
                }
            )
            .focused($focusedSongID, equals: song.id)
            .focusRing(
                itemID: song.id,
                focusedID: focusedSongID,
                accent: themeManager.resolved.accentColor
            )
            .onKeyPress(.return) {
                router.openSong(song.id)
                return .handled
            }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                let direction: LibraryFocusNavigator.FocusDirection
                switch press.key {
                case .upArrow: direction = .up
                case .downArrow: direction = .down
                case .leftArrow: direction = .left
                case .rightArrow: direction = .right
                default: return .ignored
                }
                moveFocus(direction, from: song.id)
                return .handled
            }
            .onKeyPress(.escape) {
                focusedSongID = nil
                return .handled
            }
            .contextMenu {
                Button {
                    detailSong = song
                } label: {
                    Label("Song Details", systemImage: "info.circle")
                }
                if song.source == "user" {
                    Button {
                        songToEdit = song
                    } label: {
                        Label("Edit Song", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        songToDelete = song
                    } label: {
                        Label("Delete Song", systemImage: "trash")
                    }
                }
            }
        }
    }

    /// Loading state with shimmer placeholders.
    private var loadingState: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: gridColumnCount),
                spacing: 16
            ) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.resolved.cardBackgroundColor)
                        .frame(height: 200)
                        .shimmer()
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    /// Sort menu in the toolbar.
    private var sortMenu: some View {
        Menu {
            ForEach(SongSortOption.allCases) { option in
                Button {
                    viewModel.updateSort(option)
                } label: {
                    Label(option.label, systemImage: option.icon)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .accessibilityLabel(Text("Sort songs"))
                .accessibilityHint(Text("Double tap to choose a sort order"))
        }
    }

    /// Song count badge in the toolbar.
    private var songCountBadge: some View {
        Text(verbatim: "\(viewModel.filteredSongs.count)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(themeManager.resolved.nestedSurfaceColor)
            )
            .accessibilityLabel(Text("\(viewModel.filteredSongs.count) songs"))
    }

    /// Upload Song toolbar menu (T8').
    ///
    /// Exposes two paths:
    /// - **Choose from Files**: presents the system `.fileImporter` filtered
    ///   to MusicXML UTIs (`.mxl` / `.musicxml` / `.xml`).
    /// - **Paste notation**: opens the existing `SongImportSheet` for text
    ///   paste of Sargam / Western / inline MusicXML.
    ///
    /// While an import is running (`isImportingFile == true`) the menu shows
    /// a `ProgressView` instead, matching the in-flight pattern used by
    /// `SongImportSheet.importButton`.
    private var uploadButton: some View {
        Group {
            if isImportingFile {
                ProgressView()
                    .accessibilityLabel(Text("Importing song"))
            } else {
                Menu {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Choose from Files…", systemImage: "doc.badge.plus")
                    }
                    .accessibilityLabel(Text("Choose a MusicXML file from Files"))
                    .accessibilityHint(Text("Opens a file picker filtered to .mxl, .musicxml, and .xml"))

                    Button {
                        showImportSheet = true
                    } label: {
                        Label("Paste notation…", systemImage: "doc.text")
                    }
                    .accessibilityLabel(Text("Paste song notation as text"))
                    .accessibilityHint(Text("Opens the manual paste-and-import sheet"))
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .accessibilityLabel(Text("Import song"))
                        .accessibilityHint(Text("Double tap to choose how to import a new song"))
                }
            }
        }
    }

    // MARK: - File Importer Handling (T8')

    /// Handles the `.fileImporter` completion: opens security-scoped resource
    /// access, runs the MusicXML pipeline, refreshes the library, and
    /// surfaces any errors inline.
    ///
    /// Per Apple's file-importer contract, URLs returned outside the app
    /// sandbox are security-scoped. Callers MUST bracket reads with
    /// `startAccessingSecurityScopedResource()` and the matching
    /// `stopAccessingSecurityScopedResource()`. Failure to start access
    /// returns `false` and means we are not entitled to read the file.
    ///
    /// Apple docs:
    ///   https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource()
    ///
    /// - Parameter result: The result delivered by SwiftUI's `fileImporter`.
    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            fileImportError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            importPickedURL(url)
        }
    }

    /// Opens security-scoped access for `url`, runs the import pipeline,
    /// closes access, then reloads the library.
    ///
    /// - Parameter url: The URL returned by the system file picker. Must be
    ///   wrapped in `startAccessingSecurityScopedResource()` since iOS file
    ///   pickers grant only sandbox-scoped access to user-picked files.
    private func importPickedURL(_ url: URL) {
        let logger = Logger.survibe(category: "SongLibraryView.fileImporter")
        let name = url.lastPathComponent
        let didStartScope = url.startAccessingSecurityScopedResource()
        guard didStartScope else {
            fileImportError = "SurVibe couldn't open '\(name)' from Files. "
                + "The system did not grant read access."
            logger.error(
                "startAccessingSecurityScopedResource returned false for \(name, privacy: .public)"
            )
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        isImportingFile = true
        defer { isImportingFile = false }

        do {
            _ = try ContentImportManager.importMusicXMLAsSong(
                from: url,
                into: modelContext
            )
            Task { await viewModel.loadSongs() }
            logger.info("Imported user MXL \(name, privacy: .public)")
        } catch {
            fileImportError = error.localizedDescription
            let desc = error.localizedDescription
            logger.error(
                "Import failed for \(name, privacy: .public): \(desc, privacy: .public)"
            )
        }
    }
}
