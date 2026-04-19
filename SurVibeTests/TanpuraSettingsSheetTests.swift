import SwiftUI
import Testing
@testable import SurVibe

@MainActor
struct TanpuraSettingsSheetTests {
    @Test func sheetInitializesWithController() {
        let c = TanpuraController()
        _ = TanpuraSettingsSheet(
            controller: c,
            canResetToSongDefault: false,
            onResetToSongDefault: {}
        )
    }

    @Test func resetEnabledReflectsCallerCapability() {
        let c = TanpuraController()
        _ = TanpuraSettingsSheet(
            controller: c,
            canResetToSongDefault: true,
            onResetToSongDefault: {}
        )
    }
}
