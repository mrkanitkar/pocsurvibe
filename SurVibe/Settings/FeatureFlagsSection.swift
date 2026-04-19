#if DEBUG
import SVCore
import SwiftUI

/// Toggle list for every `FeatureFlag`. Used inside `SettingsView`'s Debug
/// section. `FeatureFlagStore` is `@Observable`, so SwiftUI re-renders the
/// toggles automatically on flag changes.
///
/// Never shown in Release builds.
struct FeatureFlagsSection: View {
    var store: FeatureFlagStore = .shared

    var body: some View {
        Section("Feature flags") {
            ForEach(FeatureFlag.allCases, id: \.self) { flag in
                Toggle(flag.rawValue, isOn: Binding(
                    get: { store.isEnabled(flag) },
                    set: { store.setEnabled(flag, $0) }
                ))
            }
        }
    }
}

#Preview {
    Form { FeatureFlagsSection() }
}
#endif
