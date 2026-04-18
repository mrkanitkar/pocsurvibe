import SwiftUI

/// Horizontal swipe carousel for selecting the app's visual theme.
///
/// Displays all `AppThemePreset` cases as full-width paged cards
/// using a `TabView` with `.tabViewStyle(.page)`. The currently
/// active theme shows a highlighted ring and checkmark. Tapping
/// a card applies it immediately with haptic feedback.
///
/// Respects `accessibilityReduceMotion` — disables spring animations
/// when the user prefers reduced motion.
///
/// Navigated to from `ProfileTab` via the "Appearance" settings row.
struct ThemeCarouselPicker: View {
    // MARK: - Properties

    @Environment(AppThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Index of the currently visible page in the carousel.
    @State private var selectedIndex: Int = 0

    /// Trigger value for sensory feedback on theme selection.
    @State private var feedbackTrigger: Bool = false

    // All available theme presets in display order.
    private let presets = AppThemePreset.userVisibleCases

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            themeCarousel
            popEraSwatchRow
            activeThemeLabel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Appearance")
        .sensoryFeedback(.selection, trigger: feedbackTrigger)
        .onAppear {
            syncSelectedIndex()
        }
    }

    // MARK: - Subviews

    /// Paged carousel of theme preview cards.
    private var themeCarousel: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(presets.enumerated()), id: \.offset) { index, preset in
                ThemePreviewCard(
                    preset: preset,
                    isActive: preset == themeManager.currentPreset,
                    onSelect: {
                        applyTheme(preset)
                    }
                )
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: 480)
        .accessibilityLabel("Theme carousel")
        .accessibilityHint("Swipe left or right to browse themes. Tap to select.")
    }

    /// Label showing the name of the currently active theme below the carousel.
    private var activeThemeLabel: some View {
        VStack(spacing: 4) {
            Text("Current Theme")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(verbatim: themeManager.currentPreset.displayName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .animation(reduceMotion ? .none : .spring(), value: themeManager.currentPreset.rawValue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current theme: \(themeManager.currentPreset.displayName)")
    }

    // MARK: - Subviews (continued)

    /// Pop Era sub-theme picker — shown only when the active preset is Pop Era.
    ///
    /// Five circular swatch buttons, one per `PopEra` case. Tapping a swatch
    /// applies the era via `themeManager.setEra(_:)` and persists it.
    @ViewBuilder
    private var popEraSwatchRow: some View {
        if themeManager.currentPreset == .popEra {
            VStack(spacing: 8) {
                Text("Era")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                HStack(spacing: 16) {
                    ForEach(PopEra.allCases, id: \.self) { era in
                        eraSwatch(era)
                    }
                }
            }
            .transition(.scale.combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pop Era selector")
        }
    }

    /// Single circular era swatch button.
    ///
    /// Shows the era's accent color as background with its SF Symbol icon.
    /// A ring indicator marks the active era; a scale spring animates the
    /// active state unless the user prefers reduced motion.
    ///
    /// - Parameter era: The era this swatch represents.
    /// - Returns: A button view for the given era.
    private func eraSwatch(_ era: PopEra) -> some View {
        let isActive = themeManager.popEra == era
        let color = AppThemePreset.popEra.eraAccentColor(for: era)
        return Button {
            applyEra(era)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 44, height: 44)
                    Image(systemName: era.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay(
                    Circle()
                        .stroke(.primary, lineWidth: isActive ? 3 : 0)
                        .padding(-2)
                )
                .scaleEffect(isActive ? 1.08 : 1.0)
                .animation(reduceMotion ? .none : .spring(response: 0.3), value: isActive)

                Text(verbatim: era.displayName)
                    .font(.caption2)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(era.displayName) era")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : [.isButton])
        .accessibilityHint("Activates the \(era.displayName) era accent palette.")
    }

    // MARK: - Private Methods

    /// Apply the selected theme preset via the theme manager.
    ///
    /// Triggers haptic feedback and updates the selected page index.
    ///
    /// - Parameter preset: The theme to apply.
    private func applyTheme(_ preset: AppThemePreset) {
        withAnimation(reduceMotion ? .none : .spring()) {
            themeManager.apply(preset)
            feedbackTrigger.toggle()
        }
    }

    /// Apply the selected Pop Era sub-theme with animation and haptic feedback.
    ///
    /// Wraps `themeManager.setEra(_:)` in a spring animation and toggles
    /// the sensory feedback trigger.
    ///
    /// - Parameter era: The era to apply.
    private func applyEra(_ era: PopEra) {
        withAnimation(reduceMotion ? .none : .spring()) {
            themeManager.setEra(era)
            feedbackTrigger.toggle()
        }
    }

    /// Sync the carousel page index to the currently active theme on appear.
    ///
    /// Ensures the carousel opens to the page showing the active theme
    /// rather than always starting at page 0.
    private func syncSelectedIndex() {
        if let index = presets.firstIndex(of: themeManager.currentPreset) {
            selectedIndex = index
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ThemeCarouselPicker()
    }
    .environment(AppThemeManager())
}
