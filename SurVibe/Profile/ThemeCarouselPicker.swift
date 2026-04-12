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

    /// All available theme presets in display order.
    private let presets = AppThemePreset.allCases

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            themeCarousel
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
