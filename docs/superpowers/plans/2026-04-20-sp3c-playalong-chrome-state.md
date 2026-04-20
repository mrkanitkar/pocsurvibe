# SP-3c PlayAlongChromeState Extraction — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract chrome visibility state, view/notation modes, theme color holders, and the auto-hide timer (~150 LOC) from `PlayAlongViewModel` into a new `@Observable @MainActor final class PlayAlongChromeState`, with the VM becoming a thinner facade that delegates `viewMode`/`notationMode`/`chromeVisibility`/theme colors through `chrome.X`. View-side inline theme color assignment in `SongPlayAlongView` consolidates into `chrome.updateTheme(themeManager)`.

**Architecture:** `PlayAlongChromeState` owns the UI presentation domain: `chromeVisibility` enum + auto-hide `Task`, `viewMode`, `notationMode`, 7 `@ObservationIgnored` resolved theme colors, and the `summonChrome / hideChrome / resetAutoHide / updateTheme` methods. Public API is the spec §5.3 surface with 5 plan-time deviations locked in spec §12: `latencyPreset` stays on VM (D-SP3c-1), 7 colors stay individual not bundled (D-SP3c-2), `updateTheme(_:)` centralizes view-side resolution (D-SP3c-3), `chromeAutoHideSeconds` becomes `static let autoHideDuration` (D-SP3c-4), zero-dep init (D-SP3c-5).

**Facade pattern:** `PlayAlongViewModel` holds `let chrome = PlayAlongChromeState()`, re-exposes `viewMode`/`notationMode`/`chromeVisibility`/7 theme colors via delegating computed properties so existing 20+ external call sites continue to read `viewModel.viewMode` etc. unchanged. `SongPlayAlongView`'s `.task` blocks at lines 219-225 / 246-249 collapse into `viewModel.chrome.updateTheme(themeManager)` (or `chrome.updateTheme(themeManager)` if accessed via the new coordinator).

**Tech Stack:** Swift 6.2, SwiftUI (iOS 26+), Swift Testing (`@Test`, `#expect`), `@Observable` macro, `@MainActor` isolation, `Task` for auto-hide timer, `@ObservationIgnored` for theme color holders. No SwiftData, no audio, no concurrency boundaries.

**Spec:** [docs/superpowers/specs/2026-04-19-sp3-playalong-vm-split-design.md](../specs/2026-04-19-sp3-playalong-vm-split-design.md) §5.3 + §12 (5 plan-time deviations).

**Tasks:** 7 total. Estimated duration: 1–2 days.

**Hard gates (run after every code-touching task):**
- `LatencyContractTests.featureFlagToggleDoesNotRestartEngine` green.
- `LatencyContractTests.rotationDoesNotRestartAudioEngine` green.
- All 8 pre-existing PlayAlong test suites green: `PlayAlongFullFlowTests`, `PlayAlongIntegrationTests`, `PlayAlongThemeIntegrationTests`, `PlayAlongChromeTests` (regression-critical for this sub-project), `PlayAlongGestureTests`, `ChordScoringIntegrationTests`, `PlayAlongViewModelTests`, `PlayAlongTempoScalingTests`.

**Cross-cutting discipline (enforce via grep scan in Task 7):**
- 0 hits for `UIDevice|UIScreen\.main\.bounds|UIInterfaceOrientation|#if os\(macOS\)|#if os\(iOS\)|\.bottomBar|\.topBarTrailing` on new files.
- No `import UIKit` / `import AppKit` in new files.
- `@Observable @MainActor final class` on PlayAlongChromeState.
- 0 hits for `AudioEngineManager.shared.noteOn` on new files (chrome state never touches audio).

---

## Task 1: Setup — branch off main, capture pre-task footprint

**Files:**
- Append to: `docs/SP-3_baseline.md`

---

- [ ] **Step 1: Verify clean main + branch off**

```bash
git status
git checkout main
git pull origin main
git checkout -b feat/sp-3c-chrome-state
```

Expected: `Your branch is up to date with 'origin/main'.` · `nothing to commit, working tree clean`. New branch `feat/sp-3c-chrome-state` created from `main` HEAD (post-SP-3b merge at `4ca65ae` or beyond).

- [ ] **Step 2: Confirm pre-task latency tests green**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/LatencyContractTests test 2>&1 | tail -15
```

Expected: 3/3 LatencyContractTests pass. If anything fails BEFORE changes, STOP — baseline broken.

- [ ] **Step 3: Capture pre-SP-3c VM footprint**

```bash
wc -l SurVibe/PlayAlong/PlayAlongViewModel.swift SurVibe/PlayAlong/Coordinators/*.swift
```

Expected: `1353 ... PlayAlongViewModel.swift`, `597 ... PlaybackCoordinator.swift`, `124 ... ScoringCoordinator.swift`.

Append to `docs/SP-3_baseline.md`:

```markdown

## SP-3c pre-task snapshot (captured on `feat/sp-3c-chrome-state`)
- `PlayAlongViewModel.swift`: **1,353 lines** (post-SP-3b baseline).
- `PlaybackCoordinator.swift`: 597 lines (unchanged).
- `ScoringCoordinator.swift`: 124 lines (unchanged).
- LatencyContractTests: 3/3 PASS.

## Gate for SP-3c merge
- `PlayAlongViewModel.swift` SHRINKS to **≤ ~1,250 lines** (target: ~150 LOC peeled into PlayAlongChromeState).
- `PlayAlongChromeState.swift` ≈ 150 lines.
- Both `featureFlagToggleDoesNotRestartEngine` + `rotationDoesNotRestartAudioEngine` GREEN.
- All 8 PlayAlong suites GREEN. `PlayAlongChromeTests` is the regression guard.
```

- [ ] **Step 4: Commit baseline snapshot**

```bash
git add -f docs/SP-3_baseline.md
git commit -m "chore(SP-3c): pre-task footprint snapshot on feature branch"
```

Note: `docs/` gitignored → `-f` required.

---

## Task 2: Write failing tests for `PlayAlongChromeState`

TDD: tests fail first. 6 tests covering the spec §6 minimum of 3 plus 3 for the additional surface (viewMode, updateTheme, autoHideDuration constant).

**Files:**
- Create: `SurVibeTests/PlayAlongChromeStateTests.swift`

---

- [ ] **Step 1: Verify available test mocks**

```bash
grep -lE "AppThemeManager\(|MockThemeManager" SurVibeTests/ -r
```

Note whether tests construct `AppThemeManager` directly or use a mock. If `AppThemeManager` requires complex setup (e.g., `@MainActor` init with multiple deps), consider using a real instance with default theme — its `resolved` field returns an `AppThemeDefinition` struct whose color fields are read by `updateTheme`.

- [ ] **Step 2: Create the test file**

Create `SurVibeTests/PlayAlongChromeStateTests.swift`:

```swift
// SurVibeTests/PlayAlongChromeStateTests.swift
import Foundation
import SVCore
import SwiftUI
import Testing
@testable import SurVibe

/// Unit tests for `PlayAlongChromeState` (SP-3c).
///
/// `PlayAlongChromeState` owns chrome visibility, view/notation modes, and
/// resolved theme colors — the UI presentation domain extracted from
/// `PlayAlongViewModel`. No audio, no SwiftData, no concurrency boundaries
/// beyond the auto-hide `Task`.
@MainActor
@Suite("PlayAlongChromeState")
struct PlayAlongChromeStateTests {

    @Test func initialStateIsSummonedAndHasDefaultModes() {
        let chrome = PlayAlongChromeState()

        #expect(chrome.chromeVisibility == .summoned, "Starts summoned so users see controls on first open")
        #expect(chrome.viewMode == .fallingNotes, "Default view mode")
        #expect(chrome.notationMode == .sargam, "Default notation mode")
    }

    @Test func summonChromeShowsItAndStartsAutoHideTimer() async throws {
        let chrome = PlayAlongChromeState()
        chrome.hideChrome()
        #expect(chrome.chromeVisibility == .hidden)

        chrome.summonChrome()
        #expect(chrome.chromeVisibility == .summoned)

        // Auto-hide timer should be scheduled — wait past the constant duration.
        try await Task.sleep(for: .seconds(PlayAlongChromeState.autoHideDuration + 0.5))
        #expect(chrome.chromeVisibility == .hidden, "Auto-hides after autoHideDuration seconds")
    }

    @Test func hideChromeImmediatelyCancelsTimer() {
        let chrome = PlayAlongChromeState()
        chrome.summonChrome()
        chrome.hideChrome()

        #expect(chrome.chromeVisibility == .hidden)
    }

    @Test func resetAutoHideRestartsTimer() async throws {
        let chrome = PlayAlongChromeState()
        chrome.summonChrome()

        // Wait less than autoHideDuration — chrome should still be visible.
        try await Task.sleep(for: .seconds(PlayAlongChromeState.autoHideDuration / 2))
        chrome.resetAutoHide()
        // Wait another half-duration — would have hidden by now WITHOUT reset.
        try await Task.sleep(for: .seconds(PlayAlongChromeState.autoHideDuration / 2 + 0.1))
        #expect(chrome.chromeVisibility == .summoned, "Reset extended the auto-hide window")
    }

    @Test func autoHideDurationConstantIsSixSeconds() {
        // Magic-number elimination per D-SP3c-4.
        #expect(PlayAlongChromeState.autoHideDuration == 6.0)
    }

    @Test func updateThemeResolvesAllSevenColors() async {
        let chrome = PlayAlongChromeState()
        let themeManager = AppThemeManager()  // adjust constructor if needed
        // Apply a known preset so resolved colors are deterministic.
        themeManager.apply(.classical, source: "test")

        chrome.updateTheme(themeManager)

        #expect(chrome.rhColor == themeManager.resolved.rightHandColor)
        #expect(chrome.lhColor == themeManager.resolved.leftHandColor)
        #expect(chrome.chordColor == themeManager.resolved.chordColor)
        #expect(chrome.notationLineColor == themeManager.resolved.notationLineColor)
        #expect(chrome.notationSecondaryColor == themeManager.resolved.notationSecondaryColor)
        #expect(chrome.cardBackgroundColor == themeManager.resolved.cardBackgroundColor)
        #expect(chrome.karaokeBackgroundColor == themeManager.resolved.karaokeBackgroundColor)
    }
}
```

**Notes for the engineer:**
- If `AppThemePreset.classical` doesn't exist, substitute the real first preset case (grep `enum AppThemePreset`).
- If `AppThemeManager()` zero-arg init doesn't work, inspect the real signature and supply the minimum (e.g., a `UserDefaults` instance).
- If `notationSecondaryColor` isn't a field on `AppThemeDefinition.resolved`, the chrome state's color list mirrors the VM's current 7; some fields may map to the same source field. Match the VM's existing inline assignment at [SongPlayAlongView.swift:219-225](SurVibe/PlayAlong/SongPlayAlongView.swift) for the source-field mapping.
- The auto-hide timing tests use real `Task.sleep` — slightly flaky on heavily-loaded CI but consistent with `PlayAlongChromeTests` (the existing suite uses the same pattern).

- [ ] **Step 3: Run the test file — expect compile failure**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/PlayAlongChromeStateTests build-for-testing 2>&1 | tail -15
```

Expected: FAIL with `cannot find 'PlayAlongChromeState' in scope`. Task 3 implements it.

- [ ] **Step 4: Commit**

```bash
git add SurVibeTests/PlayAlongChromeStateTests.swift
git commit -m "test(SurVibe): failing PlayAlongChromeStateTests for SP-3c chrome extraction"
```

---

## Task 3: Implement `PlayAlongChromeState`

Create the coordinator. Modest size (~150 LOC) — single task covers state, init, all methods, and `updateTheme`.

**Files:**
- Create: `SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift`

---

- [ ] **Step 1: Create the file**

Create `SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift`:

```swift
// SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift
import Foundation
import SwiftUI
import os.log

/// Owns the play-along UI presentation state: chrome visibility + auto-hide,
/// view/notation modes, and resolved theme color holders.
///
/// Extracted from `PlayAlongViewModel` in SP-3c. The facade
/// (`PlayAlongViewModel`) holds `let chrome = PlayAlongChromeState()` and
/// re-exposes every owned property as a delegating computed property so
/// existing views/tests continue to read `viewModel.chromeVisibility` etc.
/// unchanged (spec AD-1 facade).
///
/// ## Public surface (spec §5.3 + §12 plan-time deviations)
/// - `chromeVisibility` (read-only) + `summonChrome / hideChrome / resetAutoHide`
///   methods for the auto-hiding control surface.
/// - `viewMode`, `notationMode` (read+write) for the view-mode toggles.
/// - 7 resolved theme color properties (`@ObservationIgnored`, set by
///   `updateTheme`).
/// - `updateTheme(_ themeManager: AppThemeManager)` resolves all 7 colors
///   from the current theme — replaces inline view-side assignment.
///
/// ## Out of scope (per §12 deviations)
/// - `latencyPreset` stays on VM (D-SP3c-1; defers to SP-3d alongside NoteRouter)
/// - Theme colors stay as 7 individual `@ObservationIgnored` properties, not
///   bundled into a struct (D-SP3c-2; preserves "no behavior changes" mandate)
///
/// ## Threading
/// `@MainActor`-isolated. Auto-hide `Task` runs on `@MainActor`.
@Observable
@MainActor
final class PlayAlongChromeState {
    // MARK: - Constants

    /// Seconds of inactivity before chrome auto-hides. Replaces the magic
    /// `6.0` literal that lived on the VM (D-SP3c-4).
    static let autoHideDuration: TimeInterval = 6.0

    // MARK: - Chrome visibility

    /// Whether the PlayAlong toolbar/summoned chrome is visible.
    ///
    /// `.summoned`: toolbar slide-down is visible.
    /// `.hidden`: only persistent chrome (pause dot, mic pill, tanpura pill)
    /// is on screen — notation dominates the view.
    enum ChromeVisibility: Sendable {
        case hidden
        case summoned
    }

    /// Current chrome state. Starts `.summoned` so users see controls on
    /// first open; transitions to `.hidden` after `autoHideDuration` of
    /// inactivity.
    private(set) var chromeVisibility: ChromeVisibility = .summoned

    /// Outstanding auto-hide timer. Cancel when user interacts.
    @ObservationIgnored
    private var chromeAutoHideTask: Task<Void, Never>?

    // MARK: - View modes

    /// Visual display mode (falling notes vs scrolling sheet).
    var viewMode: PlayAlongViewMode = .fallingNotes

    /// Notation label display mode (Sargam, Western, dual, etc.).
    var notationMode: NotationDisplayMode = .sargam

    // MARK: - Resolved theme colors
    //
    // `@ObservationIgnored` per D-SP3c-2: views receive these as `let` parameters
    // at construction time; theme changes mid-play do not propagate (matches
    // pre-SP-3c VM behavior).

    @ObservationIgnored
    var rhColor: Color = .blue
    @ObservationIgnored
    var lhColor: Color = .red
    @ObservationIgnored
    var chordColor: Color = .purple
    @ObservationIgnored
    var notationLineColor: Color = .black
    @ObservationIgnored
    var notationSecondaryColor: Color = .gray
    @ObservationIgnored
    var cardBackgroundColor: Color = .white.opacity(0.9)
    @ObservationIgnored
    var karaokeBackgroundColor: Color = .black.opacity(0.55)

    private static let logger = Logger.survibe(category: "PlayAlongChromeState")

    // MARK: - Initialization

    /// Zero-dependency init (D-SP3c-5). Theme color resolution happens at
    /// `updateTheme(_:)` call time, not at construction.
    init() {}

    // MARK: - Chrome actions

    /// Show the chrome and start/restart the auto-hide countdown.
    func summonChrome() {
        chromeVisibility = .summoned
        resetAutoHide()
    }

    /// Reset the auto-hide countdown (user interaction with a control).
    ///
    /// `autoHideDuration == 0` would disable auto-hide entirely; the constant
    /// is positive today, but the guard preserves that escape hatch.
    func resetAutoHide() {
        chromeAutoHideTask?.cancel()
        guard Self.autoHideDuration > 0 else { return }
        chromeAutoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.autoHideDuration))
            guard !Task.isCancelled else { return }
            self?.chromeVisibility = .hidden
        }
    }

    /// Hide chrome immediately. Cancels any pending auto-hide timer.
    func hideChrome() {
        chromeVisibility = .hidden
        chromeAutoHideTask?.cancel()
        chromeAutoHideTask = nil
    }

    // MARK: - Theme

    /// Resolve all 7 theme colors from the current theme manager state.
    /// Replaces inline view-side assignment at `SongPlayAlongView.swift:219-225`
    /// (D-SP3c-3).
    ///
    /// Called from `SongPlayAlongView`'s `.task` blocks. Field mapping mirrors
    /// the VM's previous inline assignment exactly — no behavior change.
    func updateTheme(_ themeManager: AppThemeManager) {
        rhColor = themeManager.resolved.rightHandColor
        lhColor = themeManager.resolved.leftHandColor
        chordColor = themeManager.resolved.chordColor
        notationLineColor = themeManager.resolved.notationLineColor
        notationSecondaryColor = themeManager.resolved.notationSecondaryColor
        cardBackgroundColor = themeManager.resolved.cardBackgroundColor
        karaokeBackgroundColor = themeManager.resolved.karaokeBackgroundColor
    }
}
```

**Notes for the engineer:**
- If `AppThemeDefinition` lacks any of these 7 fields (or names them differently — e.g., `rightHand` instead of `rightHandColor`), match the EXACT VM call sites at `SongPlayAlongView.swift:219-225` and `:246-249`. Do NOT invent field names.
- `Logger.survibe(category:)` is the project's existing logger pattern (used by ScoringCoordinator and PlaybackCoordinator).
- `PlayAlongViewMode` and `NotationDisplayMode` are existing app-target enums; verify with grep if uncertain.

- [ ] **Step 2: Build the app target**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'generic/platform=iOS' -configuration Debug build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Run the new tests**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/PlayAlongChromeStateTests test 2>&1 | tail -15
```

Expected: 6 tests PASS.

- [ ] **Step 4: Hardcoded-logic + UIKit-import scan**

```bash
grep -nE "UIDevice|UIScreen\.main\.bounds|UIInterfaceOrientation|#if os\(macOS\)|#if os\(iOS\)|\.bottomBar|\.topBarTrailing|import UIKit|import AppKit" \
  SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift
```

Expected: 0 lines.

- [ ] **Step 5: Commit**

```bash
git add SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift
git commit -m "feat(SurVibe): PlayAlongChromeState coordinator (SP-3c)"
```

---

## Task 4: Wire facade delegation in `PlayAlongViewModel`

Add `let chrome = PlayAlongChromeState()`, replace 11 stored properties + 3 methods with delegating computed/forwarding facade members.

**Files:**
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift`

---

- [ ] **Step 1: Add `let chrome` to the `// MARK: - Coordinators` block**

Find the block (currently has `let scoring` + `let playback`). Append:

```swift
    /// Chrome state coordinator — owns visibility + view modes + resolved
    /// theme colors. SP-3c extraction.
    let chrome = PlayAlongChromeState()
```

`PlayAlongChromeState()` is zero-dep (D-SP3c-5) — no init wiring needed.

- [ ] **Step 2: Replace `viewMode` and `notationMode` stored properties with delegations**

Find these lines (around 124, 127):

```swift
    /// Visual display mode (falling notes vs scrolling sheet).
    var viewMode: PlayAlongViewMode = .fallingNotes

    /// Notation label display mode (Sargam, Western, dual, etc.).
    var notationMode: NotationDisplayMode = .sargam
```

Replace with:

```swift
    /// Visual display mode — delegates to `chrome.viewMode` (read+write).
    var viewMode: PlayAlongViewMode {
        get { chrome.viewMode }
        set { chrome.viewMode = newValue }
    }

    /// Notation label display mode — delegates to `chrome.notationMode` (read+write).
    var notationMode: NotationDisplayMode {
        get { chrome.notationMode }
        set { chrome.notationMode = newValue }
    }
```

- [ ] **Step 3: Replace 7 `@ObservationIgnored` theme color properties with delegations**

Find these lines (around 131-149). Replace each `@ObservationIgnored var X: Color = ...` with a get+set computed property delegating to `chrome.X`. Be precise about the `@ObservationIgnored` placement — the new computed property does NOT need `@ObservationIgnored` (computed properties don't trigger observation regardless).

Pattern for each color:

```swift
// OLD:
//     @ObservationIgnored
//     var rhColor: Color = .blue
// NEW:
    /// Right-hand accent color — delegates to `chrome.rhColor` (read+write).
    var rhColor: Color {
        get { chrome.rhColor }
        set { chrome.rhColor = newValue }
    }
```

Apply to all 7: `rhColor`, `lhColor`, `chordColor`, `notationLineColor`, `notationSecondaryColor`, `cardBackgroundColor`, `karaokeBackgroundColor`.

Delete the section comment `// MARK: - Resolved Theme Colors (v2)` and the related `/// Right-hand accent color — set once at .task from theme. ...` doc block on `rhColor` if the new doc says enough.

- [ ] **Step 4: Replace `chromeVisibility`, `chromeAutoHideSeconds`, `chromeAutoHideTask`, and the `ChromeVisibility` enum**

Find the `// MARK: - Chrome Visibility (v2)` block (around 232-253). Replace ENTIRELY with delegations:

```swift
    // MARK: - Chrome Visibility (v2) — delegates to chrome coordinator (SP-3c)

    /// Chrome visibility — delegates to `chrome.chromeVisibility`.
    var chromeVisibility: PlayAlongChromeState.ChromeVisibility { chrome.chromeVisibility }
```

Delete:
- The local `enum ChromeVisibility: Sendable { ... }` declaration (now `PlayAlongChromeState.ChromeVisibility`).
- The `private(set) var chromeVisibility: ChromeVisibility = .summoned` stored property.
- The `var chromeAutoHideSeconds: Double = 6.0` (replaced by `static let autoHideDuration` on the coordinator per D-SP3c-4).
- The `@ObservationIgnored private var chromeAutoHideTask: Task<Void, Never>?` (now coordinator-internal).

External call sites that referenced `viewModel.ChromeVisibility.X` will need to use `viewModel.chromeVisibility` (via the type-on-coordinator pattern). Most call sites only read `.summoned` / `.hidden` cases on a `ChromeVisibility` value, not the type itself. If any call site does `if case .hidden = viewModel.chromeVisibility { ... }`, it works unchanged because `chromeVisibility` is the same type either way.

If a view DOES reference `PlayAlongViewModel.ChromeVisibility` as a type name (grep `PlayAlongViewModel\.ChromeVisibility`), update it to `PlayAlongChromeState.ChromeVisibility`. Most likely there are no such references — the enum is consumed via instance reads, not as a type.

- [ ] **Step 5: Replace `// MARK: - Chrome Actions (v2)` methods**

Find the block (around 255-280). Replace `summonChrome`, `resetAutoHide`, `hideChrome` bodies to delegate:

```swift
    // MARK: - Chrome Actions (v2) — delegates to chrome coordinator

    /// Show the chrome and start/restart the auto-hide countdown.
    func summonChrome() {
        chrome.summonChrome()
    }

    /// Reset the auto-hide countdown (user interaction with a control).
    func resetAutoHide() {
        chrome.resetAutoHide()
    }

    /// Hide chrome immediately. Cancels any pending auto-hide timer.
    func hideChrome() {
        chrome.hideChrome()
    }
```

- [ ] **Step 6: Build — expect SUCCESS**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'generic/platform=iOS' -configuration Debug build 2>&1 | tail -15
```

Expected: `BUILD SUCCEEDED`. Unlike SP-3b's facade Task 6 (which intentionally produced compile errors), SP-3c facade should compile cleanly — the chrome state is mostly read-only or read+write (matching the original VM properties' visibility), and the methods delegate without side-effects on still-on-VM state.

If errors appear:
- `viewModel.ChromeVisibility` type references → change to `PlayAlongChromeState.ChromeVisibility`.
- `viewModel.chromeAutoHideSeconds` reads (should be zero, but check) → constant is now `PlayAlongChromeState.autoHideDuration` (different name; if external read, route through static accessor).
- `@ObservationIgnored` syntax errors on the new computed properties → remove the `@ObservationIgnored` annotation (computed properties don't take it).

- [ ] **Step 7: Commit**

```bash
git add SurVibe/PlayAlong/PlayAlongViewModel.swift
git commit -m "refactor(SurVibe): facade delegates chrome state to PlayAlongChromeState (SP-3c)"
```

---

## Task 5: Migrate view-side theme color assignment to `chrome.updateTheme`

Replace the 14 inline `viewModel.X = themeManager.resolved.X` assignments in `SongPlayAlongView` with a single `viewModel.chrome.updateTheme(themeManager)` call.

**Files:**
- Modify: `SurVibe/PlayAlong/SongPlayAlongView.swift`

---

- [ ] **Step 1: Find the inline assignment blocks**

```bash
grep -nE "viewModel\.(rhColor|lhColor|chordColor|notationLineColor|notationSecondaryColor|cardBackgroundColor|karaokeBackgroundColor) *=" \
  SurVibe/PlayAlong/SongPlayAlongView.swift
```

Expected: 14 hits (7 colors × 2 sites — `.task` for first appearance + theme-change observer at lines 219-225 and 246-249 per pre-flight verification).

- [ ] **Step 2: Replace each block of 7 assignments with a single call**

Find the first block around line 219-225 (the `.task` setting all 7 colors). Replace entirely with:

```swift
    viewModel.chrome.updateTheme(themeManager)
```

Repeat for the second block around line 246-249 (or wherever the second 7-line block lives).

If the surrounding code has comments or guards, preserve them — only collapse the 7 assignment lines into the single `updateTheme` call.

- [ ] **Step 3: Build — expect SUCCESS**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'generic/platform=iOS' -configuration Debug build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Run the existing PlayAlong theme integration tests (regression guard)**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/PlayAlongThemeIntegrationTests test 2>&1 | tail -10
```

Expected: all tests PASS. Theme color resolution behavior must be identical.

- [ ] **Step 5: Commit**

```bash
git add SurVibe/PlayAlong/SongPlayAlongView.swift
git commit -m "refactor(SurVibe): SongPlayAlongView uses chrome.updateTheme for color resolution (SP-3c)"
```

---

## Task 6: Verification + cleanup + tag (batched)

All 8 pre-existing PlayAlong suites + new chrome state suite + latency gates + lint/format/scan + tracker + tag.

**Files:**
- Modify (only if cleanup needed): SP-3c source files
- Modify: `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md`

---

- [ ] **Step 1: Run the new PlayAlongChromeState tests**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/PlayAlongChromeStateTests test 2>&1 | tail -10
```

Expected: 6 tests PASS.

- [ ] **Step 2: Run regression suites (SP-3a + SP-3b coordinator tests)**

```bash
for suite in ScoringCoordinatorTests PlaybackCoordinatorTests ; do
  echo "=== $suite ==="
  xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
    -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
    -only-testing:SurVibeTests/$suite test 2>&1 | tail -3
done
```

Expected: ScoringCoordinatorTests 5/5 PASS; PlaybackCoordinatorTests 7/7 PASS.

- [ ] **Step 3: Run the 8 pre-existing PlayAlong suites**

```bash
for suite in PlayAlongFullFlowTests PlayAlongIntegrationTests PlayAlongThemeIntegrationTests \
             PlayAlongChromeTests PlayAlongGestureTests ChordScoringIntegrationTests \
             PlayAlongViewModelTests PlayAlongTempoScalingTests ; do
  echo "=== $suite ==="
  xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
    -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
    -only-testing:SurVibeTests/$suite test 2>&1 | tail -3
done
```

Expected: all 8 suites PASS. `PlayAlongChromeTests` is the regression-critical suite for this sub-project — its 6 tests cover the EXACT facade methods we're delegating (`summonChrome`, `hideChrome`, `resetAutoHide`, auto-hide timing). If they fail, the facade delegation is broken.

- [ ] **Step 4: Run latency-contract tests**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/LatencyContractTests test 2>&1 | tail -10
```

Expected: 3/3 PASS.

- [ ] **Step 5: Run SVCore tests**

```bash
swift test --package-path Packages/SVCore 2>&1 | tail -5
```

Expected: 93/93 passing.

- [ ] **Step 6: SwiftLint + swift-format on SP-3c files**

```bash
/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml 2>&1 | tail -20
xcrun swift-format lint --configuration .swift-format \
  SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift \
  SurVibe/PlayAlong/PlayAlongViewModel.swift \
  SurVibe/PlayAlong/SongPlayAlongView.swift \
  SurVibeTests/PlayAlongChromeStateTests.swift 2>&1 | head -20
```

If swift-format lint produces output, run:

```bash
xcrun swift-format format --in-place --configuration .swift-format \
  SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift \
  SurVibe/PlayAlong/PlayAlongViewModel.swift \
  SurVibe/PlayAlong/SongPlayAlongView.swift \
  SurVibeTests/PlayAlongChromeStateTests.swift
```

Commit any cleanup:

```bash
git add -A
git commit -m "fix(SP-3c): lint/format cleanup"
```

(Skip this commit if there were no fixes.)

- [ ] **Step 7: Hardcoded-logic + single-hop noteOn scan**

```bash
grep -nE "UIDevice|UIScreen\.main\.bounds|UIInterfaceOrientation|#if os\(macOS\)|#if os\(iOS\)|\.bottomBar|\.topBarTrailing|import UIKit|import AppKit" \
  SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift \
  SurVibeTests/PlayAlongChromeStateTests.swift

grep -nE "AudioEngineManager\.shared\.noteOn|audioEngine\.noteOn|soundFont\.playNote" \
  SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift
```

Expected: 0 lines for both. Chrome state is pure UI presentation — no audio touched.

- [ ] **Step 8: Confirm footprint shrunk**

```bash
wc -l SurVibe/PlayAlong/Coordinators/*.swift SurVibe/PlayAlong/PlayAlongViewModel.swift
```

Expected:
- `PlayAlongChromeState.swift`: ~150 lines.
- `PlaybackCoordinator.swift`: 597 (unchanged).
- `ScoringCoordinator.swift`: 124 (unchanged).
- `PlayAlongViewModel.swift`: ~1,200–1,250 lines (was 1,353 pre-SP-3c, target -100 to -150).

If VM is > 1,300 lines, recheck deletions in Task 4 — the 11 stored properties + chrome enum + auto-hide task should have removed ~120-150 lines.

---

## Task 7: Tag + tracker update + exit checklist

**Files:**
- Modify: `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md`

---

- [ ] **Step 1: Update tracker §Status row**

Find the `SP-3c View-chrome extraction (phase 3 of 4)` row in the §Status table. Update:
- Status: `✅ shipped`
- Tag: `sp-3c-view-chrome @ <SHA>` (will be the tag SHA from Step 2)
- Merge SHA: leave blank (controller fills after merge)
- Commits: count from `git log --oneline main..HEAD`

Update heading `## Status (2026-04-19, post-SP-3b merge)` → `## Status (2026-04-20, post-SP-3c merge)`.

Add new `### SP-3c landed (2026-04-20)` block under the SP-3b one:

```markdown
### SP-3c landed (2026-04-20)

- Extracted: chrome visibility + auto-hide timer, viewMode, notationMode, 7 `@ObservationIgnored` theme color holders, theme color resolution method — all into `SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift` (~150 lines).
- Facade pattern wired: `PlayAlongViewModel` holds `let chrome = PlayAlongChromeState()`; 11 stored properties + 3 methods became delegating facade members.
- View-side change: `SongPlayAlongView` collapses 14 inline color assignments into `chrome.updateTheme(themeManager)` (D-SP3c-3).
- `PlayAlongViewModel.swift`: 1,353 → ~1,200 lines (≈ -150 net).
- Tests: 6 new PlayAlongChromeStateTests pass; 8 pre-existing PlayAlong suites pass (PlayAlongChromeTests is the regression guard); 3/3 LatencyContractTests; SP-3a/3b regression tests pass.
- Zero hardcoded platform checks on new file.
- Zero audio-thread interactions (chrome state is pure UI presentation).

**Architectural deviations applied (per spec §12):**
- D-SP3c-1: latencyPreset stays on VM (defers to SP-3d alongside NoteRouter).
- D-SP3c-2: 7 theme colors stay individual @ObservationIgnored (no observable struct).
- D-SP3c-3: updateTheme(_:) centralizes color resolution.
- D-SP3c-4: static let autoHideDuration replaces magic 6.0.
- D-SP3c-5: chrome init takes zero dependencies.
```

Commit:

```bash
git add -f docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md
git commit -m "docs(SP-3c): update tracker with SP-3c completion + SP-3d as next"
```

- [ ] **Step 2: Tag**

```bash
git tag sp-3c-view-chrome
git log --oneline main..HEAD
```

Note the commit count.

- [ ] **Step 3: Exit checklist (report only)**

- [ ] `SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift` exists, `@Observable @MainActor final class`, ~150 lines.
- [ ] 6 PlayAlongChromeStateTests green.
- [ ] All 8 pre-existing PlayAlong suites green (especially `PlayAlongChromeTests`).
- [ ] 5 ScoringCoordinatorTests + 7 PlaybackCoordinatorTests green (SP-3a/3b regression).
- [ ] 3/3 LatencyContractTests green.
- [ ] SVCore 93/93 green.
- [ ] Facade holds `let scoring` + `let playback` + `let chrome`.
- [ ] 11 stored properties + 3 methods (chrome surface) replaced by delegations.
- [ ] `SongPlayAlongView` collapses 14 inline color assignments into `chrome.updateTheme(themeManager)`.
- [ ] `chromeAutoHideSeconds` and old `ChromeVisibility` enum deleted from VM.
- [ ] `PlayAlongViewModel.swift` shrunk to ≤ ~1,250 lines.
- [ ] Hardcoded-logic grep returns 0 hits on SP-3c files.
- [ ] `AudioEngineManager.shared.noteOn` and `soundFont.playNote` return 0 hits in `PlayAlongChromeState.swift`.
- [ ] Tag `sp-3c-view-chrome` created.
- [ ] Tracker updated.

Next: SP-3d NoteRouter (HIGH risk, ships LAST). After SP-3d merges, the SP-3 umbrella close-out checks: VM ≤ 200 lines, delete `// swiftlint:disable file_length` directive, push `sp-3-vm-split-complete` umbrella tag, flip tracker SP-3 row to ✅ shipped.
