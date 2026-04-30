import SwiftUI

/// Empty state view for the song library.
///
/// Displays two distinct modes:
/// - **No songs at all**: Shows a general "no songs" message with updated import guidance
///   and a "Try a sample" button to load a bundled song.
/// - **No matching filters**: Shows a "no results" message with a "Clear Filters" button.
struct SongLibraryEmptyState: View {
    // MARK: - Properties

    /// Whether filters are currently active (determines which message to show).
    let hasActiveFilters: Bool

    /// Action to clear all active filters.
    var clearFiltersAction: (() -> Void)?

    /// Action to import a bundled sample song (e.g. Sukhkarta_Dukhharta.mxl).
    var onTrySample: () -> Void = {}

    // MARK: - Body

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(description)
        } actions: {
            if hasActiveFilters, let clearFiltersAction {
                Button("Clear Filters") {
                    clearFiltersAction()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Clear Filters"))
                .accessibilityHint(Text("Double tap to remove all filters and show all songs"))
            } else {
                Button {
                    onTrySample()
                } label: {
                    Label("Try a sample", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Try a sample"))
                .accessibilityHint(
                    Text("Double tap to import a bundled sample song so you can start playing")
                )
            }
        }
    }

    // MARK: - Private Methods

    /// Title for the empty state.
    private var title: String {
        hasActiveFilters ? "No Matching Songs" : "No Songs Yet"
    }

    /// SF Symbol for the empty state.
    private var icon: String {
        hasActiveFilters ? "magnifyingglass" : "music.note"
    }

    /// Description for the empty state.
    private var description: String {
        if hasActiveFilters {
            "Try adjusting your filters or search terms to find more songs."
        } else {
            "Drop in a .mxl, .musicxml, or .xml file from MuseScore, your teacher,"
                + " or your own composition. Multi-instrument songs play their backing"
                + " while you practice the piano part."
        }
    }

    // MARK: - Test Seam

    #if DEBUG
    /// Simulates a tap on the "Try a sample" button for testing.
    func simulateTrySampleTap() { onTrySample() }
    #endif
}

// MARK: - Preview

#Preview("No Songs") {
    SongLibraryEmptyState(hasActiveFilters: false) {
        print("Try a sample tapped")
    }
}

#Preview("No Matches") {
    SongLibraryEmptyState(hasActiveFilters: true, clearFiltersAction: {})
}
