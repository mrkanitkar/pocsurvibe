import SVCore
import SwiftUI

/// Detail screen for a single song showing metadata, playback controls,
/// and interactive notation display.
///
/// Loads the song's MIDI data into a `SongPlaybackEngine` on appear
/// and provides transport controls for listening. The notation section
/// uses ``NotationContainerView`` with Sargam/Western/Dual display modes,
/// pinch-to-zoom, and accuracy-based label fading via ``SargamFadeManager``.
struct SongDetailView: View {
    // MARK: - Properties

    /// The song to display and play.
    let song: Song

    /// Engine driving playback of this song's MIDI data.
    @State
    private var engine = SongPlaybackEngine()

    /// Manages Sargam label opacity based on playing accuracy.
    @State
    private var fadeManager = SargamFadeManager()

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Environment(\.modelContext)
    private var modelContext

    @Environment(GamificationService.self)
    private var gamificationService: GamificationService?

    @Environment(AppThemeManager.self)
    private var themeManager: AppThemeManager

    /// Whether the practice session full-screen cover is shown.
    @State private var showPractice = false

    /// Whether the play-along full-screen cover is shown.
    @State private var showPlayAlong = false

    // MARK: - Constants

    /// Two-column grid layout for metadata items.
    private let metadataColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection

                playbackSection

                notationSection

                Divider()

                metadataGrid

                // Play Along button
                Button {
                    showPlayAlong = true
                } label: {
                    Label("Play Along", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(themeManager.resolved.accentColor)
                .accessibilityLabel("Play along with this song")
                .accessibilityHint(
                    "Open an interactive play-along session with falling notes and scoring"
                )

                // Practice button
                Button {
                    showPractice = true
                } label: {
                    Label("Practice This Song", systemImage: "music.note.list")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Practice this song")
                .accessibilityHint("Open a practice session for this song")
            }
            .padding()
        }
        .fullScreenCover(isPresented: $showPractice) {
            PracticeSessionView(
                song: song,
                modelContext: modelContext,
                gamificationService: gamificationService
            )
        }
        .fullScreenCover(isPresented: $showPlayAlong) {
            NavigationStack {
                SongPlayAlongView(song: song)
            }
        }
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await engine.load(song: song)
        }
        .onDisappear {
            engine.stop()
        }
    }

    // MARK: - Private Views

    /// Song title, artist, and key metadata in a compact header.
    private var headerSection: some View {
        VStack(spacing: 4) {
            Text(song.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if !song.ragaName.isEmpty {
                    Text(verbatim: "Raag \(song.ragaName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: "\(song.tempo) BPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(song.title) by \(song.artist)")
    }

    /// Two-column grid of song metadata: language, difficulty, category,
    /// raga, tempo, and duration.
    private var metadataGrid: some View {
        LazyVGrid(columns: metadataColumns, alignment: .leading, spacing: 16) {
            metadataItem(
                label: "Language",
                value: song.songLanguage?.rawValue.uppercased() ?? song.language.uppercased()
            )

            metadataItem(
                label: "Difficulty",
                value: "\(song.difficulty) / 5"
            )

            metadataItem(
                label: "Category",
                value: song.songCategory?.rawValue.capitalized ?? song.category.capitalized
            )

            metadataItem(
                label: "Raga",
                value: song.ragaName.isEmpty ? "—" : song.ragaName
            )

            metadataItem(
                label: "Tempo",
                value: "\(song.tempo) BPM"
            )

            metadataItem(
                label: "Duration",
                value: formattedDuration
            )
        }
        .padding()
        .background(themeManager.resolved.cardBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Playback controls section with a section header.
    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            PlaybackControlsView(engine: engine)
        }
    }

    /// Notation display section with Sargam/Western renderers and error fallback.
    ///
    /// Shows ``NotationContainerView`` when the song has notation data,
    /// or ``NotationErrorView`` when data is missing.
    private var notationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notation")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if hasNotationData {
                NotationContainerView(
                    song: song,
                    currentNoteIndex: engine.currentNoteIndex,
                    labelOpacity: fadeManager.labelOpacity
                )
            } else {
                NotationErrorView.noNotation
            }
        }
    }

    /// Whether the song has any decoded notation data (Sargam or Western).
    private var hasNotationData: Bool {
        let sargam = song.decodedSargamNotes ?? []
        let western = song.decodedWesternNotes ?? []
        return !sargam.isEmpty || !western.isEmpty
    }

    // MARK: - Private Methods

    /// Creates a labeled metadata item with a caption label above a body value.
    ///
    /// - Parameters:
    ///   - label: The metadata field name (e.g., "Language").
    ///   - value: The metadata field value (e.g., "HI").
    /// - Returns: A VStack with label and value text.
    private func metadataItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    /// Formats `song.durationSeconds` as "Xm Ys" for display.
    private var formattedDuration: String {
        let minutes = song.durationSeconds / 60
        let seconds = song.durationSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SongDetailView(
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
    }
}
