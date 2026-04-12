import SVCore
import SwiftData
import SwiftUI

/// Profile tab — gamification dashboard, authentication, and app settings.
///
/// Displays a full gamification overview including XP progress, rang level,
/// practice streaks, stats grid, and recent achievements. Below that, the
/// existing auth and settings sections are preserved.
///
/// Managers are created lazily in `.task {}` from the SwiftData model context
/// because they require `ModelContext` which is only available at view runtime.
struct ProfileTab: View {
    // MARK: - Properties

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(OnboardingManager.self) private var onboardingManager

    @State private var languageManager = LanguageManager()

    /// Controls the sign-in prompt sheet.
    @State private var signInTrigger: SignInTrigger?

    /// XP manager for reading total XP and today's XP.
    @State private var xpManager: XPManager?

    /// Rang system for level progression and progress-to-next calculations.
    @State private var rangSystem: RangSystem?

    /// Streak tracker for consecutive practice day tracking.
    @State private var streakTracker: StreakTracker?

    /// Achievement manager for earned achievements and trigger checks.
    @State private var achievementManager: AchievementManager?

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
            }
            .navigationTitle("Profile")
            .navigationDestination(for: String.self) { destination in
                if destination == "languages" {
                    LanguageSelectorView()
                } else if destination == "achievements" {
                    if let achievementManager {
                        AchievementGalleryView(achievementManager: achievementManager)
                    }
                }
            }
            .sheet(item: $signInTrigger) { trigger in
                SignInPromptView(trigger: trigger)
            }
            .task {
                initializeManagers()
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
                rang: rangSystem?.currentRang ?? .neel
            )
        }
    }

    /// XP progress card with total XP, progress bar, and today's XP.
    private var xpProgressSection: some View {
        Section {
            XPProgressCard(
                totalXP: xpManager?.totalXP ?? 0,
                xpToday: xpManager?.xpToday ?? 0,
                progressToNextRang: rangSystem?.progressToNextRang ?? 0.0,
                xpToNextRang: rangSystem?.xpToNextRang ?? 0,
                currentRang: rangSystem?.currentRang ?? .neel
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
                bestStreak: streakTracker?.longestStreak ?? 0
            )
        }
    }

    /// Current streak with practiced-today indicator.
    private var streakSection: some View {
        Section {
            StreakSectionView(
                currentStreak: streakTracker?.currentStreak ?? 0,
                practicedToday: streakTracker?.practicedToday ?? false
            )
        }
    }

    /// Preview of latest 3 achievements with "See All" navigation.
    private var achievementPreviewSection: some View {
        Section {
            if let achievementManager {
                AchievementPreviewSection(
                    recentAchievements: Array(achievementManager.earnedAchievements.prefix(3)),
                    achievementManager: achievementManager
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

    /// Creates all gamification managers from the model context.
    ///
    /// Called once in `.task {}` when the view appears. Also triggers
    /// an initial streak recomputation to ensure values are fresh.
    private func initializeManagers() {
        let xp = XPManager(modelContext: modelContext)
        xpManager = xp

        rangSystem = RangSystem(modelContext: modelContext)

        let streak = StreakTracker(modelContext: modelContext)
        streak.recompute()
        streakTracker = streak

        achievementManager = AchievementManager(modelContext: modelContext, xpManager: xp)
    }
}

#Preview {
    ProfileTab()
        .environment(AuthManager.shared)
        .environment(OnboardingManager())
        .modelContainer(for: [
            UserProfile.self,
            XPEntry.self,
            RiyazEntry.self,
            SongProgress.self,
            LessonProgress.self,
            Achievement.self,
        ], inMemory: true)
}
