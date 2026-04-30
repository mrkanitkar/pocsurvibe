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
    @Environment(AppRouter.self)
    private var router

    @Environment(OnboardingManager.self)
    private var onboardingManager
    @Environment(GamificationService.self)
    private var gamificationService: GamificationService?
    @Environment(AppThemeManager.self)
    private var themeManager
    @Environment(\.colorScheme)
    private var colorScheme
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var systemReduceTransparency

    /// Controls the post-onboarding welcome sheet.
    @State
    private var showPostOnboarding = false

    /// Guards against showing post-onboarding more than once per session.
    @State
    private var hasShownPostOnboarding = false

    /// Shared guard for the Play tab's "unsaved scratchpad recording"
    /// protection. Owned here (root view) so the same guard instance is
    /// visible to both `AppRouter.switchTab(to:)` (programmatic switches,
    /// deep links) and the user-driven `TabView` selection binding.
    @State
    private var scratchpadGuard = UnsavedScratchpadGuard()

    // MARK: - Body

    var body: some View {
        // Legacy .tabItem + .tag syntax used intentionally instead of the
        // iOS 18+ `Tab(... value:)` API. The new API auto-adopts a sidebar
        // layout on iPad regular-width which (a) the user does not want and
        // (b) reflows the TabView body on every reactive tick, remounting
        // presented sheets/covers (Play Along hung — see commit aaa6270).
        TabView(selection: $selectedTab) {
            HomeTab()
                .tabItem { Label(AppTab.home.label, systemImage: AppTab.home.systemImage) }
                .tag(AppTab.home)

            LearnTab()
                .tabItem { Label(AppTab.learn.label, systemImage: AppTab.learn.systemImage) }
                .tag(AppTab.learn)

            PlayTab(scratchpadGuard: scratchpadGuard)
                .tabItem { Label(AppTab.play.label, systemImage: AppTab.play.systemImage) }
                .tag(AppTab.play)

            SongsTab()
                .tabItem { Label(AppTab.songs.label, systemImage: AppTab.songs.systemImage) }
                .tag(AppTab.songs)

            ProfileTab()
                .tabItem { Label(AppTab.profile.label, systemImage: AppTab.profile.systemImage) }
                .tag(AppTab.profile)
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
        .tint(themeManager.resolved.accentColor)
        .onChange(of: colorScheme) { _, newScheme in
            themeManager.updateColorScheme(newScheme)
        }
        .onChange(of: systemReduceTransparency) { _, newValue in
            // Honor the system "Reduce Transparency" accessibility preference by
            // auto-enabling Dim Mode. Does not auto-disable — user toggle wins.
            if newValue && !themeManager.dimModeEnabled {
                themeManager.setDimMode(true)
            }
        }
        .task {
            // Apply system preference on first launch (in case it was on before the app ran).
            if systemReduceTransparency && !themeManager.dimModeEnabled {
                themeManager.setDimMode(true)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            router.switchTab(to: newTab)
            // If the router vetoed the switch (Play tab has unsaved
            // scratchpad — guard is now showing the dialog), `currentTab`
            // is unchanged. Roll the TabView selection back so the bar
            // visually stays on the source tab until the user resolves
            // Save / Discard / Cancel. (See spec §9-2: rollback approach.)
            if router.currentTab != newTab {
                selectedTab = router.currentTab
            } else {
                AnalyticsManager.shared.track(.tabSelected, properties: ["tab": newTab.label])
            }
        }
        .onChange(of: router.currentTab) { _, newTab in
            // Sync programmatic tab changes (e.g. from PostOnboardingWelcomeView,
            // or the guard's Discard/Save advance) back to the TabView selection.
            if selectedTab != newTab {
                selectedTab = newTab
            }
        }
        .confirmationDialog(
            "You have an unsaved scratchpad recording. What would you like to do?",
            isPresented: Binding(
                get: { scratchpadGuard.pending != nil },
                set: { presented in
                    // Dismissal-by-tap-outside resolves as Cancel.
                    if !presented, scratchpadGuard.pending != nil {
                        scratchpadGuard.answer(.cancel)
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Save take") { scratchpadGuard.answer(.save) }
            Button("Discard", role: .destructive) { scratchpadGuard.answer(.discard) }
            Button("Cancel", role: .cancel) { scratchpadGuard.answer(.cancel) }
        }
        .task {
            // Wire the guard onto the router so AppRouter.switchTab(to:)
            // (programmatic switches, deep links) goes through the same
            // path as user-driven TabView changes.
            router.scratchpadGuard = scratchpadGuard
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
                // Explicitly re-pass all environment @Observables. On Mac
                // (Designed for iPad) iOS 26's modal presentation doesn't
                // always inherit the parent scene's environment reliably;
                // re-binding here guarantees OnboardingContainerView's
                // @Environment(AppThemeManager.self) / AuthManager /
                // GamificationService lookups succeed on every platform.
                OnboardingContainerView()
                    .environment(onboardingManager)
                    .environment(themeManager)
                    .environment(AuthManager.shared)
                    .environment(gamificationService)
                    .environment(router)
            }
        )
        .sheet(isPresented: $showPostOnboarding) {
            // Same explicit re-pass for the post-onboarding welcome sheet.
            PostOnboardingWelcomeView()
                .environment(onboardingManager)
                .environment(themeManager)
                .environment(AuthManager.shared)
                .environment(gamificationService)
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
        .environment(AppThemeManager())
        .environment(AppRouter())
}
