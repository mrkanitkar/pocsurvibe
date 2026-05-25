import XCTest

/// UI tests for the SurVibe main tab bar and navigation.
///
/// All tests disable the onboarding cover by setting
/// `UITEST_SKIP_ONBOARDING=1` in the launch environment, which the app
/// reads via `OnboardingManager` to treat onboarding as complete.
/// Without this, a fullScreenCover blocks every tab bar interaction.
final class SurVibeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    /// Launch the app with onboarding bypassed.
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_SKIP_ONBOARDING"] = "1"
        app.launch()
        return app
    }

    /// Wait for the tab bar to appear (gives the app time to settle after launch).
    @MainActor
    private func waitForTabBar(in app: XCUIApplication) -> Bool {
        app.tabBars.firstMatch.waitForExistence(timeout: 5)
    }

    // MARK: - Tests

    /// D1: App launches and shows 4 tabs: Home, Learn, Songs, Profile.
    @MainActor
    func testAppLaunchesWithFourTabs() throws {
        let app = launchApp()
        XCTAssertTrue(waitForTabBar(in: app), "Tab bar should appear within 5s")

        XCTAssertTrue(app.tabBars.buttons["Home"].exists, "Home tab should exist")
        XCTAssertTrue(app.tabBars.buttons["Learn"].exists, "Learn tab should exist")
        XCTAssertTrue(app.tabBars.buttons["Songs"].exists, "Songs tab should exist")
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists, "Profile tab should exist")
    }

    /// D7: Each tab shows the expected navigation bar title.
    @MainActor
    func testTabNavigation() throws {
        let app = launchApp()
        XCTAssertTrue(waitForTabBar(in: app), "Tab bar should appear within 5s")

        app.tabBars.buttons["Learn"].tap()
        XCTAssertTrue(app.navigationBars["Learn"].waitForExistence(timeout: 3),
                      "Learn tab nav bar should show 'Learn'")

        app.tabBars.buttons["Songs"].tap()
        XCTAssertTrue(app.navigationBars["Songs"].waitForExistence(timeout: 3),
                      "Songs tab nav bar should show 'Songs'")

        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 3),
                      "Profile tab nav bar should show 'Profile'")

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 3),
                      "Home tab nav bar should show 'Home'")
    }

    /// Measures cold-launch time. Not affected by onboarding skip.
    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchEnvironment["UITEST_SKIP_ONBOARDING"] = "1"
            app.launch()
        }
    }
}
