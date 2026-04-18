import SVCore
import SwiftUI

/// A reusable row for displaying a song in a list.
///
/// Shows the song's title, artist, language badge, and difficulty
/// indicator in a compact horizontal layout suitable for use inside
/// a `List` or `ForEach`. The entire row is combined into a single
/// accessibility element for efficient VoiceOver navigation.
struct SongListRow: View {
    // MARK: - Properties

    @Environment(AppThemeManager.self) private var themeManager

    /// The song to display metadata for.
    let song: Song

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            languageBadge

            difficultyIndicator
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(song.title) by \(song.artist), difficulty \(song.difficulty) of 5"
        )
    }

    // MARK: - Private Views

    /// Capsule badge showing the song's language code.
    private var languageBadge: some View {
        Text(song.language.uppercased())
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.fill.tertiary, in: Capsule())
    }

    /// Row of filled and unfilled circles representing song difficulty (1-5).
    private var difficultyIndicator: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { level in
                Circle()
                    .fill(
                        level <= song.difficulty
                            ? (RangLevel(rawValue: song.difficulty)?.bodyTextColor ?? .gray)
                            : themeManager.resolved.dividerColor
                    )
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    List {
        SongListRow(
            song: {
                let song = Song(
                    slugId: "preview-yaman",
                    title: "Raag Yaman Alaap",
                    artist: "Traditional",
                    language: SongLanguage.hindi.rawValue,
                    difficulty: 3,
                    category: SongCategory.classical.rawValue,
                    ragaName: "Yaman",
                    tempo: 80,
                    durationSeconds: 180
                )
                return song
            }()
        )

        SongListRow(
            song: {
                let song = Song(
                    slugId: "preview-bhajan",
                    title: "Vaishnav Jan To",
                    artist: "Narsinh Mehta",
                    language: SongLanguage.hindi.rawValue,
                    difficulty: 1,
                    category: SongCategory.devotional.rawValue,
                    ragaName: "",
                    tempo: 100,
                    durationSeconds: 240
                )
                return song
            }()
        )
    }
    .listStyle(.plain)
}
