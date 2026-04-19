# SP-Trajectory Tracker — iPad/Mac Refactor

> Dedicated tracker for the Apple 3-OS refactor trajectory (SP-0 through SP-6).
> Source of truth for "what shipped, what was deferred, what's next".
> Created 2026-04-19 after SP-0 + SP-1 landed on `main`.

## Status (2026-04-19)

| Sub-project | Status | Tag | Merge SHA | Commits |
|---|---|---|---|:---:|
| **SP-0** Foundation | ✅ shipped | `sp-0-foundation` @ `84b523c` | `51c6e76` | 11 |
| **SP-1** Adaptive Root Shell | ✅ shipped | `sp-1-adaptive-shell` @ `3b3677c` | `685d1c7` | 9 |
| **SP-2** Per-surface layout (piano, split view, landscape) | ⬜ pending | — | — | — |
| **SP-3** PlayAlongViewModel split | ⬜ pending | — | — | — |
| **SP-4** Accessibility polish + iOS Settings nav | ⬜ pending | — | — | — |
| **SP-5** Gen-AI harness | ⬜ pending | — | — | — |
| **SP-6** Mac destination | ⬜ pending | — | — | — |

**Test-suite snapshot (post-SP-1 on `main`):**
- SVCore: 93/93 passing (swift test, 0.46 s).
- SurVibeTests: full-suite run gated by a pre-existing simulator crash (tracked separately); individual SP-0/SP-1 tests (FeatureFlagStoreTests, AnalyticsEventTests, AppCommandsTests, AppTabTests, LatencyContractTests.featureFlagToggleDoesNotRestartEngine) run individually and pass.

---

## SP-0 — Foundation

- **Spec:** [docs/superpowers/specs/2026-04-19-sp0-foundation-design.md](../specs/2026-04-19-sp0-foundation-design.md)
- **Plan:** [docs/superpowers/plans/2026-04-19-sp0-foundation.md](2026-04-19-sp0-foundation.md)
- **Tag:** `sp-0-foundation` @ `84b523c`
- **Merge commit:** `51c6e76` (2026-04-19)
- **Commits on feature branch:** 11

### F1–F6 Deliverables

| ID | Deliverable | Status | Evidence |
|---|---|:---:|---|
| F1 | `featureFlagToggleDoesNotRestartEngine` latency regression test | ✅ | `SurVibeTests/LatencyContractTests.swift:55-75` |
| F1 | `LatencyContractTests+macOS.swift` Mac-CI stub | ✅ | `SurVibeTests/LatencyContractTests+macOS.swift` (exists; `#if os(macOS)` no-op body) |
| F2 | Platform hygiene convention doc | ✅ | `docs/Architecture_Platform_Hygiene.md` |
| F2 | `Platform/` folders + `.gitkeep` | ✅ | `SurVibe/Platform/.gitkeep`, `Packages/SVCore/Sources/SVCore/Platform/.gitkeep` |
| F3 | 8 new analytics event cases (`sidebarUsed`, `shortcutInvoked`, `featureFlagToggled`, `settingsOpened`, `aiConsentShown`, `aiConsentGranted`, `aiConsentRevoked`, `macWindowOpened`) | ✅ | `AnalyticsEvent.swift:95-112` |
| F3 | `AnalyticsEvent: CaseIterable` conformance | ✅ | `AnalyticsEvent.swift:4` (+ manual `allCases` in `:120-144` because deprecated cases block synthesis — SE-0192) |
| F3 | `rawValuesAreUnique` + `rawValuesUseSnakeCase` tests | ✅ | `Packages/SVCore/Tests/SVCoreTests/AnalyticsEventTests.swift` (10 tests pass) |
| F4 | `FeatureFlag` enum with 3 cases | ✅ | `Packages/SVCore/Sources/SVCore/FeatureFlags/FeatureFlag.swift` |
| F4 | `FeatureFlagStoring` protocol | ✅ | `Packages/SVCore/Sources/SVCore/FeatureFlags/FeatureFlagStoring.swift` |
| F4 | `FeatureFlagStore` (`@MainActor @Observable`) | ✅ | `Packages/SVCore/Sources/SVCore/FeatureFlags/FeatureFlagStore.swift` |
| F4 | `FeatureFlagStoreTests` (defaults-off, round-trip, analytics-fires) | ✅ | 4 tests pass (added `togglingOneFlagDoesNotAffectOthers` beyond spec's 3) |
| F4 | Debug UI for flag toggles | ✅ | `SurVibe/Settings/FeatureFlagsSection.swift` (see deviation D-SP0-1 below) |
| F5 | `SettingsView` SwiftUI view | ✅ | `SurVibe/Settings/SettingsView.swift` |
| F5 | `Settings { }` scene wired in `SurVibeApp` | ✅ | `SurVibeApp.swift:235-249` (guarded `#if os(macOS)` — see D-SP0-2) |
| F5 | `PreferenceStoring` protocol | ✅ | `Packages/SVCore/Sources/SVCore/Preferences/PreferenceStoring.swift` |
| F6 | `docs/Foundation_Primitives.md` | ✅ | file exists |

### AD-1 — AD-5 architectural decisions

| ID | Decision | Verified? |
|---|---|:---:|
| AD-1 | `FeatureFlag` in SVCore (not app target) | ✅ code lives in `Packages/SVCore/Sources/SVCore/FeatureFlags/` |
| AD-2 | `PreferenceStoring` as SVCore protocol; impl in app | ✅ protocol only in SVCore; no impl yet (deferred to SP-4/SP-5 per spec §5) |
| AD-3 | Platform interop via SVCore protocols | ✅ convention documented in `Architecture_Platform_Hygiene.md` |
| AD-4 | `FeatureFlagStore` uses `@Observable` macro | ✅ `FeatureFlagStore.swift:15` |
| AD-5 | `Settings{}` scene inert on iOS by design | ⚠️ Evolved to `#if os(macOS)` guard (see D-SP0-2) — same outcome, different mechanism |

### Deferrals consumed by later sub-projects

| Deferred from SP-0 | To | Verified |
|---|---|:---:|
| Commands module | **SP-1 (landed)** | ✅ `SurVibe/Commands/AppCommands.swift` exists post-SP-1 |
| `AppDestination` v2 (deep links / column routing) | SP-1 | ✅ confirmed NOT landed; `AppDestination.swift` unchanged from pre-SP-0 |
| VM scene-hoisting code (rotation / size-class survival) | SP-2 / SP-3 | ✅ confirmed not present |

### Architectural deviations from plan (all documented, all accepted)

**D-SP0-1 — `FeatureFlagStore.init` uses constructor DI instead of `setProvider/resetProvider`.**
- *Spec said:* analytics dependency would be reset via a provider-swap helper.
- *Shipped:* `init(defaults: UserDefaults = .standard, analytics: any AnalyticsProviding = AnalyticsManager.shared)`.
- *Reason:* `AnalyticsManager.shared` has no set-provider seam, and constructor DI is cleaner + testable without mutating shared state.
- *Impact:* none. Tests use the DI'd mock; production uses the defaulted shared.

**D-SP0-2 — `Settings { }` scene wrapped in `#if os(macOS)`.**
- *Spec (AD-5) said:* the scene is "inert by design" on iOS; no guard needed.
- *Shipped:* `SurVibeApp.swift:235` guards the whole `Settings { }` block with `#if os(macOS)`.
- *Reason:* SwiftUI's `Settings` scene is macOS-only; referencing it unconditionally on iOS builds surfaced a compile / unresolved-symbol issue.
- *Impact:* identical user-visible behavior (no iOS settings surface). SP-4 still owns the iOS in-app Settings route.

**D-SP0-3 — `FeatureFlagsSection` lives at `SurVibe/Settings/FeatureFlagsSection.swift`, not inside `DiagnosticsOverlayView`.**
- *Spec (F4) said:* append the section inside `DiagnosticsOverlayView`.
- *Shipped:* a standalone `#if DEBUG` component consumed by `SettingsView`'s Debug section (the `#Preview` still works).
- *Reason:* places the debug UI where a developer actually expects to find it (Settings → Debug), and keeps the diagnostics overlay focused on latency/pitch telemetry.
- *Impact:* feature flags are still toggleable in DEBUG builds; `DiagnosticsOverlayView` file was not modified.

---

## SP-1 — Adaptive Root Shell

- **Spec:** [docs/superpowers/specs/2026-04-19-sp1-adaptive-shell-design.md](../specs/2026-04-19-sp1-adaptive-shell-design.md)
- **Plan:** [docs/superpowers/plans/2026-04-19-sp1-adaptive-shell.md](2026-04-19-sp1-adaptive-shell.md)
- **Tag:** `sp-1-adaptive-shell` @ `3b3677c`
- **Merge commit:** `685d1c7` (2026-04-19)
- **Commits on feature branch:** 9

### F1–F5 Deliverables

| ID | Deliverable | Status | Evidence |
|---|---|:---:|---|
| F1 | `.tabViewStyle(.sidebarAdaptable)` on root `TabView` | ✅ | `ContentView.swift:64` |
| F1 | `AppRouter` read via `@Environment` inside `ContentView` | ✅ | `ContentView.swift:16-17` |
| F2 | `AppRouter` hoisted to `SurVibeApp` + injected into `ContentView` | ✅ | `SurVibeApp.swift:216-228` |
| F2 | `.commands { AppCommands(router:) }` attached to `WindowGroup` | ✅ | `SurVibeApp.swift:231-233` |
| F3 | `AppCommands.swift` with `CommandMenu("Navigate")` + `CommandGroup(replacing: .appSettings)` | ✅ | `SurVibe/Commands/AppCommands.swift` |
| F3 | ⌘1–⌘4 tab switching | ✅ | `AppCommands.swift:17-25` |
| F3 | ⌘, Preferences shortcut | ✅ | `AppCommands.swift:27-32` |
| F3 | `shortcutInvoked` analytics on each command action | ✅ | `AppCommands.swift:45-76` |
| F4 | `AppTab: CaseIterable` | ✅ | `AppTab.swift:11` |
| F4 | `AppTab.keyEquivalent` mapping (1/2/3/4) | ✅ | `AppTab.swift:40-50` |
| F5 | `.hoverEffect(.automatic, isEnabled:)` on `DoorCard` | ✅ | `DoorCard.swift:96` |
| F5 | `.hoverEffect(.automatic)` on 5 ProfileTab rows | ✅ | `ProfileTab.swift:243, 257, 269, 288, 304` |
| Tests | `AppCommandsTests` — 3 tests | ✅ | `SurVibeTests/AppCommandsTests.swift` |
| Tests | `AppTabTests` — 3 tests | ✅ | `SurVibeTests/AppTabTests.swift` |

### AD-1 — AD-7 architectural decisions

| ID | Decision | Verified? |
|---|---|:---:|
| AD-1 | `.sidebarAdaptable` with no size-class wrapping | ✅ `ContentView.swift:64` — single modifier, no `horizontalSizeClass` check |
| AD-2 | `AppRouter` hoisted to `SurVibeApp` | ✅ `SurVibeApp.swift:216` |
| AD-3 | Commands in app target, not SVCore | ✅ `SurVibe/Commands/AppCommands.swift` (imports SVCore but defined in app) |
| AD-4 | Dispatch through `router.switchTab(to:)` | ✅ `AppCommands.performTabSwitch` calls `router.switchTab` |
| AD-5 | `CommandGroup(replacing: .appSettings)` | ✅ `AppCommands.swift:27` |
| AD-6 | `.hoverEffect` on component (DoorCard body) | ✅ `DoorCard.swift:96` inside body, single site |
| AD-7 | No `sidebarUsed` firing in SP-1 | ✅ grep confirms no call site dispatches `.sidebarUsed`; event case exists (from SP-0 F3) but unused |

### Deferrals (explicit in spec §1 Out of Scope)

| Item | Deferred to | Verified not-landed |
|---|---|:---:|
| `NavigationSplitView` on Songs + Learn | SP-2 | ✅ `grep NavigationSplitView SurVibe/` → 0 matches |
| Transport shortcuts (Space = play/pause, ←/→ seek) | SP-2 | ✅ `AppCommands.swift` contains only ⌘1–⌘4 + ⌘, |
| `@FocusState` / `@FocusedValue` | SP-2 | ✅ 0 code hits; only 1 comment hit in `AppCommands.swift:13` |
| `hoverEffect` on Songs list rows + Learn lesson rows | SP-2 / SP-4 | ✅ grep shows hoverEffect only on DoorCard (1) + ProfileTab (5); SongCardView/SongListRow/FilterChip/LessonCardView untouched |
| Piano adaptive `pitchRange` (width-responsive 61/73/88 keys) | SP-2 (P0-5) | ✅ still hardcoded `Pitch(36)...Pitch(96)` at `SurVibe/Audio/InteractivePianoView.swift:121` |
| Landscape play-along size-class branching | SP-2 (P1-3) | ✅ `grep horizontalSizeClass SurVibe/PlayAlong/` → 0 matches |
| `AppDestination` enum changes | later | ✅ enum still has its pre-SP-0 cases; no column-routing additions |
| Mac destination (SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD) | SP-6 | ✅ no pbxproj change in SP-0/SP-1 |

### Architectural deviations from plan

**D-SP1-1 — `AppCommands.performTabSwitch` / `performPreferences` take `analytics: (any AnalyticsProviding)? = nil`, not `= AnalyticsManager.shared`.**
- *Spec (F3) said:* the tests could pass a mock and otherwise default to `AnalyticsManager.shared`.
- *Shipped:* nil-sentinel default; `provider = analytics ?? AnalyticsManager.shared` at call time.
- *Reason:* `AnalyticsManager.shared` is `@MainActor`-isolated and cannot be evaluated as a default parameter value at function-signature time (main-actor isolation violation). Nil-sentinel preserves the DI seam without breaking isolation rules.
- *Impact:* identical runtime behavior; tests use `analytics: provider`.

**D-SP1-2 — In-DoorCard `.hoverEffect` placement.**
- *Spec (F5) said:* "Apply to the outermost tappable `Button` in DoorCard's body". Exact placement was plan-time.
- *Shipped:* `DoorCard.swift:96` — modifier chain is `.buttonStyle(.plain)` then `.hoverEffect(.automatic, isEnabled: isEnabled)` then `.disabled(!isEnabled) .contentShape(Rectangle()) .accessibilityElement(children: .combine)`. Places hoverEffect on the outer `Button`, after `.buttonStyle` (correct — buttonStyle is the tappable-region declaration), before `.disabled` (correct — hoverEffect honours disabled state implicitly via `isEnabled:`).
- *Reason:* plan chose this order so the hover visual renders on the same shape the button paints; accessibility modifiers stay at the end of the chain per CLAUDE.md convention.
- *Impact:* none. Only noted here so SP-2 authors know this is the load-bearing line, not a suggestion.

**D-SP1-3 — `MockAnalyticsProvider.trackedEvents` vs `.tracked`.**
- *Spec testing plan said:* use the existing `MockAnalyticsProvider` at `MockAnalyticsProviderTests.swift:19`.
- *Shipped:* `AppCommandsTests.swift` uses `provider.trackedEvents` (matches `SurVibeTests` mock shape).
- *Detail:* two mocks exist — `SurVibeTests/MockAnalyticsProvider` exposes `trackedEvents`; `SVCoreTests/TestDoubles/MockAnalyticsProvider` exposes `tracked`. SP-1 tests use the SurVibeTests variant because they target app-target types.
- *Impact:* none. Distinction is internal to the test suites.

---

## Upcoming sub-projects

### SP-2 — Per-surface deep layout (next)

From the Refactor Plan P0 + P1 pool:
- P0-2 **`NavigationSplitView` on Songs + Learn** — primary column 320–375pt, detail column fills remainder (iPad regular-width only).
- P0-5 **Piano `pitchRange` adapts to width** — compact 61 keys / regular 73 or 88 keys via `GeometryReader`.
- P0-6 **Migrate PlayAlongToolbar + PracticeControlsToolbar to system `.toolbar {}`** — gets Liquid Glass for free.
- P1-3 **Landscape play-along layout** — side-by-side keyboard + notation on iPhone landscape / iPad.
- Transport shortcuts in `AppCommands` (Space, ←, →, ⌘. for stop) using `@FocusedValue` for per-surface dispatch.
- `hoverEffect` sweep across Songs/Learn cards + rows.

### SP-3 — PlayAlongViewModel split

- P1-1 Decompose the 1,828-line `PlayAlongViewModel` into `PlaybackCoordinator`, `ScoringCoordinator`, `NoteRouter`, `WaitController` (existing), view-chrome extraction.
- Guarded by SP-0 `FeatureFlag.playAlongViewModelV2` for A/B rollout.
- Non-negotiable latency contract: `LatencyProbe` p95 delta ≤ 0.5 ms vs baseline.

### SP-4 — Accessibility polish + iOS in-app Settings

- Add iOS navigation route to `SettingsView` (SP-0 built the view; SP-4 wires the entry point).
- Populate the Appearance section of `SettingsView` (theme picker, dim mode, display density).
- P1-5 Hand colors → Rang theme tokens.
- P1-6 Differentiate-without-color on piano key highlights.
- P1-7 Devanagari `accessibilityLabel` across SargamNoteView.
- P1-8 Pinch-zoom inheritance on `ScrollingSheetView` + double-tap reset.
- P1-9 Skip-onboarding button.
- P1-10 Mic permission pre-prompt.
- VoiceOver sweep.

### SP-5 — Gen-AI harness

- P1-11 `AIGeneratedBadge`, `AIDisclosureSheet`, `AIFeedbackControl`, `PromptSanitiser`, `useAIFeatures` preference (wires SP-0's `PreferenceStoring`), consent analytics (`aiConsentShown/Granted/Revoked` from SP-0 F3), `PlaybackState.isActive` gate.
- Guarded by SP-0 `FeatureFlag.onDeviceAI`.

### SP-6 — Mac destination

- P2-7 / P2-8 SVAudio macOS port: `#if os(iOS)` around `AVAudioSession` calls, Mac no-op path.
- Enable `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` after deep Mac validation (or native Mac target + Catalyst decision).
- Populate `LatencyContractTests+macOS.swift` stub (SP-0 F1) with Mac p95 budget (5–15 ms).
- Guarded by SP-0 `FeatureFlag.macDestination`.
- Fires `macWindowOpened` analytics (SP-0 F3).

---

## How to use this tracker

- Before starting a sub-project, read the upcoming section and confirm scope matches the live Refactor Plan (`docs/Audit_2026-04-19_Refactor_Plan.md`).
- After merging a sub-project, update the row in §Status + add an §SP-N block with the same shape as SP-0 / SP-1.
- If a deferred item gets pulled forward (or pushed back), move the row in the deferrals table of the relevant sub-project with a note in parentheses `(moved from SP-X on YYYY-MM-DD because ...)`.
- **Do not** create a new SP-N spec/plan without updating this tracker's §Status table in the same commit.
