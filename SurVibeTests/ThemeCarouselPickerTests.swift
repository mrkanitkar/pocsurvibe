import SwiftUI
import Testing
@testable import SurVibe

struct ThemeCarouselPickerTests {
    @Test @MainActor func presetsArrayUsesUserVisibleCases() {
        // Carousel shows all 9 first-class themes (5 Bars + 4 Drop variants).
        // Pop Era's 5 era sub-variants are exposed via the inline era picker
        // inside the Pop Era card, not as separate carousel pages.
        #expect(AppThemePreset.userVisibleCases.count == 9)
    }
}
