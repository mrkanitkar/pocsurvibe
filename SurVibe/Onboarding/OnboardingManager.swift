import SVCore
import SwiftUI
import os.log

/// Manages the 4-screen onboarding flow state and user preference persistence.
///
/// Tracks the current screen, stores user selections (skill level, doors,
/// notation preference, language), and persists all choices to @AppStorage.
/// All mutations are @MainActor-isolated for thread-safe UI updates.
///
/// ## Usage
/// ```swift
/// @Environment(OnboardingManager.self) private var onboarding
/// ```
@Observable
@MainActor
final class OnboardingManager {
    // MARK: - Properties

    /// Current onboarding screen index (0-3).
    var currentScreen: Int = 0

    /// User's selected skill level.
    var skillLevel: SkillLevel = .intermediate

    /// User's preferred feature doors (1-3 selections).
    var preferredDoors: Set<OnboardingDoorType> = [.songs, .learn]

    /// User's notation display preference.
    var notationPreference: NotationDisplayMode = .sargam

    /// User's preferred language code (ISO 639-1).
    var preferredLanguageCode: String = "en"

    // MARK: - Onboarding Completion

    /// Whether the user has completed onboarding.
    ///
    /// This is the SwiftUI-observed property that drives the fullScreenCover
    /// dismiss in ContentView. It is synchronized with `@AppStorage` for
    /// cross-session persistence, but kept as a plain `var` so `@Observable`
    /// tracks mutations and notifies SwiftUI.
    var isOnboardingComplete: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
        didSet {
            UserDefaults.standard.set(isOnboardingComplete, forKey: "hasCompletedOnboarding")
        }
    }

    // MARK: - AppStorage-Backed Persistence

    @ObservationIgnored
    @AppStorage("onboardingSkillLevel")
    private var storedSkillLevel: String = SkillLevel.intermediate.rawValue

    @ObservationIgnored
    @AppStorage("onboardingPreferredDoors")
    private var storedPreferredDoors: Data = Data()

    @ObservationIgnored
    @AppStorage("onboardingNotationPreference")
    private var storedNotationPreference: String = NotationDisplayMode.sargam.rawValue

    @ObservationIgnored
    @AppStorage("onboardingPreferredLanguage")
    private var storedPreferredLanguage: String = "en"

    // MARK: - Private

    /// Logger for onboarding events.
    private static let logger = Logger.survibe(category: "OnboardingManager")

    /// Total number of onboarding screens.
    private let totalScreens = 4

    // MARK: - Initialization

    /// Creates an OnboardingManager and restores any previously saved preferences.
    ///
    /// When the `UITEST_SKIP_ONBOARDING` launch environment key is set to `"1"`,
    /// onboarding is treated as already complete so UI tests can reach the tab bar
    /// without interacting with the onboarding flow.
    init() {
        restoreFromStorage()
        if ProcessInfo.processInfo.environment["UITEST_SKIP_ONBOARDING"] == "1" {
            isOnboardingComplete = true
            Self.logger.info("UI test mode: onboarding skipped via launch environment")
        }
    }

    // MARK: - Navigation Methods

    /// Advance to the next onboarding screen.
    ///
    /// Clamps at the last screen (index 3). Tracks analytics for each screen viewed.
    func nextScreen() {
        let newScreen = min(currentScreen + 1, totalScreens - 1)
        guard newScreen != currentScreen else { return }
        currentScreen = newScreen
        AnalyticsManager.shared.track(
            .onboardingScreenViewed,
            properties: [
                "screen_number": newScreen + 1,
                "screen_name": screenName(for: newScreen),
            ]
        )
    }

    /// Go back to the previous onboarding screen.
    ///
    /// Clamps at the first screen (index 0).
    func previousScreen() {
        currentScreen = max(currentScreen - 1, 0)
    }

    /// Skip onboarding entirely with sensible defaults.
    ///
    /// Applies: intermediate skill, songs + learn + practice doors,
    /// sargam notation, auto-detected language (or English fallback).
    func skipAll() {
        skillLevel = .intermediate
        preferredDoors = [.songs, .learn, .practice]
        notationPreference = .sargam

        // Auto-detect language from device locale
        if let langCode = Locale.current.language.languageCode?.identifier {
            switch langCode {
            case "hi": preferredLanguageCode = "hi"
            case "mr": preferredLanguageCode = "mr"
            default: preferredLanguageCode = "en"
            }
        } else {
            preferredLanguageCode = "en"
        }

        persistToStorage()
        isOnboardingComplete = true

        Self.logger.info("Onboarding skipped with defaults")
        AnalyticsManager.shared.track(
            .onboardingSkipped,
            properties: [
                "skill_level": skillLevel.rawValue,
                "num_doors": preferredDoors.count,
                "notation_preference": notationPreference.rawValue,
                "language": preferredLanguageCode,
            ]
        )
    }

    /// Mark onboarding as complete and persist all user preferences.
    ///
    /// Called when the user finishes the final onboarding screen.
    func completeOnboarding() {
        persistToStorage()
        isOnboardingComplete = true

        Self.logger.info("Onboarding completed")
        AnalyticsManager.shared.track(
            .onboardingCompleted,
            properties: [
                "skill_level": skillLevel.rawValue,
                "num_doors": preferredDoors.count,
                "notation_preference": notationPreference.rawValue,
                "language": preferredLanguageCode,
                "total_screens_viewed": currentScreen + 1,
            ]
        )
    }

    /// Reset onboarding state so it can be shown again.
    ///
    /// Used from Settings -> "Redo Onboarding".
    func resetOnboarding() {
        currentScreen = 0
        isOnboardingComplete = false
        Self.logger.info("Onboarding reset by user")
    }

    // MARK: - Private Methods

    /// Persist current selections to @AppStorage.
    private func persistToStorage() {
        storedSkillLevel = skillLevel.rawValue
        storedNotationPreference = notationPreference.rawValue
        storedPreferredLanguage = preferredLanguageCode

        if let encoded = try? JSONEncoder().encode(Array(preferredDoors)) {
            storedPreferredDoors = encoded
        }
    }

    /// Restore saved values from @AppStorage on init.
    private func restoreFromStorage() {
        if let skill = SkillLevel(rawValue: storedSkillLevel) {
            skillLevel = skill
        }
        if let notation = NotationDisplayMode(rawValue: storedNotationPreference) {
            notationPreference = notation
        }
        preferredLanguageCode = storedPreferredLanguage

        if !storedPreferredDoors.isEmpty,
            let doors = try? JSONDecoder().decode([OnboardingDoorType].self, from: storedPreferredDoors)
        {
            preferredDoors = Set(doors)
        }
    }

    /// Return screen name for analytics tracking.
    ///
    /// - Parameter screen: Screen index (0-3).
    /// - Returns: Human-readable screen name.
    private func screenName(for screen: Int) -> String {
        switch screen {
        case 0: "skill_level"
        case 1: "door_selector"
        case 2: "notation_preference"
        case 3: "language_selector"
        default: "unknown"
        }
    }
}
