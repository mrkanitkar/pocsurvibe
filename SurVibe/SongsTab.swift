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
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .playAlong(let song):
                    PlayAlongSceneHost(song: song)
                default:
                    EmptyView()
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
}

// MARK: - Preview

#Preview {
    SongsTab()
        .modelContainer(for: Song.self, inMemory: true)
        .environment(AppThemeManager())
        .environment(AppRouter())
}
