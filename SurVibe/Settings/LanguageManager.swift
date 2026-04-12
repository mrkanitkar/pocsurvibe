import Foundation
import os
import SVCore

/// Manages the user's preferred app language via the `AppleLanguages` UserDefaults key.
///
/// Setting `AppleLanguages` overrides `Locale.current` and `Bundle.preferredLocalizations`
/// on the next app launch, so all `Text()` and `String(localized:)` calls automatically
/// resolve in the chosen language without any code changes.
///
/// The language change requires an app restart to take effect.
@MainActor
@Observable
final class LanguageManager {
    // MARK: - Properties

    private static let logger = Logger.survibe(category: "LanguageManager")

    /// Key used by iOS to determine per-app language override.
    private static let appleLanguagesKey = "AppleLanguages"

    /// Whether a restart is needed because the language was changed this session.
    var pendingRestart: Bool = false

    /// The currently selected language code, or `nil` for system default.
    var selectedLanguageCode: String? {
        guard let languages = UserDefaults.standard.array(forKey: Self.appleLanguagesKey) as? [String],
              let first = languages.first else {
            return nil
        }
        // Only return it if it matches one of our supported languages
        let supported = SupportedLanguage.all.map(\.id)
        return supported.contains(first) ? first : nil
    }

    /// The display-friendly native name of the current language.
    var currentLanguageDisplayName: String {
        guard let code = selectedLanguageCode,
              let language = SupportedLanguage.all.first(where: { $0.id == code }) else {
            return String(localized: "System Default")
        }
        return language.nativeName
    }

    // MARK: - Methods

    /// Set the preferred language. Requires app restart to take effect.
    ///
    /// - Parameter code: The ISO 639 language code, or `nil` to restore system default.
    func setLanguage(_ code: String?) {
        if let code {
            UserDefaults.standard.set([code], forKey: Self.appleLanguagesKey)
            Self.logger.info("Language set to: \(code, privacy: .public)")
        } else {
            UserDefaults.standard.removeObject(forKey: Self.appleLanguagesKey)
            Self.logger.info("Language reset to system default")
        }
        UserDefaults.standard.synchronize()
        pendingRestart = true

        AnalyticsManager.shared.track(
            .languageChanged,
            properties: ["language": code ?? "system"]
        )
    }
}
