import SVCore
import SwiftData
import SwiftUI

/// Profile tab — gamification dashboard, authentication, and app settings.
///
/// Displays a full gamification overview including XP progress, rang level,
/// practice streaks, stats grid, and recent achievements. Below that, the
/// existing auth and settings sections are preserved.
///
/// Reads gamification data from the shared `GamificationService` injected
/// via `.environment()` at the app root. Refreshes streak on appear.
struct ProfileTab: View {
    // MARK: - Properties

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(OnboardingManager.self) private var onboardingManager
    @Environment(GamificationService.self) private var gamificationService: GamificationService?
    @Environment(AppThemeManager.self) private var themeManager

    @State private var languageManager = LanguageManager()

    /// Controls the sign-in prompt sheet.
    @State private var signInTrigger: SignInTrigger?

    /// All UserProfile records — expected to be exactly one singleton.
    @Query private var userProfiles: [UserProfile]

    /// The singleton user profile, or nil if not yet created.
    private var userProfile: UserProfile? { userProfiles.first }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                profileHeaderSection
                xpProgressSection
                statsGridSection
                streakSection
                achievementPreviewSection
                authSection
                settingsSection
                appearanceSection
            }
            .navigationTitle("Profile")
            .navigationDestination(for: String.self) { destination in
                if destination == "languages" {
                    LanguageSelectorView()
                } else if destination == "appearance" {
                    ThemeCarouselPicker()
                } else if destination == "achievements" {
                    if let am = gamificationService?.achievementManager {
                        AchievementGalleryView(achievementManager: am)
                    }
                }
            }
            .sheet(item: $signInTrigger) { trigger in
                SignInPromptView(trigger: trigger)
            }
            .task {
                // Refresh streak and achievements on each profile visit
                gamificationService?.refreshStreak()
                gamificationService?.achievementManager.checkTriggers(
                    context: buildProfileAchievementContext()
                )
            }
        }
        .accessibilityLabel(AccessibilityHelper.tabLabel(for: "Profile"))
    }

    // MARK: - Gamification Sections

    /// Profile header with avatar, display name, and rang badge.
    private var profileHeaderSection: some View {
        Section {
            ProfileHeaderView(
                displayName: displayName,
                rang: gamificationService?.rangSystem.currentRang ?? .neel
            )
        }
    }

    /// XP progress card with total XP, progress bar, and today's XP.
    private var xpProgressSection: some View {
        Section {
            XPProgressCard(
                totalXP: gamificationService?.xpManager.totalXP ?? 0,
                xpToday: gamificationService?.xpManager.xpToday ?? 0,
                progressToNextRang: gamificationService?.rangSystem.progressToNextRang ?? 0.0,
                xpToNextRang: gamificationService?.rangSystem.xpToNextRang ?? 0,
                currentRang: gamificationService?.rangSystem.currentRang ?? .neel
            )
        }
    }

    /// 2x2 grid of aggregate stats from SwiftData.
    private var statsGridSection: some View {
        Section {
            StatsGridView(
                totalPracticeMinutes: totalPracticeMinutes,
                songsPlayed: songsPlayedCount,
                lessonsComplete: lessonsCompleteCount,
                bestStreak: gamificationService?.streakTracker.longestStreak ?? 0
            )
        }
    }

    /// Current streak with practiced-today indicator and freeze token badge.
    private var streakSection: some View {
        Section {
            StreakSectionView(
                currentStreak: gamificationService?.streakTracker.currentStreak ?? 0,
                practicedToday: gamificationService?.streakTracker.practicedToday ?? false,
                freezeTokensAvailable: userProfile?.streakFreezeTokens ?? 0
            )
        }
    }

    /// Preview of latest 3 achievements with "See All" navigation.
    private var achievementPreviewSection: some View {
        Section {
            if let am = gamificationService?.achievementManager {
                AchievementPreviewSection(
                    recentAchievements: Array(am.earnedAchievements.prefix(3)),
                    achievementManager: am
                )
            } else {
                Text("Loading achievements...")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Auth Section

    /// Authentication section -- shows user info when signed in, or sign-in button when anonymous.
    private var authSection: some View {
        Section {
            if authManager.isAuthenticated {
                // Signed-in state
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        if let user = authManager.currentUser {
                            if !user.displayName.isEmpty {
                                Text(verbatim: user.displayName)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            } else {
                                Text("SurVibe User")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }

                            if let email = user.email {
                                Text(verbatim: email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("Signed in with Apple")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 8)

                // Sign Out button
                Button(role: .destructive) {
                    authManager.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.forward")
                }
                .accessibilityLabel(Text("Sign Out"))
                .accessibilityHint(Text("Double tap to sign out of your Apple ID"))
            } else {
                // Anonymous state
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not Signed In")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Sign in to sync progress and access premium content")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)

                // Sign In button
                Button {
                    signInTrigger = .profile
                } label: {
                    Label("Sign in with Apple", systemImage: "apple.logo")
                }
                .accessibilityLabel(Text("Sign in with Apple"))
                .accessibilityHint(Text("Double tap to sign in with your Apple ID"))
            }
        }
    }

    // MARK: - Settings Section

    /// User preference for auto-hiding sargam labels as accuracy improves.
    @AppStorage("autoHideSargamLabels") private var autoHideSargamLabels: Bool = true

    /// Settings section -- language selector, sargam label toggle, and redo onboarding.
    private var settingsSection: some View {
        Section(header: Text("Settings")) {
            NavigationLink(value: "languages") {
                HStack {
                    Label("App Language", systemImage: "globe")
                    Spacer()
                    Text(verbatim: languageManager.currentLanguageDisplayName)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(Text("App Language"))
            .accessibilityHint(
                Text("Current language: \(languageManager.currentLanguageDisplayName). Double tap to change.")
            )

            // Auto-hide sargam labels toggle
            Toggle("Auto-hide sargam labels", isOn: $autoHideSargamLabels)
                .accessibilityLabel("Auto-hide sargam labels")
                .accessibilityHint("When enabled, sargam labels fade as your accuracy improves")

            // Redo Onboarding
            Button {
                onboardingManager.resetOnboarding()
            } label: {
                Label("Redo Onboarding", systemImage: "arrow.counterclockwise")
            }
            .accessibilityLabel(Text("Redo Onboarding"))
            .accessibilityHint(Text("Double tap to restart the onboarding flow and reconfigure your preferences"))
        }
    }

    // MARK: - Appearance Section

    /// Appearance section -- navigates to the theme carousel picker.
    private var appearanceSection: some View {
        Section(header: Text("Appearance")) {
            NavigationLink(value: "appearance") {
                HStack {
                    Label("Theme", systemImage: "paintbrush.fill")
                    Spacer()
                    Text(verbatim: themeManager.currentPreset.displayName)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("App Theme")
            .accessibilityHint(
                "Current theme: \(themeManager.currentPreset.displayName). Double tap to change."
            )
        }
    }

    // MARK: - Computed Data

    /// Display name derived from the current authenticated user, falling back to "SurVibe User".
    private var displayName: String {
        if let user = authManager.currentUser, !user.displayName.isEmpty {
            return user.displayName
        }
        return "SurVibe User"
    }

    /// Total practice minutes from all RiyazEntry records.
    private var totalPracticeMinutes: Int {
        let descriptor = FetchDescriptor<RiyazEntry>()
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return entries.reduce(0) { $0 + $1.durationMinutes }
    }

    /// Count of songs with at least one play session.
    private var songsPlayedCount: Int {
        let descriptor = FetchDescriptor<SongProgress>(
            predicate: #Predicate { $0.timesPlayed > 0 }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Count of completed lessons.
    private var lessonsCompleteCount: Int {
        let descriptor = FetchDescriptor<LessonProgress>(
            predicate: #Predicate { $0.isCompleted == true }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Private Methods

    /// Builds an `AchievementContext` from current profile state for passive achievement checks.
    ///
    /// Called on ProfileTab appear to evaluate achievements that may have been
    /// earned while the profile was not visible (e.g., streak milestones).
    private func buildProfileAchievementContext() -> AchievementContext {
        AchievementContext(
            totalXP: gamificationService?.xpManager.totalXP ?? 0,
            currentStreak: gamificationService?.streakTracker.currentStreak ?? 0,
            songsCompleted: songsPlayedCount,
            lessonsCompleted: lessonsCompleteCount,
            totalPracticeSessions: totalPracticeMinutes,
            latestQuizScore: nil,
            newRangLevel: nil,
            firstPitchDetected: false,
            hasProficientSong: false
        )
    }
}

#Preview {
    ProfileTab()
        .environment(AuthManager.shared)
        .environment(OnboardingManager())
        .environment(AppThemeManager())
        .modelContainer(for: [
            UserProfile.self,
            XPEntry.self,
            RiyazEntry.self,
            SongProgress.self,
            LessonProgress.self,
            Achievement.self,
        ], inMemory: true)
}
