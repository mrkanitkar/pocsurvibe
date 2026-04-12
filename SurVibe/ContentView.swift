import SVCore
import SwiftUI

/// Root content view with 5-tab navigation and onboarding flow.
///
/// Each tab maintains its own NavigationStack internally.
/// The AppRouter provides programmatic tab switching and navigation.
///
/// On first launch, presents `OnboardingContainerView` as a full-screen cover.
/// After onboarding completes, shows `PostOnboardingWelcomeView` as a sheet.
struct ContentView: View {
    // MARK: - Properties

    @State
    private var selectedTab: AppTab = .home
    @State
    private var router = AppRouter()

    @Environment(OnboardingManager.self) private var onboardingManager
    @Environment(GamificationService.self) private var gamificationService: GamificationService?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Controls the post-onboarding welcome sheet.
    @State private var showPostOnboarding = false

    /// Guards against showing post-onboarding more than once per session.
    @State private var hasShownPostOnboarding = false

    // MARK: - Body

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.home.label, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                HomeTab()
            }

            Tab(AppTab.learn.label, systemImage: AppTab.learn.systemImage, value: AppTab.learn) {
                LearnTab()
            }

            Tab(AppTab.songs.label, systemImage: AppTab.songs.systemImage, value: AppTab.songs) {
                SongsTab()
            }

            Tab(
                AppTab.profile.label,
                systemImage: AppTab.profile.systemImage,
                value: AppTab.profile
            ) {
                ProfileTab()
            }
        }
        .environment(router)
        .onChange(of: selectedTab) { _, newTab in
            router.switchTab(to: newTab)
            AnalyticsManager.shared.track(.tabSelected, properties: ["tab": newTab.label])
        }
        .onChange(of: router.currentTab) { _, newTab in
            // Sync programmatic tab changes (e.g. from PostOnboardingWelcomeView)
            // back to the TabView selection binding.
            if selectedTab != newTab {
                selectedTab = newTab
            }
        }
        .fullScreenCover(
            isPresented: showOnboarding,
            onDismiss: {
                // Show post-onboarding welcome after the fullScreenCover is fully dismissed.
                // Using onDismiss avoids race conditions from presenting a sheet while
                // the fullScreenCover dismiss animation is still in progress.
                if onboardingManager.isOnboardingComplete, !hasShownPostOnboarding {
                    hasShownPostOnboarding = true
                    showPostOnboarding = true
                }
            },
            content: {
                OnboardingContainerView()
                    .environment(onboardingManager)
            }
        )
        .sheet(isPresented: $showPostOnboarding) {
            PostOnboardingWelcomeView()
                .environment(onboardingManager)
                .environment(router)
        }
        .overlay(alignment: .top) {
            if let achievement = gamificationService?.achievementManager.lastUnlockedAchievement {
                AchievementUnlockToast(
                    title: achievement.title,
                    xpBonus: achievement.xpBonus,
                    onDismiss: {
                        gamificationService?.achievementManager.lastUnlockedAchievement = nil
                    }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .padding(.top, 60)
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(reduceMotion ? .none : .easeOut) {
                        gamificationService?.achievementManager.lastUnlockedAchievement = nil
                    }
                }
            }
        }
        .animation(
            reduceMotion ? .none : .spring(duration: 0.4),
            value: gamificationService?.achievementManager.lastUnlockedAchievement != nil
        )
    }

    // MARK: - Private Methods

    /// Binding that presents the onboarding full-screen cover when onboarding is incomplete.
    private var showOnboarding: Binding<Bool> {
        Binding(
            get: { !onboardingManager.isOnboardingComplete },
            set: { newValue in
                if !newValue {
                    // Dismissed — onboarding was completed or skipped
                }
            }
        )
    }
}

#Preview {
    ContentView()
        .environment(OnboardingManager())
}
