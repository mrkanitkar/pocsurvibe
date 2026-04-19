import SwiftUI

/// A preview card displaying a single theme's visual identity in the carousel.
///
/// Shows a mini representation of the theme: background gradient, accent color
/// swatch, SF Symbol icon, display name, and subtitle. An active-theme
/// checkmark overlay appears when this card matches the currently applied theme.
///
/// Designed for use inside `ThemeCarouselPicker`'s paged `TabView`.
/// Card dimensions are approximately 280 x 400 pt to fit comfortably
/// within a single carousel page with surrounding padding.
struct ThemePreviewCard: View {
    // MARK: - Properties

    /// The theme preset this card represents.
    let preset: AppThemePreset

    /// Whether this card's preset is the currently active theme.
    let isActive: Bool

    /// Callback invoked when the user taps this card.
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                VStack(spacing: 0) {
                    gradientPreview
                    detailFooter
                }
                .frame(width: 280, height: 400)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(activeRing)
                .overlay(alignment: .topTrailing) { checkmarkBadge }
                .glassEffect(.regular)
                .shadow(
                    color: isActive ? preset.accentColor.opacity(0.35) : .black.opacity(0.15),
                    radius: isActive ? 16 : 8,
                    y: isActive ? 6 : 4
                )
            }
            .buttonStyle(.plain)
            .hoverEffect(.automatic)
            .accessibilityLabel("\(preset.displayName) theme")
            .accessibilityHint(
                isActive
                    ? "Currently active theme. \(preset.subtitle)."
                    : "Double tap to apply \(preset.displayName) theme. \(preset.subtitle)."
            )
            .accessibilityAddTraits(isActive ? .isSelected : [])

            if preset == .popEra && isActive {
                PopEraSwatchRow()
            }
        }
    }

    // MARK: - Subviews

    /// Gradient background area with the theme's SF Symbol icon centered.
    private var gradientPreview: some View {
        ZStack {
            LinearGradient(
                colors: preset.backgroundGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Accent color swatch circle behind the icon
            Circle()
                .fill(preset.accentColor.opacity(0.25))
                .frame(width: 100, height: 100)

            Image(systemName: preset.iconName)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(preset.accentColor)
                .accessibilityHidden(true)
        }
        .frame(height: 280)
    }

    /// Footer area showing theme name and subtitle.
    private var detailFooter: some View {
        VStack(spacing: 6) {
            Text(verbatim: preset.displayName)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(verbatim: preset.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    /// Highlighted ring drawn around the card when this preset is active.
    private var activeRing: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(
                preset.accentColor,
                lineWidth: isActive ? 3 : 0
            )
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: isActive)
    }

    /// Checkmark badge shown in the top-trailing corner when active.
    @ViewBuilder
    private var checkmarkBadge: some View {
        if isActive {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.white, preset.accentColor)
                .padding(12)
                .accessibilityHidden(true)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Pop Era Swatch Row

/// Row of five circular swatches representing the Pop Era sub-themes.
///
/// Shown beneath the `ThemePreviewCard` only when the card represents the
/// Pop Era preset AND is the currently active theme. Tapping a swatch
/// switches the active era via `AppThemeManager.setEra(_:)`. The selected
/// era is indicated with a white stroke ring.
private struct PopEraSwatchRow: View {
    @Environment(AppThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: 12) {
            ForEach(PopEra.allCases, id: \.self) { era in
                Button {
                    themeManager.setEra(era)
                } label: {
                    ZStack {
                        Circle()
                            .fill(AppThemePreset.popEra.eraAccentColor(for: era))
                            .frame(width: 32, height: 32)
                        if themeManager.popEra == era {
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 32, height: 32)
                        }
                    }
                }
                .accessibilityLabel("\(era.displayName) era")
                .accessibilityAddTraits(themeManager.popEra == era ? .isSelected : [])
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - Preview

#Preview("Active Card") {
    ThemePreviewCard(
        preset: .sargamGlass,
        isActive: true,
        onSelect: {}
    )
    .padding()
}

#Preview("Inactive Card") {
    ThemePreviewCard(
        preset: .neonRhythm,
        isActive: false,
        onSelect: {}
    )
    .padding()
}
