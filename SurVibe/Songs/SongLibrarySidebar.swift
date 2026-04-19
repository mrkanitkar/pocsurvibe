import SVCore
import SwiftData
import SwiftUI

/// Sidebar variant of the song library used inside `NavigationSplitView`.
///
/// Renders a `List` bound to the parent's `selection` binding so the
/// detail column updates when the user picks a song. Uses `@Query` with
/// title sort for a lightweight display — the full search/filter experience
/// remains available in `SongLibraryView` on compact layouts.
struct SongLibrarySidebar: View {
    // MARK: - Properties

    /// The currently selected song ID, driving the split-view detail column.
    @Binding var selection: Song.ID?

    @Query(sort: \Song.title) private var songs: [Song]

    @Environment(AppThemeManager.self) private var themeManager

    // MARK: - Body

    var body: some View {
        List(songs, selection: $selection) { song in
            SongListRow(song: song)
                .tag(song.id)
        }
        .navigationTitle("Songs")
        .accessibilityLabel(Text("Songs sidebar"))
    }
}

// MARK: - Preview

#Preview {
    NavigationSplitView {
        SongLibrarySidebar(selection: .constant(nil))
            .environment(AppThemeManager())
    } detail: {
        Text("Select a song")
    }
    .modelContainer(for: Song.self, inMemory: true)
}
