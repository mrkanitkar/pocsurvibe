import Testing

@testable import SurVibe

@MainActor
@Suite("SettingsView Appearance")
struct SettingsViewAppearanceTests {

    @Test
    func settingsViewConstructs() {
        let view = SettingsView()
        _ = view
        #expect(true)
    }

    @Test
    func appearanceSettingsViewConstructs() {
        let view = AppearanceSettingsView()
        _ = view
        #expect(true)
    }
}
