import SwiftUI

/// Appearance settings — Dim Mode and other accessibility-adjacent display toggles.
///
/// Presented via `NavigationLink(value: "display")` from `ProfileTab.appearanceSection`.
/// Reads and writes through `AppThemeManager` which persists state to `UserDefaults`
/// and re-resolves the active theme immediately.
struct AppearanceSettingsView: View {

    // MARK: - Properties

    @Environment(AppThemeManager.self) private var themeManager

    // MARK: - Body

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Dim Mode", isOn: dimModeBinding)
                    .accessibilityLabel("Dim Mode")
                    .accessibilityHint(
                        "Reduces brightness for late-night practice. Honors system Reduce Transparency."
                    )
            }
        }
        .navigationTitle("Display")
    }

    // MARK: - Private

    /// Two-way binding that delegates reads and writes to `AppThemeManager`.
    private var dimModeBinding: Binding<Bool> {
        Binding(
            get: { themeManager.dimModeEnabled },
            set: { themeManager.setDimMode($0) }
        )
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
    .environment(AppThemeManager())
}
