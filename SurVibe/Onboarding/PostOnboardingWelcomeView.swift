import os
import SVCore
import SwiftData
import SwiftUI

/// Welcome sheet presented immediately after onboarding completes.
///
/// Shows a personalized welcome message based on the user's chosen skill level,
/// a featured song and lesson matching their preferences, and quick-start
/// buttons that dismiss the sheet and navigate to the relevant tab.
///
/// Presented as a `.sheet` from `ContentView` after the onboarding
/// `fullScreenCover` is dismissed.
struct PostOnboardingWelcomeView: View {
    // MARK: - Logger

    private static let logger = Logger.survibe(category: "OnboardingWelcome")

    // MARK: - Properties

    @Environment(AppThemeManager.self) private var themeManager
    @Environment(OnboardingManager.self) private var onboardingManager
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// A song matching the user's preferred language and difficulty.
    @State private var featuredSong: Song?

    /// A lesson matching the user's chosen difficulty level.
    @State private var featuredLesson: Lesson?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Welcome hero
                    heroSection

                    // Featured content cards
                    if featuredSong != nil || featuredLesson != nil {
                        featuredContentSection
                    }

                    // Quick-start buttons
                    actionButtons
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(Text("Close"))
                    .accessibilityHint(Text("Double tap to dismiss the welcome screen"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            loadFeaturedContent()
        }
        .onAppear { Self.logger.info("Onboarding screen appeared: PostOnboardingWelcome") }
    }

    // MARK: - Subviews

    /// Welcome hero with personalized skill-level greeting.
    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.sparkle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
                .padding(.top, 16)

            Text("Welcome to SurVibe!")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(welcomeMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Featured song and lesson cards.
    private var featuredContentSection: some View {
        VStack(spacing: 16) {
            Text("Start here")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if let song = featuredSong {
                featuredSongCard(song)
            }

            if let lesson = featuredLesson {
                featuredLessonCard(lesson)
            }
        }
    }

    /// Card displaying a recommended song.
    ///
    /// - Parameter song: The song to feature.
    /// - Returns: A styled card with song title, artist, and raga.
    private func featuredSongCard(_ song: Song) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: song.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(verbatim: song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !song.ragaName.isEmpty {
                    Text(verbatim: "Raag \(song.ragaName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.resolved.cardBackgroundColor)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Featured song: \(song.title) by \(song.artist)"))
    }

    /// Card displaying a recommended lesson.
    ///
    /// - Parameter lesson: The lesson to feature.
    /// - Returns: A styled card with lesson title.
    private func featuredLessonCard(_ lesson: Lesson) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "book.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(themeManager.resolved.successColor)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: lesson.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("Lesson")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right.circle.fill")
                .font(.title2)
                .foregroundStyle(themeManager.resolved.successColor)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.resolved.cardBackgroundColor)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Featured lesson: \(lesson.title)"))
    }

    /// Quick-start action buttons.
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                dismiss()
                router.switchTab(to: .songs)
            } label: {
                Label("Start Playing", systemImage: "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel(Text("Start Playing"))
            .accessibilityHint(Text("Double tap to go to the Songs tab"))

            Button {
                dismiss()
                router.switchTab(to: .learn)
            } label: {
                Label("Start Learning", systemImage: "book.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    )
            }
            .accessibilityLabel(Text("Start Learning"))
            .accessibilityHint(Text("Double tap to go to the Learn tab"))
        }
        .padding(.top, 8)
    }

    // MARK: - Private Methods

    /// Welcome message tailored to the user's chosen skill level.
    private var welcomeMessage: String {
        switch onboardingManager.skillLevel {
        case .beginner:
            "Perfect setup for a beginner! We've prepared easy songs and guided lessons to get you started."
        case .intermediate:
            "Great choices! We've got intermediate ragas and songs ready for you."
        case .advanced:
            "Welcome, experienced musician! Dive into advanced ragas and challenging compositions."
        }
    }

    /// Loads a featured song and lesson from SwiftData based on user preferences.
    private func loadFeaturedContent() {
        let languageCode = onboardingManager.preferredLanguageCode
        let targetDifficulty = onboardingManager.skillLevel.difficulty

        // Fetch a song matching language + difficulty (fallback to any song)
        do {
            var descriptor = FetchDescriptor<Song>(
                predicate: #Predicate<Song> { song in
                    song.language == languageCode && song.difficulty <= targetDifficulty
                },
                sortBy: [SortDescriptor(\Song.sortOrder)]
            )
            descriptor.fetchLimit = 1
            let songs = try modelContext.fetch(descriptor)
            featuredSong = songs.first

            // Fallback: any song
            if featuredSong == nil {
                var fallbackDescriptor = FetchDescriptor<Song>(
                    sortBy: [SortDescriptor(\Song.sortOrder)]
                )
                fallbackDescriptor.fetchLimit = 1
                let fallbackSongs = try modelContext.fetch(fallbackDescriptor)
                featuredSong = fallbackSongs.first
            }
        } catch {
            // Non-critical — just don't show a featured song
        }

        // Fetch a lesson matching difficulty (fallback to any lesson)
        do {
            var descriptor = FetchDescriptor<Lesson>(
                predicate: #Predicate<Lesson> { lesson in
                    lesson.difficulty <= targetDifficulty
                },
                sortBy: [SortDescriptor(\Lesson.orderIndex)]
            )
            descriptor.fetchLimit = 1
            let lessons = try modelContext.fetch(descriptor)
            featuredLesson = lessons.first

            // Fallback: any lesson
            if featuredLesson == nil {
                var fallbackDescriptor = FetchDescriptor<Lesson>(
                    sortBy: [SortDescriptor(\Lesson.orderIndex)]
                )
                fallbackDescriptor.fetchLimit = 1
                let fallbackLessons = try modelContext.fetch(fallbackDescriptor)
                featuredLesson = fallbackLessons.first
            }
        } catch {
            // Non-critical — just don't show a featured lesson
        }
    }
}

// MARK: - Preview

#Preview {
    PostOnboardingWelcomeView()
        .environment(AppThemeManager())
        .environment(OnboardingManager())
        .environment(AppRouter())
}
