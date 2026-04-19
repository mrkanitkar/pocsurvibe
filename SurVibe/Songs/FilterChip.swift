import SVCore
import SwiftUI

/// A reusable capsule-shaped filter chip for the song library filter bar.
///
/// Displays a label with an optional SF Symbol icon. When active, uses
/// the accent color fill; when inactive, uses a secondary background.
///
/// Usage:
/// ```swift
/// FilterChip(label: "Hindi", isActive: true) {
///     toggleLanguageFilter("hi")
/// }
/// ```
struct FilterChip: View {
    // MARK: - Properties

    @Environment(AppThemeManager.self)
    private var themeManager

    /// The text label displayed on the chip.
    let label: String

    /// Optional SF Symbol name shown before the label.
    var icon: String?

    /// Whether this chip is currently active (selected).
    let isActive: Bool

    /// Action performed when the chip is tapped.
    let action: () -> Void

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                        .accessibilityHidden(true)
                }

                Text(label)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isActive ? .white : .primary)
            .background(
                Capsule()
                    .fill(isActive ? themeManager.resolved.accentColor : themeManager.resolved.nestedSurfaceColor)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.automatic)
        .accessibilityLabel(Text(label))
        .accessibilityHint(
            isActive
                ? Text("Active filter. Double tap to remove.")
                : Text("Double tap to apply this filter.")
        )
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Preview

#Preview {
    HStack {
        FilterChip(label: "Hindi", icon: "globe", isActive: true, action: {})
        FilterChip(label: "Beginner", isActive: false, action: {})
        FilterChip(label: "Favorites", icon: "heart.fill", isActive: true, action: {})
    }
    .padding()
}
