import os
import SVCore
import SwiftUI

/// Onboarding screen 3: language preference.
///
/// Presents three language cards (Hindi, Marathi, English) so the user
/// can choose their preferred app language. Each card shows the native
/// script name prominently with the English name below.
///
/// Navigation chrome (Next / Back / Skip) is handled by the parent
/// container — this view only manages the language preference state.
struct OnboardingLanguageView: View {
    // MARK: - Logger

    private static let logger = Logger.survibe(category: "OnboardingLanguage")

    // MARK: - Properties

    @Environment(OnboardingManager.self) private var onboardingManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            headerSection

            VStack(spacing: 16) {
                ForEach(OnboardingLanguage.allCases) { language in
                    languageCard(for: language)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 32)
        .onAppear { Self.logger.info("Onboarding screen appeared: Language") }
    }

    // MARK: - Subviews

    /// Title and subtitle for the language selection screen.
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Choose your language")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("You can change this anytime in Settings")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    /// A selectable card representing a single language option.
    ///
    /// - Parameter language: The language option this card represents.
    /// - Returns: A styled card with native script name, English name, and selection state.
    private func languageCard(for language: OnboardingLanguage) -> some View {
        let isSelected = onboardingManager.preferredLanguageCode == language.code
        let fillColor: Color = isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground)
        let strokeColor: Color = isSelected ? Color.accentColor : .clear

        return Button {
            if reduceMotion {
                onboardingManager.preferredLanguageCode = language.code
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    onboardingManager.preferredLanguageCode = language.code
                }
            }
        } label: {
            languageCardLabel(language: language, isSelected: isSelected)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(fillColor))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(strokeColor, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(language.englishName), \(language.nativeName)"))
        .accessibilityHint(isSelected ? Text("Currently selected") : Text("Double tap to select"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Label content for a language card, extracted to help the compiler type-check.
    ///
    /// - Parameters:
    ///   - language: The language option to display.
    ///   - isSelected: Whether this card is currently selected.
    /// - Returns: The card's interior layout.
    private func languageCardLabel(language: OnboardingLanguage, isSelected: Bool) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: language.nativeName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(verbatim: language.englishName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Supporting Types

/// Represents a language option available during onboarding.
///
/// This is a lightweight value type used only by `OnboardingLanguageView`.
/// The full 23-language list is handled by `LanguageSelectorView` in Settings.
private enum OnboardingLanguage: String, CaseIterable, Identifiable {
    case hindi
    case marathi
    case english

    /// Unique identifier for `ForEach`.
    var id: String { rawValue }

    /// ISO 639-1 language code stored in `OnboardingManager.preferredLanguageCode`.
    var code: String {
        switch self {
        case .hindi: "hi"
        case .marathi: "mr"
        case .english: "en"
        }
    }

    /// Native script name displayed prominently on the card.
    var nativeName: String {
        switch self {
        case .hindi: "\u{0939}\u{093F}\u{0928}\u{094D}\u{0926}\u{0940}"
        case .marathi: "\u{092E}\u{0930}\u{093E}\u{0920}\u{0940}"
        case .english: "English"
        }
    }

    /// English name displayed below the native name.
    var englishName: String {
        switch self {
        case .hindi: "Hindi"
        case .marathi: "Marathi"
        case .english: "English"
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingLanguageView()
        .environment(OnboardingManager())
}
