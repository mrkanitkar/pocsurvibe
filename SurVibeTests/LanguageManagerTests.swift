import Foundation
import SVCore
import SwiftUI
import Testing

@testable import SurVibe

@MainActor
struct LanguageManagerTests {
    // MARK: - SupportedLanguage Tests

    @Test func allLanguagesContainsTwentyThreeEntries() {
        #expect(SupportedLanguage.all.count == 23)
    }

    @Test func englishIsIncluded() {
        let english = SupportedLanguage.all.first { $0.id == "en" }
        #expect(english != nil)
        #expect(english?.nativeName == "English")
        #expect(english?.englishName == "English")
    }

    @Test func allNativeNamesAreNonEmpty() {
        for language in SupportedLanguage.all {
            #expect(!language.nativeName.isEmpty, "Native name empty for \(language.id)")
        }
    }

    @Test func allEnglishNamesAreNonEmpty() {
        for language in SupportedLanguage.all {
            #expect(!language.englishName.isEmpty, "English name empty for \(language.id)")
        }
    }

    @Test func allLanguageIdsAreUnique() {
        let ids = SupportedLanguage.all.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count)
    }

    @Test func rtlLanguagesIdentifiedCorrectly() {
        let rtlCodes: Set<String> = ["ur", "ks", "sd"]
        for language in SupportedLanguage.all {
            if rtlCodes.contains(language.id) {
                #expect(
                    language.scriptDirection == .rightToLeft,
                    "\(language.id) should be RTL"
                )
            } else {
                #expect(
                    language.scriptDirection == .leftToRight,
                    "\(language.id) should be LTR"
                )
            }
        }
    }

    @Test func languagesAreSortedByEnglishName() {
        let englishNames = SupportedLanguage.all.map(\.englishName)
        let sorted = englishNames.sorted()
        #expect(englishNames == sorted)
    }

    // MARK: - LanguageManager Tests

    @MainActor
    @Test func setLanguageWritesAppleLanguagesKey() {
        let manager = LanguageManager()
        let testSuite = "AppleLanguages"

        // Set a language
        manager.setLanguage("hi")

        let stored = UserDefaults.standard.array(forKey: testSuite) as? [String]
        #expect(stored == ["hi"])

        // Clean up
        UserDefaults.standard.removeObject(forKey: testSuite)
    }

    @MainActor
    @Test func clearLanguageResetsToSystemDefault() {
        let manager = LanguageManager()

        // Set then clear
        manager.setLanguage("mr")
        manager.setLanguage(nil)

        // After clearing, selectedLanguageCode should return nil (system default)
        // Note: iOS may repopulate AppleLanguages with system defaults,
        // so we test the manager's behavior rather than raw UserDefaults.
        #expect(manager.selectedLanguageCode == nil)
    }

    @MainActor
    @Test func selectedLanguageCodeReadsBackCorrectly() {
        let manager = LanguageManager()

        // Set a known supported language
        manager.setLanguage("ta")
        #expect(manager.selectedLanguageCode == "ta")

        // Clean up
        manager.setLanguage(nil)
    }

    @MainActor
    @Test func setLanguageSetsPendingRestart() {
        let manager = LanguageManager()
        #expect(manager.pendingRestart == false)

        manager.setLanguage("bn")
        #expect(manager.pendingRestart == true)

        // Clean up
        manager.setLanguage(nil)
    }

    @MainActor
    @Test func currentLanguageDisplayNameShowsNativeNameForKnownLanguage() {
        let manager = LanguageManager()

        manager.setLanguage("hi")
        #expect(manager.currentLanguageDisplayName == "हिन्दी")

        // Clean up
        manager.setLanguage(nil)
    }

    // MARK: - Analytics Integration

    @Test func languageChangedEventNameMatchesSpec() {
        // Verify the analytics event raw value matches the PostHog spec
        #expect(AnalyticsEvent.languageChanged.rawValue == "language_changed")
    }

    @MainActor
    @Test func setLanguageFiresAnalyticsWithoutCrash() {
        // AnalyticsManager.isConfigured is false in tests, so the PostHog
        // call is a no-op — but this verifies the full code path executes,
        // including the AnalyticsManager.track(.languageChanged, properties:) call.
        let manager = LanguageManager()
        manager.setLanguage("gu")
        #expect(manager.pendingRestart == true)

        // Clean up
        manager.setLanguage(nil)
    }
}
