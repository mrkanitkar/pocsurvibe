import os
import SVCore
import SwiftUI

/// The full-screen onboarding flow container.
///
/// Wraps the four onboarding screens (SkillLevel, DoorSelector,
/// NotationPreference, Language) in a paged `TabView` with custom
/// navigation chrome: progress dots, Skip button, and Next / Get Started button.
///
/// Presented as a `.fullScreenCover` from `ContentView` when the user
/// has not yet completed onboarding.
struct OnboardingContainerView: View {
    // MARK: - Logger

    private static let logger = Logger.survibe(category: "OnboardingContainer")

    // MARK: - Properties

    @Environment(OnboardingManager.self) private var onboardingManager
    @Environment(AppThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Total number of onboarding screens.
    private let totalScreens = 4

    // MARK: - Body

    var body: some View {
        @Bindable var manager = onboardingManager

        VStack(spacing: 0) {
            // Top bar: progress dots + skip
            topBar

            // Paged screens
            TabView(selection: $manager.currentScreen) {
                SkillLevelView()
                    .tag(0)

                DoorSelectorView()
                    .tag(1)

                NotationPreferenceView()
                    .tag(2)

                OnboardingLanguageView()
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: onboardingManager.currentScreen)

            // Bottom navigation
            bottomBar
        }
        .background(
            LinearGradient(
                colors: themeManager.resolved.backgroundGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .onAppear { Self.logger.info("Onboarding screen appeared: Container") }
        .onChange(of: onboardingManager.currentScreen) { _, newValue in
            AnalyticsManager.shared.track(
                .onboardingScreenViewed,
                properties: ["screen": newValue]
            )
        }
    }

    // MARK: - Subviews

    /// Top bar with progress dots and skip button.
    private var topBar: some View {
        HStack {
            // Spacer to balance the skip button width
            Color.clear.frame(width: 60, height: 1)

            Spacer()

            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<totalScreens, id: \.self) { index in
                    Circle()
                        .fill(index == onboardingManager.currentScreen
                              ? themeManager.resolved.accentColor
                              : themeManager.resolved.dividerColor)
                        .frame(width: 8, height: 8)
                        .scaleEffect(index == onboardingManager.currentScreen ? 1.2 : 1.0)
                        .animation(
                            reduceMotion ? .none : .easeInOut(duration: 0.2),
                            value: onboardingManager.currentScreen
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Step \(onboardingManager.currentScreen + 1) of \(totalScreens)"))

            Spacer()

            // Skip button
            Button {
                onboardingManager.skipAll()
            } label: {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60)
            .accessibilityLabel(Text("Skip onboarding"))
            .accessibilityHint(Text("Double tap to skip remaining screens and use default settings"))
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    /// Bottom bar with Back and Next/Get Started buttons.
    private var bottomBar: some View {
        HStack {
            // Back button — hidden on first screen
            if onboardingManager.currentScreen > 0 {
                Button {
                    onboardingManager.previousScreen()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .accessibilityHidden(true)
                        Text("Back")
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text("Back"))
                .accessibilityHint(Text("Double tap to go to the previous screen"))
            } else {
                // Invisible spacer to keep layout balanced
                Color.clear.frame(width: 80, height: 1)
            }

            Spacer()

            // Next / Get Started button
            Button {
                if onboardingManager.currentScreen == totalScreens - 1 {
                    onboardingManager.completeOnboarding()
                } else {
                    onboardingManager.nextScreen()
                }
            } label: {
                Text(onboardingManager.currentScreen == totalScreens - 1 ? "Get Started" : "Next")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(nextButtonDisabled
                                  ? themeManager.resolved.accentColor.opacity(0.4)
                                  : themeManager.resolved.accentColor)
                    )
            }
            .disabled(nextButtonDisabled)
            .accessibilityLabel(
                Text(onboardingManager.currentScreen == totalScreens - 1 ? "Get Started" : "Next")
            )
            .accessibilityHint(
                Text(onboardingManager.currentScreen == totalScreens - 1
                     ? "Double tap to complete onboarding and start using the app"
                     : "Double tap to go to the next screen")
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(themeManager.resolved.cardBackgroundColor)
    }

    // MARK: - Private Methods

    /// Whether the Next/Get Started button should be disabled.
    ///
    /// Screen 1 (DoorSelector) requires at least 1 door selected.
    /// All other screens have valid defaults.
    private var nextButtonDisabled: Bool {
        if onboardingManager.currentScreen == 1 {
            return onboardingManager.preferredDoors.isEmpty
        }
        return false
    }
}

// MARK: - Preview

#Preview {
    OnboardingContainerView()
        .environment(OnboardingManager())
        .environment(AppThemeManager())
}
