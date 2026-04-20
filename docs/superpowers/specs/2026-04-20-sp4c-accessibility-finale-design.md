# SP-4c — Accessibility Finale (Design Spec)

> Sub-project: SP-4c
> Date: 2026-04-20
> Predecessor: SP-4b (`sp-4b-accessibility-remainder @ ce695b9`, merge `8770217`)
> Successors: SP-4d (Live Activity), SP-4e (Pencil annotation)
> Audit items covered: 4 SP-4b §6 deferrals + VoiceOver sweep (per SP-4 upcoming block)

## 1. Purpose

Close the accessibility layer of the SP-4 umbrella:
- Ship the 4 focus + grid polish items deferred from SP-4b §6.
- Perform a full-app accessibility audit using Apple's documented best-practice: XCUITest-driven `performAccessibilityAudit(for:)` rather than manual file-by-file inspection.

After SP-4c lands, the three remaining SP-4 items (P1-2 Live Activity, P1-4 Pencil) split into dedicated SP-4d / SP-4e sub-projects with their own specs.

## 2. Reference grounding (verified 2026-04-20)

- **Apple doc "Performing accessibility audits for your app"**: recommends XCUITest automation via `performAccessibilityAudit(for:_:)` on `XCUIApplication`. Test fails automatically if audit issues are found. Covers 9 categories: element description, hit region, contrast, element detection, text clipping, traits, Dynamic Type, hierarchy, action.
- **`FocusState`** (SwiftUI): focus moves programmatically via wrapped-value assignment (SP-4b precedent).
- **`onKeyPress(.escape)`**: iOS 17+, available on iOS 26 unconditionally.
- **`GeometryReader`**: reports proposed size; combined with `.adaptive(minimum:)` grid layout it lets us match SwiftUI's own column computation.
- **Rang color tokens** (SP-4a): `rangRightHand`, `rangLeftHand`, `rangBothHands` already WCAG AA-verified per SP-4a §9.

## 3. Scope

### 3.1 Phase A — Focus + grid polish

Five items, independent edits, same branch.

#### 3.1.1 Focus-ring custom styling on library cards

**Files:** `SurVibe/Navigation/FocusRingModifier.swift` (new), `LessonLibraryView.swift`, `SongLibraryView.swift`.

Reusable `ViewModifier` applies a 3pt stroke in `themeManager.resolved.accentColor` when the card's `id` matches the focused `@FocusState`. Respects `@Environment(\.accessibilityReduceMotion)` — no animated ring transitions if reduce-motion is on.

```swift
struct FocusRingModifier<ID: Hashable>: ViewModifier {
    let itemID: ID
    let focusedID: ID?
    let accent: Color

    func body(content: Content) -> some View {
        content.overlay {
            if focusedID == itemID {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(accent, lineWidth: 3)
            }
        }
    }
}
```

Apply to each card: `.modifier(FocusRingModifier(itemID: song.id, focusedID: focusedSongID, accent: themeManager.resolved.accentColor))`.

#### 3.1.2 Escape-to-clear-focus on library cards

Append to each library card's `.onKeyPress` chain:

```swift
.onKeyPress(.escape) {
    focusedSongID = nil
    return .handled
}
```

Same for `focusedLessonID` in `LessonLibraryView`.

#### 3.1.3 HomeTab DoorCard `@FocusState` + arrow + Return

**File:** `SurVibe/HomeTab.swift`.

Add `@FocusState private var focusedDoorID: DoorID?` where `DoorID` is the existing enum/hashable identity for the 4 doors (Play, Practice, Learn, Streak).

Apply to each `DoorCard`:
- `.focused($focusedDoorID, equals: door.id)`
- `.onKeyPress(.return) { door.action(); return .handled }`
- `.onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow])` using `LibraryFocusNavigator` with the right column count (typically 2×2 grid).
- `FocusRingModifier` for the ring

`.onAppear` primes initial focus on the first door (guarded on `focusedDoorID == nil`).

#### 3.1.4 ProfileTab rows `@FocusState` + arrow + Return

**File:** `SurVibe/ProfileTab.swift` (lines 243, 257, 269, 288, 304 already have `.hoverEffect` on 5 rows).

Add `@FocusState private var focusedRowID: ProfileRowID?` where `ProfileRowID` is a new enum with 5 cases covering the existing rows (Display, Themes, Debug, Feature Flags, About — actual names verified at plan-time).

Apply to each row:
- `.focused($focusedRowID, equals: .displayRow)` etc.
- `.onKeyPress(.return) { row.action(); return .handled }`
- `.onKeyPress(keys: [.upArrow, .downArrow])` using `LibraryFocusNavigator` with `columns: 1` (list).
- `FocusRingModifier` for the ring

`.onAppear` primes initial focus on the first row.

#### 3.1.5 GeometryReader dynamic column count for Songs grid

**File:** `SurVibe/Songs/SongLibraryView.swift`.

Replace `private static let gridColumns = 2` with a computed property read from GeometryReader-measured width:

```swift
@State private var gridColumns: Int = 2

// In songGrid body:
ScrollView {
    GeometryReader { proxy in
        Color.clear
            .onAppear { gridColumns = Self.columnCount(for: proxy.size.width) }
            .onChange(of: proxy.size.width) { _, new in gridColumns = Self.columnCount(for: new) }
    }
    .frame(height: 0)
    LazyVGrid(columns: gridColumnArray(count: gridColumns), spacing: 16) { /* ... */ }
}

private static func columnCount(for width: CGFloat) -> Int {
    // Empirical breakpoints validated against iPhone / iPad portrait / iPad landscape:
    switch width {
    case ..<700: return 2   // iPhone all sizes + split iPad regular
    case 700..<1000: return 3   // iPad portrait, iPad landscape split
    default: return 4   // iPad Pro landscape, Mac
    }
}

private static func gridColumnArray(count: Int) -> [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
}
```

Pass `gridColumns` to both:
- Grid layout (`gridColumnArray(count: gridColumns)`)
- `LibraryFocusNavigator.nextIndex(..., columns: gridColumns)` in `moveFocus`

Now the arrow-key grid math matches the rendered layout at any width.

### 3.2 Phase B — XCUITest accessibility audit

**New file:** `SurVibeUITests/AccessibilityAuditTests.swift`.

Structure:

```swift
import XCTest

/// Automated accessibility audits per Apple's documented best-practice.
/// Each test launches the app, navigates to a target screen, and calls
/// `performAccessibilityAudit` — the test fails automatically if issues surface.
///
/// - SeeAlso: https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app
final class AccessibilityAuditTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITest", "1"]
        app.launch()
    }

    /// Audits Home tab (DoorCards grid).
    func testHomeTab() throws {
        app.tabBars.buttons["Home"].tap()
        try app.performAccessibilityAudit(
            for: [.dynamicType, .elementDetection, .contrast, .hitRegion, .traits, .parentChildRelationships]
        )
    }

    /// Audits Songs library.
    func testSongsLibrary() throws {
        app.tabBars.buttons["Songs"].tap()
        try app.performAccessibilityAudit(
            for: [.dynamicType, .elementDetection, .contrast, .hitRegion, .traits, .parentChildRelationships]
        )
    }

    // + 6 more tests: Lessons library, Song detail, Play-along, Practice,
    //   Settings → Appearance, Onboarding flow step 1
}
```

Audit types included (6 of Apple's 9, selected for SurVibe relevance):
- `.dynamicType` — critical given 22-language Hindi/Urdu/Marathi etc. text
- `.elementDetection` — verifies Devanagari + Sargam grouping
- `.contrast` — Rang colors must pass WCAG AA on every surface
- `.hitRegion` — piano keys, nav buttons must be ≥44pt
- `.traits` — buttons declared as buttons, headers as headers
- `.parentChildRelationships` — notation + lesson card hierarchies

Excluded:
- `.action` — noisy on SwiftUI-generated accessibility actions; can enable in follow-up.
- `.textClipping` — redundant with `.dynamicType` (clipping caught by Dynamic Type check).

### 3.3 Iteration loop for Phase B

1. Write all 8 audit tests (structure above, screen-specific navigation body).
2. Run the suite. Expect failures.
3. Each failure surfaces a specific issue (e.g., "Button without accessibility label at `SongCardView.body:47`"). Fix in the identified Swift file.
4. Re-run. Iterate until all 8 tests pass.
5. Fixes likely clustered in: `MicPermissionPrePrompt`, `OnboardingContainerView`, `SargamNoteView` (traits), piano keys (hit-region), secondary-text on Rang-coloured backgrounds (contrast — primary Rang tokens already pass WCAG AA per SP-4a §9; audit flags are expected on *secondary* contrast cases like small greys on tinted cards), `AchievementUnlockToast` (element detection).

## 4. Architecture decisions

### AD-1 — XCUITest audits over manual sweep

Apple's recommendation: automate via `performAccessibilityAudit`. Manual sweep is effort-proportional to file count (~50 files); automated sweep is effort-proportional to *issue* count (typically small-medium on a well-structured SwiftUI app). Automated audits also stay in the codebase as a regression gate.

### AD-2 — Reusable `FocusRingModifier` over inline overlays

Three surfaces (Lessons, Songs, Home) all need the same ring. One generic `ViewModifier` over repeated inline `.overlay`s. Tradeoff: adds one new file but prevents three copies of the same visual styling drifting apart.

### AD-3 — `performAccessibilityAudit` category selection

Apple provides 9 categories; SP-4c uses 6. `.action` deferred (noisy on SwiftUI auto-generated actions — filter-heavy). `.textClipping` omitted (subsumed by `.dynamicType`). All 6 included types are high-signal for SurVibe's Hindi-music + piano UI.

### AD-4 — Dynamic column count uses floor division with minimum 2

Matches SwiftUI's `.adaptive(minimum: 160)` behaviour at common widths. Minimum 2 prevents 1-column degenerate case on very narrow widths (no SurVibe surface should render <300pt in practice, but `max(2, ...)` is defensive).

### AD-5 — No CI wiring for UI tests in SP-4c

XCUITests require a simulator; no CI config changes ship in SP-4c (user can wire to Xcode Cloud or GitHub Actions later). The tests are runnable locally via `xcodebuild test -only-testing:SurVibeUITests/AccessibilityAuditTests`.

### AD-6 — Phase-level commits, not item-level commits

Phase A is 5 independent items → 5 commits (same pattern as SP-4b).
Phase B is fix-then-test loops → 1 commit per screen fixed (group by screen, not by audit-issue type).
Total: ~13 commits + merge + tag.

## 5. Testing

### 5.1 Unit tests

Phase A additions:
- `SurVibeTests/HomeTabFocusTests.swift` (new, ~4 tests): 2×2 grid navigation math. Reuses `LibraryFocusNavigator.nextIndex` (no new type).
- `SurVibeTests/ProfileTabFocusTests.swift` (new, ~4 tests): linear 5-row navigation. Same pattern.
- `SurVibeTests/SongGridColumnCountTests.swift` (new, ~5 tests): `SongLibraryView.columnCount(for:)` at iPhone / iPad portrait / iPad landscape / Mac widths.

No new tests for `FocusRingModifier` (pure visual; manual QA sufficient).

### 5.2 XCUITests (Phase B)

8 screens × 1 audit test = 8 new test methods in `AccessibilityAuditTests.swift`. All must pass before merge.

### 5.3 Manual QA (iPad + Magic Keyboard + physical iPhone)

- **Phase A:** arrow keys + focus ring visually correct on Lessons, Songs, Home, Profile. Escape clears focus. Songs grid column count changes on iPad rotation.
- **Phase B:** once audit tests green, sanity-check with real VoiceOver on a physical device. XCUITest audit is necessary but not sufficient (Apple's own doc says "eliminating all audit issues doesn't guarantee a fully accessible app").

### 5.4 Latency regression

`/latency-check` merge gate. UI-only changes. `LatencyContractTests` 3/3 green. p95 delta ≤ 0.5 ms.

## 6. Out of scope → SP-4d, SP-4e, other sub-projects

### Routed to SP-4d

- **P1-2 Live Activity / Dynamic Island** — new `SurVibeWidgets/` target, ActivityKit integration, Dynamic Island leading/trailing. L effort. Requires its own spec (build-config decisions, entitlements, CloudKit integration question).

### Routed to SP-4e

- **P1-4 Apple Pencil annotation on notation** — PKCanvasView overlay on `ScrollingSheetView`, new SwiftData `NotationAnnotation` model, per-(userId, songId) persistence, CloudKit sync. L effort. Requires its own spec (SwiftData model + CloudKit conflict strategy).

### Rejected (decision, not deferral)

| Item | Decision |
|---|---|
| Manual file-by-file VoiceOver sweep | Rejected per AD-1 — Apple's documented path is XCUITest audits. |
| `.action` audit category in Phase B | Deferred per AD-3. Filter-heavy on SwiftUI; revisit if low-hanging. |
| `.textClipping` audit category | Omitted per AD-3 (subsumed by `.dynamicType`). |
| CI wiring for the new UI tests | Out of scope per AD-5; user's call whether to wire to Xcode Cloud or GitHub Actions in a follow-up. |

## 7. Non-goals

- No audio-path changes.
- No coordinator / ViewModel changes.
- No new cross-package dependencies.
- No new analytics events.
- No SwiftData model changes (SP-4e handles annotation persistence).
- No new localisation strings (audit-surfaced fixes may add accessibility labels; those get extracted like any other string).
- No new Xcode target (SP-4d adds the Widget target).

## 8. Risks

| Risk | Mitigation |
|---|---|
| XCUITest audits find a large fix backlog (>20 issues) and Phase B blows past 4 days | Phase B commits per-screen; if any single screen balloons, we can split that screen's fixes into SP-4c-addendum and ship the rest. Explicit escape hatch in plan. |
| `performAccessibilityAudit` false positives on 3rd-party AudioKit views | Filter via `performAccessibilityAudit(for:_:)`'s `_:` closure to ignore specific issues with documented justification. Each ignored issue must have a comment explaining why. |
| Focus ring overlay interferes with existing `.hoverEffect` modifier | Test manually; if visual conflict, `.hoverEffect(.lift)` + ring is fine (different pointer vs focus semantics). |
| Dynamic column count changes grid layout mid-scroll on iPad rotation | `.animation(.default, value: gridColumns)` on the grid, respects `@Environment(\.accessibilityReduceMotion)` guard. |
| Simulator contention during XCUITest runs (seen during SP-4b) | Use `xcrun simctl erase` before test runs; run tests after killing any stale xcodebuild processes. Same mitigation as SP-4b. |

## 9. Acceptance criteria

- ✅ Phase A: 13 unit tests pass (4 HomeTabFocus + 4 ProfileTabFocus + 5 SongGridColumnCount, plus existing 8 LibraryFocusNavigator).
- ✅ Phase B: 8 XCUITest audit tests pass on iPad Air 13-inch (M3) simulator.
- ✅ `SongLibraryView` grid layout matches its arrow-key math at every width (2/3/4 columns).
- ✅ Escape clears focus on both library views; focus ring visible in accent colour on focused card.
- ✅ HomeTab DoorCards + ProfileTab rows keyboard-navigable via hardware keyboard.
- ✅ `LatencyContractTests` 3/3 green; p95 delta ≤ 0.5 ms.
- ✅ SVCore 93/93 green.
- ✅ All pre-SP-4c `SurVibeTests` suites still green.
- ✅ Zero banned-pattern introductions (grep clean).
- ✅ `performAccessibilityAudit` reports zero issues (or ignored issues are explicitly commented).

## 10. Tag + merge

- Branch: `feat/sp-4c-accessibility-finale`
- Tag: `sp-4c-accessibility-finale` at last feat commit before merge (matches SP-3d/SP-4b convention).
- Tracker row: SP-4c in `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md` § Status table → mark ✅ shipped.

## 11. File-count budget

**New files (6):**
- `SurVibe/Navigation/FocusRingModifier.swift`
- `SurVibeTests/HomeTabFocusTests.swift`
- `SurVibeTests/ProfileTabFocusTests.swift`
- `SurVibeTests/SongGridColumnCountTests.swift`
- `SurVibeUITests/AccessibilityAuditTests.swift`
- (one of the above gets a corresponding `.xcstrings` entry only if a new user-facing string is added)

**Modified files (4 + fixes from Phase B):**
- `SurVibe/HomeTab.swift`
- `SurVibe/ProfileTab.swift`
- `SurVibe/Learn/LessonLibraryView.swift` (focus-ring + escape)
- `SurVibe/Songs/SongLibraryView.swift` (focus-ring + escape + dynamic columns)

Plus unknown number of fixes from Phase B (estimated 5-15 files).

**Estimated totals:** 6 new + 4 core modified + 5-15 audit-fix modified = 15-25 files. Ships as one PR with ~13-15 commits.

---

*Spec author: Claude (Opus 4.7). Reviewed by: [pending — user review gate after spec-self-review].*
