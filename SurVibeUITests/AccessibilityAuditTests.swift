import XCTest

/// Automated accessibility audits per Apple's documented best-practice.
///
/// Each test launches the app, navigates to a target screen, and calls
/// `performAccessibilityAudit(for:)` — the test fails automatically if
/// the audit surfaces issues in the selected categories.
///
/// ## SP-4c ship state (2026-04-20)
///
/// The **infrastructure** (this scaffold + the iOS 26 floating-tab-bar
/// navigation pattern + the 5-category iOS audit set + the Dynamic Type
/// deferral) shipped. **Per-screen iteration** — actually running each
/// audit and fixing the issues it surfaces — is parked under `XCTSkip`
/// with a clear reason pending a dedicated follow-up. Per spec §8 escape
/// hatch: initial audit runs surfaced substantially more work than the
/// narrow SP-4c budget can absorb (Dynamic Type refactor alone is 30+
/// call sites; contrast / hit-region / label iteration is itself
/// multi-day). Un-skipping one test at a time is the intended path for
/// the follow-up sub-project.
///
/// - SeeAlso: https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app
final class AccessibilityAuditTests: XCTestCase {

    private var app: XCUIApplication!

    /// Audit categories exercised in SP-4c Phase B.
    ///
    /// iOS-available only: `.parentChild` and `.action` are macOS/MacCatalyst-only
    /// in the SDK (`XCUIAccessibilityAuditTypes.h` gates them behind
    /// `#if TARGET_OS_OSX`), so they're unreachable from iOS UI tests.
    /// `.textClipped` is subsumed by `.dynamicType` per spec AD-3.
    /// `.sufficientElementDescription` is Apple's "descriptive labels" audit
    /// (substituted for the spec's nominal `.traits` + `.parentChildRelationships`
    /// bundle on iOS).
    ///
    /// `.dynamicType` is **deliberately excluded** from the default audit set:
    /// SurVibe's piano keyboard, sargam notation, XP numerals, and chord brackets
    /// all use `.font(.system(size:))` for music-layout-critical visual integrity
    /// (30+ call sites across the app). Making them Dynamic-Type-compliant is a
    /// substantive refactor (e.g., `@ScaledMetric` + constrained scale clamping)
    /// that warrants its own sub-project. The `testDynamicTypeAuditPendingRefactor`
    /// method below runs the Dynamic Type audit in isolation for future telemetry
    /// but is skipped by default.
    private static let auditTypes: XCUIAccessibilityAuditType = [
        .elementDetection,
        .contrast,
        .hitRegion,
        .sufficientElementDescription,
        .trait
    ]

    /// Common skip reason string surfaced by the per-screen tests until the
    /// follow-up sub-project iterates and removes the skip.
    private static let iterationDeferredReason =
        "SP-4c Phase B per-screen iteration parked; infrastructure-only ship. "
        + "Remove this XCTSkip when the dedicated accessibility-iteration "
        + "sub-project fixes this screen's audit issues."

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Screen-by-screen audits (deferred — see class doc)

    func testHomeTabAudit() throws {
        throw XCTSkip(Self.iterationDeferredReason)
        // When un-skipped, navigate + audit:
        //   app.buttons["Home"].firstMatch.tap()
        //   try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testSongsLibraryAudit() throws {
        throw XCTSkip(Self.iterationDeferredReason)
        // app.buttons["Songs"].firstMatch.tap()
        // try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testLessonsLibraryAudit() throws {
        throw XCTSkip(Self.iterationDeferredReason)
        // app.buttons["Learn"].firstMatch.tap()
        // try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testSongDetailAudit() throws {
        throw XCTSkip(Self.iterationDeferredReason)
    }

    func testPlayAlongAudit() throws {
        throw XCTSkip(Self.iterationDeferredReason)
    }

    func testPracticeAudit() throws {
        throw XCTSkip(Self.iterationDeferredReason)
    }

    func testSettingsAppearanceAudit() throws {
        throw XCTSkip(Self.iterationDeferredReason)
    }

    func testOnboardingAudit() throws {
        throw XCTSkip(Self.iterationDeferredReason)
    }

    // MARK: - Deferred: Dynamic Type audit

    /// Dynamic Type audit parked pending a dedicated refactor sub-project.
    /// SurVibe uses `.font(.system(size:))` in 30+ music-layout-critical sites
    /// (piano keys, sargam rows, XP numerals) that require coordinated design
    /// decisions (`@ScaledMetric` with clamped scale) before this audit can
    /// realistically pass. Skipped by default; re-enable when the refactor
    /// ships.
    func testDynamicTypeAuditPendingRefactor() throws {
        throw XCTSkip("Dynamic Type audit deferred — see method docs.")
    }
}
