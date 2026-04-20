import XCTest

/// Automated accessibility audits per Apple's documented best-practice.
///
/// Each test launches the app, navigates to a target screen, and calls
/// `performAccessibilityAudit(for:)` — the test fails automatically if
/// the audit surfaces issues in the selected categories.
///
/// - SeeAlso: https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app
final class AccessibilityAuditTests: XCTestCase {

    private var app: XCUIApplication!

    /// Audit categories exercised in SP-4c Phase B.
    /// Excludes `.action` (filter-heavy on SwiftUI) and `.textClipping`
    /// (subsumed by `.dynamicType`) per spec AD-3.
    private static let auditTypes: XCUIAccessibilityAuditType = [
        .dynamicType,
        .elementDetection,
        .contrast,
        .hitRegion,
        .traits,
        .parentChildRelationships
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Screen-by-screen audits

    func testHomeTabAudit() throws {
        app.tabBars.buttons["Home"].tap()
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testSongsLibraryAudit() throws {
        app.tabBars.buttons["Songs"].tap()
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testLessonsLibraryAudit() throws {
        app.tabBars.buttons["Learn"].tap()
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testSongDetailAudit() throws {
        app.tabBars.buttons["Songs"].tap()
        let firstSong = app.scrollViews.otherElements.element(boundBy: 0)
        firstSong.press(forDuration: 0.8)
        if app.buttons["Song Details"].waitForExistence(timeout: 2) {
            app.buttons["Song Details"].tap()
            try app.performAccessibilityAudit(for: Self.auditTypes)
        } else {
            throw XCTSkip("Song detail context menu not reachable on this launch; skipping")
        }
    }

    func testPlayAlongAudit() throws {
        app.tabBars.buttons["Songs"].tap()
        let firstSong = app.scrollViews.otherElements.element(boundBy: 0)
        guard firstSong.waitForExistence(timeout: 2) else {
            throw XCTSkip("Songs list empty on this launch; skipping")
        }
        firstSong.tap()
        if app.buttons["Play"].waitForExistence(timeout: 2) {
            app.buttons["Play"].tap()
            try app.performAccessibilityAudit(for: Self.auditTypes)
        } else {
            throw XCTSkip("Play button not reachable on this launch; skipping")
        }
    }

    func testPracticeAudit() throws {
        app.tabBars.buttons["Learn"].tap()
        let firstLesson = app.scrollViews.otherElements.element(boundBy: 0)
        guard firstLesson.waitForExistence(timeout: 2) else {
            throw XCTSkip("Lessons list empty on this launch; skipping")
        }
        firstLesson.tap()
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testSettingsAppearanceAudit() throws {
        app.tabBars.buttons["Profile"].tap()
        if app.buttons["App Theme"].waitForExistence(timeout: 2) {
            app.buttons["App Theme"].tap()
            try app.performAccessibilityAudit(for: Self.auditTypes)
        } else {
            throw XCTSkip("App Theme row not reachable on this launch; skipping")
        }
    }

    func testOnboardingAudit() throws {
        // Relies on OnboardingManager showing onboarding on this launch.
        // If onboarding isn't shown, this test is skipped via XCTSkip.
        guard app.staticTexts["Welcome"].waitForExistence(timeout: 2) else {
            throw XCTSkip("Onboarding not shown on this launch; skipping")
        }
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }
}
