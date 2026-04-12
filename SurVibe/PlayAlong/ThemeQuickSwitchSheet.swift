import SwiftUI

/// A compact bottom sheet for switching themes during play-along.
///
/// Displays all five `AppThemePreset` options as small gradient cards
/// in a horizontal scroll view. The currently active theme shows a
/// highlighted ring. Tapping a card applies the theme immediately
/// and dismisses the sheet.
///
/// ## Presentation
/// Present with `.sheet` and `.presentationDetents([.height(180)])`:
/// ```swift
/// .sheet(isPresented: $showThemeSheet) {
///     ThemeQuickSwitchSheet()
///         .presentationDetents([.height(180)])
/// }
/// ```
struct ThemeQuickSwitchSheet: View {

    // MARK: - Environment

    /// The app-wide theme manager for reading and applying themes.
    @Environment(AppThemeManager.self) private var themeManager

    /// Dismiss action to close the sheet after selection.
    @Environment(\.dismiss) private var dismiss

    /// Whether the user has requested reduced motion in system accessibility settings.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            sheetHandle
            sheetTitle
            themeCarousel
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    // MARK: - Subviews

    /// Visual drag handle at the top of the sheet.
    private var sheetHandle: some View {
        Capsule()
            .fill(Color(.tertiaryLabel))
            .frame(width: 36, height: 5)
            .accessibilityHidden(true)
    }

    /// Title label for the sheet.
    private var sheetTitle: some View {
        Text("Theme")
            .font(.subheadline)
            .fontWeight(.semibold)
            .accessibilityAddTraits(.isHeader)
    }

    /// Horizontal scroll view of theme cards.
    private var themeCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AppThemePreset.allCases, id: \.self) { preset in
                    themeCard(for: preset)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// A single theme card showing the preset's gradient, icon, and name.
    ///
    /// The active preset displays a ring around its card. Tapping applies
    /// the theme and dismisses the sheet.
    ///
    /// - Parameter preset: The theme preset to display.
    /// - Returns: A tappable card view.
    private func themeCard(for preset: AppThemePreset) -> some View {
        let isActive = themeManager.currentPreset == preset

        return Button {
            themeManager.apply(preset)
            dismiss()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Gradient background
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: preset.backgroundGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    // Theme icon
                    Image(systemName: preset.iconName)
                        .font(.title2)
                        .foregroundStyle(preset.accentColor)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isActive ? preset.accentColor : Color.clear,
                            lineWidth: 2.5
                        )
                )
                .shadow(
                    color: isActive ? preset.accentColor.opacity(0.3) : .clear,
                    radius: isActive ? 4 : 0
                )

                // Theme name
                Text(verbatim: preset.displayName)
                    .font(.caption2)
                    .fontWeight(isActive ? .bold : .regular)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.displayName) theme")
        .accessibilityValue(isActive ? "Active" : "")
        .accessibilityHint(
            isActive
                ? "Currently active theme"
                : "Tap to switch to \(preset.displayName) theme"
        )
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview("Theme Quick Switch") {
    ThemeQuickSwitchSheet()
        .environment(AppThemeManager())
        .presentationDetents([.height(180)])
}
