import SwiftUI
import Testing
@testable import SurVibe

struct ThemeCarouselPickerTests {
    @Test @MainActor func presetsArrayUsesUserVisibleCases() {
        // Ensure the carousel shows the 5 user-visible themes, not 9 legacy+new
        // (5 because popEra expands inline)
        #expect(AppThemePreset.userVisibleCases.count == 5)
    }
}
