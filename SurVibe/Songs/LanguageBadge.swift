import SVCore
import SwiftUI

/// A small badge displaying a song's language with a flag indicator.
///
/// Maps the ISO 639-1 language code to a display name and flag emoji.
///
/// Usage:
/// ```swift
/// LanguageBadge(languageCode: song.language)
/// ```
struct LanguageBadge: View {
    // MARK: - Properties

    /// The ISO 639-1 language code (e.g., "hi", "mr", "en").
    let languageCode: String

    @Environment(AppThemeManager.self) private var themeManager

    // MARK: - Body

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: flag)
                .font(.caption2)
                .accessibilityHidden(true)

            Text(verbatim: displayName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(themeManager.resolved.badgeTextColor)
        .background(
            Capsule()
                .fill(themeManager.resolved.nestedSurfaceColor)
        )
        .accessibilityLabel(Text("Language: \(displayName)"))
    }

    // MARK: - Private Methods

    /// Display name for the language code.
    private var displayName: String {
        switch languageCode {
        case "hi": "Hindi"
        case "mr": "Marathi"
        case "en": "English"
        default: languageCode.uppercased()
        }
    }

    /// Flag emoji for the language code.
    private var flag: String {
        switch languageCode {
        case "hi", "mr": "\u{1F1EE}\u{1F1F3}"  // 🇮🇳
        case "en": "\u{1F1EC}\u{1F1E7}"          // 🇬🇧
        default: "\u{1F310}"                      // 🌐
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 8) {
        LanguageBadge(languageCode: "hi")
        LanguageBadge(languageCode: "mr")
        LanguageBadge(languageCode: "en")
    }
    .padding()
    .environment(AppThemeManager())
}
