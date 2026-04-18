import os
import SVCore
import SwiftUI

/// Onboarding screen 0: skill level selection.
///
/// Presents three selectable cards (Beginner, Intermediate, Advanced)
/// so the user can self-report their piano experience. The selection
/// drives content recommendations for songs and lessons.
///
/// Navigation chrome (Next / Back / Skip) is handled by the parent
/// container — this view only manages the selection state.
struct SkillLevelView: View {
    // MARK: - Logger

    private static let logger = Logger.survibe(category: "OnboardingSkillLevel")

    // MARK: - Properties

    @Environment(OnboardingManager.self) private var onboardingManager
    @Environment(AppThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            headerSection

            VStack(spacing: 16) {
                ForEach(SkillLevel.allCases, id: \.self) { level in
                    skillCard(for: level)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 32)
        .onAppear { Self.logger.info("Onboarding screen appeared: SkillLevel") }
    }

    // MARK: - Subviews

    /// Title and subtitle for the skill selection screen.
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("What's your experience?")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("We'll personalize your learning path")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    /// A selectable card representing a single skill level.
    ///
    /// - Parameter level: The skill level this card represents.
    /// - Returns: A styled card view with icon, label, and description.
    private func skillCard(for level: SkillLevel) -> some View {
        let isSelected = onboardingManager.skillLevel == level
        let accent = themeManager.resolved.accentColor
        let rangColor = RangLevel(rawValue: level.difficulty)?.bodyTextColor ?? accent
        let fillColor: Color = isSelected ? accent.opacity(0.08) : themeManager.resolved.cardBackgroundColor
        let strokeColor: Color = isSelected ? accent : .clear
        let iconBackground: Color = isSelected ? accent : accent.opacity(0.12)
        let iconForeground: Color = isSelected ? .white : rangColor

        return Button {
            if reduceMotion {
                onboardingManager.skillLevel = level
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    onboardingManager.skillLevel = level
                }
            }
        } label: {
            skillCardLabel(
                level: level,
                isSelected: isSelected,
                iconForeground: iconForeground,
                iconBackground: iconBackground
            )
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(fillColor))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(strokeColor, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(level.label). \(level.description)"))
        .accessibilityHint(isSelected ? Text("Currently selected") : Text("Double tap to select"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Label content for a skill card, extracted to help the compiler type-check.
    ///
    /// - Parameters:
    ///   - level: The skill level to display.
    ///   - isSelected: Whether this card is currently selected.
    ///   - iconForeground: Foreground color for the icon.
    ///   - iconBackground: Background color for the icon container.
    /// - Returns: The card's interior layout.
    private func skillCardLabel(
        level: SkillLevel,
        isSelected: Bool,
        iconForeground: Color,
        iconBackground: Color
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: level.icon)
                .font(.title2)
                .foregroundStyle(iconForeground)
                .frame(width: 44, height: 44)
                .background(iconBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: level.label)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(verbatim: level.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(themeManager.resolved.accentColor)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SkillLevelView()
        .environment(OnboardingManager())
        .environment(AppThemeManager())
}
