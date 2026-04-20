import Testing
@testable import SurVibe

/// Verifies `ProfileRowID` linear-list nav math.
/// 5 rows: appLanguage=0, midiDevice=1, redoOnboarding=2, theme=3, display=4.
struct ProfileTabFocusTests {
    @Test
    func downFromAppLanguageGoesToMidi() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 0, count: 5, columns: 1
        )
        #expect(result == 1)
    }

    @Test
    func upFromDisplayGoesToTheme() {
        // display = 4, theme = 3
        let result = LibraryFocusNavigator.nextIndex(
            for: .up, currentIndex: 4, count: 5, columns: 1
        )
        #expect(result == 3)
    }

    @Test
    func upFromAppLanguageReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .up, currentIndex: 0, count: 5, columns: 1
        )
        #expect(result == nil)
    }

    @Test
    func downFromDisplayReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 4, count: 5, columns: 1
        )
        #expect(result == nil)
    }
}
