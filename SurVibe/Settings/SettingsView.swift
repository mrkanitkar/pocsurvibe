import SVCore
import SwiftUI

/// Top-level Settings surface.
///
/// Consumed by the `Settings { }` scene in `SurVibeApp` (active on macOS as
/// the Preferences window; inert on iOS/iPadOS). Populated progressively:
/// Appearance section lands with SP-4, Privacy section lands with SP-5.
/// The Debug section ships in DEBUG builds only.
struct SettingsView: View {
    var body: some View {
        Form {
            Section("Appearance") {
                Text("Populated in SP-4")
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("Populated in SP-5")
                    .foregroundStyle(.secondary)
            }
            #if DEBUG
            FeatureFlagsSection()
            #endif
        }
        .navigationTitle("Settings")
        .onAppear {
            AnalyticsManager.shared.track(.settingsOpened)
        }
    }
}

#Preview {
    SettingsView()
}
