import SVCore
import SwiftData
import SwiftUI

/// Songs tab — browse and play the song library.
///
/// On iPad and Mac Catalyst (regular horizontal size class), renders a
/// `NavigationSplitView` with `SongLibrarySidebar` in the sidebar column
/// and `SongDetailView` in the detail column. On iPhone (compact), the
/// sidebar column collapses and behaves like a `NavigationStack`.
///
/// Injects `SongLibraryViewModel` via the environment for the full
/// `SongLibraryView` used on compact layouts.
struct SongsTab: View {
    // MARK: - Properties

    @Environment(\.modelContext)
    private var modelContext
    @Environment(AppThemeManager.self)
    private var themeManager
    @Environment(AppRouter.self)
    private var router

    @State
    private var viewModel: SongLibraryViewModel?

    // MARK: - Body

    var body: some View {
        @Bindable
        var router = router

        NavigationSplitView {
            Group {
                if let viewModel {
                    SongLibrarySidebar(selection: $router.selectedSongID)
                        .environment(viewModel)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 420)
        } detail: {
            NavigationStack(path: router.pathForTab(.songs)) {
                detailContent(for: router.selectedSongID)
                    .navigationDestination(for: Song.self) { song in
                        PlayAlongSceneHost(song: song)
                    }
            }
        }
        .background(
            LinearGradient(
                colors: themeManager.resolved.backgroundGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .accessibilityLabel(AccessibilityHelper.tabLabel(for: "Songs"))
        .onAppear {
            if viewModel == nil {
                viewModel = SongLibraryViewModel(modelContext: modelContext)
            }
        }
    }

    // MARK: - Private Methods

    /// Resolves the detail column content for the currently selected song ID.
    ///
    /// Shows `SongDetailView` when a song is selected, or a
    /// `ContentUnavailableView` prompt when nothing is selected.
    ///
    /// - Parameter songID: The optional selected `Song.ID`.
    @ViewBuilder
    private func detailContent(for songID: Song.ID?) -> some View {
        if let songID {
            SongDetailViewResolver(songID: songID)
        } else {
            ContentUnavailableView(
                "Select a Song",
                systemImage: "music.note.list",
                description: Text("Choose a song from the sidebar.")
            )
        }
    }
}

// MARK: - Song Detail Resolver

/// Fetches a `Song` by ID from SwiftData and hands off to `SongDetailView`.
///
/// Avoids requiring every NavigationSplitView call-site to hold a full
/// `Song` object. Falls back to `ContentUnavailableView` if the song
/// has been deleted between selection and render.
private struct SongDetailViewResolver: View {
    // MARK: - Properties

    let songID: Song.ID

    @Query
    private var songs: [Song]

    // MARK: - Initialization

    /// Creates a resolver filtered to the given song ID.
    ///
    /// - Parameter songID: The `UUID` of the song to display.
    init(songID: Song.ID) {
        self.songID = songID
        _songs = Query(filter: #Predicate<Song> { $0.id == songID })
    }

    // MARK: - Body

    var body: some View {
        if let song = songs.first {
            SongDetailView(song: song)
        } else {
            ContentUnavailableView(
                "Song Not Found",
                systemImage: "music.note.list",
                description: Text("The selected song is no longer available.")
            )
        }
    }
}

// MARK: - Preview

#Preview {
    SongsTab()
        .modelContainer(for: Song.self, inMemory: true)
        .environment(AppThemeManager())
        .environment(AppRouter())
}
