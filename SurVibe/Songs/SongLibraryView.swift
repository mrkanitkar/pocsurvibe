import SVCore
import SVLearning
import SwiftUI

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

    /// Tracks keyboard focus for hardware-keyboard navigation.
    @FocusState
    private var focusedSongID: Song.ID?

    /// Controls the sign-in prompt sheet for premium songs.
    @State
    private var signInTrigger: SignInTrigger?

    /// Song for which to show the detail sheet (via long-press context menu).
    @State
    private var detailSong: Song?

    /// Controls the song import sheet.
    @State
    private var showImportSheet: Bool = false

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
                SongDetailView(song: song)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showImportSheet) {
            SongImportSheet()
                .environment(viewModel)
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
            NavigationLink(value: song) {
                SongCardView(song: song)
            }
            .buttonStyle(.plain)
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

    /// Upload Song toolbar button.
    private var uploadButton: some View {
        Button {
            showImportSheet = true
        } label: {
            Image(systemName: "square.and.arrow.down")
                .accessibilityLabel(Text("Import song"))
                .accessibilityHint(Text("Double tap to import a new song"))
        }
    }
}
