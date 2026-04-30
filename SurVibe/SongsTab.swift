import SVCore
import SwiftData
import SwiftUI

/// Songs tab — browse and play the song library.
///
/// Single-column `NavigationStack` on all sizes (iPhone + iPad). Was
/// previously a `NavigationSplitView` with a sidebar, but the sidebar
/// detail column reflowed on every reactive tick (e.g. inline-preview
/// `currentTime`), which propagated into Play Along's `fullScreenCover`
/// and remounted `SongPlayAlongView` every ~720ms before its `.task`
/// could run — hanging the feature. User-confirmed they do not need
/// the sidebar.
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

        NavigationStack(path: router.pathForTab(.songs)) {
            Group {
                if let viewModel {
                    SongLibraryView()
                        .environment(viewModel)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationDestination(for: Song.self) { song in
                SongDetailView(song: song)
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
