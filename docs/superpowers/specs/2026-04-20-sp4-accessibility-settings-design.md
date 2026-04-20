# SP-4 — Accessibility Polish + iOS Settings — Design Spec

**Date:** 2026-04-20
**Sub-project:** SP-4 (fifth in the Apple 3-OS refactor trajectory; consumer of SP-0 SettingsView + PreferenceStoring protocol + SP-3 coordinator surfaces)
**Status:** Design in review
**Size:** ~5-7 days across 8 batched tasks.
**Context:** No release has shipped; back-compat shims not required. Post-SP-3 trajectory: SP-4 → SP-5 → SP-6 (each sub-project is independent; SP-4 first by convention).
**Foundations consumed:**
- SP-0 F5 `SettingsView` + `PreferenceStoring` protocol (populate Appearance section).
- SP-0 `AppThemeManager` + `RangColorSystem` (for hand-color tokens).
- SP-3c `PlayAlongChromeState.updateTheme` (hand colors flow through resolved theme).
- SVCore `HapticEngine` (existing — wire, don't build).

## 1. Purpose

SurVibe's accessibility story has six concrete gaps vs the HIG audit (2026-04-19):
- **P1-5** Hand colors (rhColor/lhColor/chordColor) are hardcoded `.blue`/`.red`/`.purple` at `InteractivePianoView.swift:79-90`, bypassing the Rang theme system.
- **P1-6** No `accessibilityDifferentiateWithoutColor` guard anywhere — key highlights are color-only.
- **P1-8** Pinch-zoom works on `NotationContainerView` but doesn't inherit on `ScrollingSheetView` (the play-along notation scroller); no double-tap reset exists.
- **P1-10** Mic permission is requested cold via `PermissionManager.shared.requestMicrophoneAccess()` — no in-app explanation before the system alert.
- **SP-0 F5** `SettingsView.swift:14` still says `Text("Populated in SP-4")` for the Appearance section.
- **P2-2** (tightly coupled to P1-6): `HapticEngine` exists in SVCore but success paths (achievement unlock, correct-note flash, lesson completion) don't wire it.

SP-4 ships all six in one sub-project — they share a natural "polish the accessibility + Settings surface" theme and all are S-effort (≤1 day each).

**In scope (6 items):**

| # | Item | Files touched | Risk |
|---|---|---|:---:|
| 1 | P1-5 Rang hand-color tokens | `SVCore/Theme/RangColorSystem.swift` + `SVCore/Theme/AppThemeDefinition.swift` (if needed) + `InteractivePianoView.swift` + `PlayAlongChromeState.swift` | 🟢 LOW |
| 2 | P1-6 Differentiate-without-color on key highlights | `InteractivePianoView.swift` | 🟢 LOW |
| 3 | P1-8 ScrollingSheetView pinch-zoom + double-tap reset | `ScrollingSheetView.swift` | 🟢 LOW |
| 4 | P1-10 Mic permission pre-prompt | NEW `SurVibe/Components/MicPermissionPrePrompt.swift` + `PracticeSessionView.swift` + `SongPlayAlongView.swift` | 🟢 LOW |
| 5 | SettingsView Appearance section | `SettingsView.swift` | 🟢 LOW |
| 6 | P2-2 HapticEngine wiring on success paths | `AchievementUnlockToast.swift` + `LessonCompletionView.swift` + `SongPlayAlongView.swift` | 🟢 LOW |

**Out of scope (explicit non-goals):**
- No new coordinators. SP-4 is UI/theme polish; coordinator architecture is frozen after SP-3.
- No changes to audio, SwiftData, MIDI, or scoring pipelines.
- No P1-2 (Live Activity), P1-4 (Pencil), P1-11 (Gen-AI harness) — those are larger projects (SP-5 territory or post-SP).
- No P2-3 (AppIntent), P2-4 (multi-window), P2-5 (external display), P2-6 (arrow-key card nav), P2-9 (TipKit), P2-12 (presentation detents audit), P2-13 (haptics on tab switch), P2-14 (Focus filters) — opportunistic later work.

## 2. Success criteria

- SwiftLint 0 new errors; 0 new warnings on SP-4 files.
- All existing test suites pass (no regression).
- New per-item tests: ≥ 1 focused test per item. Target ~8-12 new `@Test` functions.
- VoiceOver smoke test on each changed surface (manual, documented in final verification).
- `grep .blue|.red|.purple SurVibe/Audio/InteractivePianoView.swift` returns 0 hits for the hand-color defaults (P1-5 exit signal).
- `grep accessibilityDifferentiateWithoutColor` returns ≥ 1 hit in `InteractivePianoView.swift` (P1-6 exit signal).
- `grep MagnificationGesture SurVibe/PlayAlong/ScrollingSheetView.swift` returns ≥ 1 hit (P1-8 exit signal).
- `ls SurVibe/Components/MicPermissionPrePrompt.swift` exists (P1-10 exit signal).
- `grep "Populated in SP-4" SurVibe/Settings/SettingsView.swift` returns 0 hits (F5 exit signal).
- `grep -E "HapticEngine|.sensoryFeedback" SurVibe/Components/AchievementUnlockToast.swift SurVibe/Learn/LessonCompletionView.swift SurVibe/PlayAlong/SongPlayAlongView.swift` returns ≥ 3 hits (P2-2 exit signal — at least one per file).
- Tag `sp-4-accessibility` pushed.

## 3. Architecture decisions

**AD-1 — No new coordinator.** SP-4 is polish + Settings population, not architecture. `PlayAlongChromeState` already owns theme colors (post-SP-3c); extending it is the natural home for Rang hand-color tokens. `SettingsView` owns the Settings UI. `MicPermissionPrePrompt` is a standalone `View` with no state.

**AD-2 — Hand colors on `AppThemeDefinition` (not a new type).** Rang theme already defines `rangNeel` / `rangHara` / `rangLal` / `rangPeela` / `rangSona` at `SVCore/Theme/RangColorSystem.swift`. Adding `rangHandRH` / `rangHandLH` / `rangHandBoth` (or equivalent names matching the existing RH/LH/Both semantic) to `RangColorSystem` + flowing through `AppThemeDefinition.resolved.rightHandColor` / `.leftHandColor` / `.chordColor` is the minimal change. `PlayAlongChromeState.updateTheme(_:)` already reads these fields — the fields just need real values wired. `InteractivePianoView`'s defaults change from `.blue`/`.red`/`.purple` to the theme-resolved values OR to the Rang tokens.

**AD-3 — Differentiate-without-color via letter overlay (R/L).** Per HIG audit recommendation: "overlay 'R'/'L' letter on highlighted keys when `@Environment(\.accessibilityDifferentiateWithoutColor) == true`". Applied at the key-highlight ZStack in `InteractivePianoView`. No new component needed — `Text("R")` / `Text("L")` with appropriate accessibility labels.

**AD-4 — ScrollingSheetView inherits `NotationContainerView`'s MagnificationGesture pattern.** Per HIG audit: `NotationContainerView.swift:171` already has `MagnificationGesture()` clamped 0.5x–3.0x with `zoomScale` + `pinchScale` `@GestureState`. `ScrollingSheetView` applies the same pattern. Double-tap reset is a `TapGesture(count: 2)` resetting `zoomScale = 1.0` with `.animation(.easeInOut)`.

**AD-5 — MicPermissionPrePrompt is a sheet-presented explanation.** Triggered BEFORE the system prompt. Reads a persisted `hasSeenMicPermissionPrePrompt` flag (via `@AppStorage` — or via `PreferenceStoring` once we have a concrete implementer, which is SP-5 territory; for SP-4 use `@AppStorage` with a clear TODO comment pointing to SP-5 migration). Presents a branded explanation + "Continue" button that triggers the system prompt. Dismissible via swipe or explicit button.

**AD-6 — Settings Appearance section reuses `AppearanceSettingsView`.** `AppearanceSettingsView` already exists at `SurVibe/Settings/AppearanceSettingsView.swift` (45 lines, has Dim Mode toggle). SettingsView's Appearance section can either:
- (a) Inline `AppearanceSettingsView`'s content directly
- (b) Use `NavigationLink(destination: AppearanceSettingsView())` for a sub-navigation surface

Spec picks (b) — cleaner separation, matches ProfileTab's existing link pattern.

**AD-7 — Haptics wire via `.sensoryFeedback(...)` on SwiftUI views, not direct `HapticEngine.shared.play(...)` calls.** `.sensoryFeedback(.success, trigger: X)` is the SwiftUI-native API and integrates with Reduce Motion automatically. Reserve direct `HapticEngine` calls for non-SwiftUI code paths. Per audit: `.sensoryFeedback(.selection)` already used in `ThemeCarouselPicker.swift:40` as the precedent.

## 4. Target file layout

```
SurVibe/
├── Audio/InteractivePianoView.swift           MODIFIED (P1-5, P1-6)
├── Components/
│   ├── AchievementUnlockToast.swift           MODIFIED (P2-2)
│   └── MicPermissionPrePrompt.swift           NEW (P1-10)
├── Learn/LessonCompletionView.swift           MODIFIED (P2-2)
├── Onboarding/                                UNCHANGED
├── PlayAlong/
│   ├── Coordinators/PlayAlongChromeState.swift  MODIFIED (P1-5 — Rang color wiring)
│   ├── ScrollingSheetView.swift               MODIFIED (P1-8)
│   └── SongPlayAlongView.swift                MODIFIED (P1-10, P2-2)
├── Practice/PracticeSessionView.swift         MODIFIED (P1-10)
└── Settings/SettingsView.swift                MODIFIED (F5)

Packages/SVCore/Sources/SVCore/Theme/
├── RangColorSystem.swift                      MODIFIED (P1-5 — new tokens)
└── AppThemeDefinition.swift                   MODIFIED IF field names change

SurVibeTests/
├── InteractivePianoViewAccessibilityTests.swift   NEW (P1-5 + P1-6)
├── MicPermissionPrePromptTests.swift              NEW (P1-10)
├── SettingsViewAppearanceTests.swift              NEW (F5)
└── (existing HapticsTests may exist — extend)
```

~9 files modified + 3 new files + 2-3 new test files.

## 5. Per-item acceptance criteria

### Item 1 — P1-5 Rang hand-color tokens

- [ ] `RangColorSystem.swift` adds 3 token `Color` extensions (e.g., `rangHandRH`, `rangHandLH`, `rangHandBoth`) with documented WCAG AA ratios + light/dark Asset Catalog variants.
- [ ] `InteractivePianoView.swift` defaults change from `Color = .blue` / `.red` / `.purple` → `Color = .rangHandRH` / `.rangHandLH` / `.rangHandBoth` (or the field read from theme resolved colors if the view has access).
- [ ] `PlayAlongChromeState.updateTheme` continues to flow `themeManager.resolved.rightHandColor` / `leftHandColor` / `chordColor` — real values are the Rang tokens.
- [ ] Test: `InteractivePianoView` default `rhColor` equals `Color.rangHandRH` (or equivalent assertion).
- [ ] Dark-mode Asset Catalog entries exist for all 3.

### Item 2 — P1-6 Differentiate-without-color overlay

- [ ] `InteractivePianoView` reads `@Environment(\.accessibilityDifferentiateWithoutColor)`.
- [ ] When true, highlighted keys show a "R" (right-hand) or "L" (left-hand) letter overlay at the top of the key.
- [ ] Overlay has `accessibilityHidden(true)` since the color announcement is already provided separately.
- [ ] Test: with `differentiateWithoutColor = true`, snapshot/view-state verifies overlay Text is present.

### Item 3 — P1-8 ScrollingSheetView pinch-zoom + double-tap reset

- [ ] `ScrollingSheetView.swift` adds `MagnificationGesture()` clamped 0.5x–3.0x (matching `NotationContainerView.swift:171` pattern).
- [ ] Double-tap resets `zoomScale = 1.0` with `.animation(.easeInOut)`.
- [ ] Tests: pinch state transitions + double-tap reset behavior.

### Item 4 — P1-10 Mic permission pre-prompt

- [ ] NEW `SurVibe/Components/MicPermissionPrePrompt.swift` — `struct MicPermissionPrePrompt: View`, branded explanation + Continue button.
- [ ] `@AppStorage("hasSeenMicPermissionPrePrompt")` gate; pre-prompt shows only on first mic request.
- [ ] `PracticeSessionView` + `SongPlayAlongView` (or their view models) present the pre-prompt via `.sheet(isPresented:)` before calling `PermissionManager.shared.requestMicrophoneAccess()`.
- [ ] `TODO(SP-5): migrate hasSeenMicPermissionPrePrompt from @AppStorage to PreferenceStoring concrete implementer` comment on the @AppStorage.
- [ ] Tests: pre-prompt view renders; dismissing it records the flag.

### Item 5 — SettingsView Appearance section populated

- [ ] `SettingsView.swift:14` placeholder `Text("Populated in SP-4")` REPLACED with `NavigationLink(destination: AppearanceSettingsView())` (or appropriate routing for iOS 26 `NavigationStack`).
- [ ] Section label: `"Appearance"` with an SF Symbol (e.g., `paintbrush`).
- [ ] Tests: SettingsView body contains the Appearance navigation link.

### Item 6 — P2-2 Haptic wiring on success paths

- [ ] `AchievementUnlockToast.swift` adds `.sensoryFeedback(.success, trigger: isVisible)` (or similar trigger for the reveal).
- [ ] `LessonCompletionView.swift` adds `.sensoryFeedback(.success, trigger: completionMomentReached)`.
- [ ] `SongPlayAlongView.swift` adds `.sensoryFeedback(.selection, trigger: lastCorrectNoteTimestamp)` on correct-note flash.
- [ ] All three guarded by `Reduce Motion` respect (automatic with `.sensoryFeedback`).
- [ ] No direct `HapticEngine.shared.play()` calls in these files (SwiftUI-native API only).

## 6. Testing plan

**New test files:**

| File | Tests | Covers |
|---|---|---|
| `InteractivePianoViewAccessibilityTests.swift` | ~4 | P1-5 default colors + P1-6 overlay presence |
| `MicPermissionPrePromptTests.swift` | ~3 | View renders + dismiss flag + AppStorage gate |
| `SettingsViewAppearanceTests.swift` | ~2 | Appearance link present + routes to AppearanceSettingsView |

Haptics (P2-2) not tested directly (SwiftUI `.sensoryFeedback` is framework-level; grep-based acceptance per §5 item 6 is sufficient).

Rang color tokens (P1-5) are structural — test via the new `InteractivePianoViewAccessibilityTests` assertion on default value.

**Regression suites (must still pass):** all 8 PlayAlong suites + 4 coordinator suites + LatencyContractTests + SVCore 93/93. None of these change behavior; regressions indicate a wiring bug.

## 7. Rollout

Single PR. Single tag: `sp-4-accessibility`.

Unlike SP-3 (4 sub-tags), SP-4's 6 items are not large enough to warrant separate phases — they're all S-effort. Batch all into one feature branch.

**Merge gates:**
- `/check` green.
- All regression suites green.
- New tests green.
- SwiftLint 0 new errors.
- All 6 grep-based exit signals (§2) pass.

## 8. Risks & open questions

### Resolved pre-spec

- ✅ `HapticEngine` exists in SVCore — wiring, not building.
- ✅ `AppearanceSettingsView` exists at `SurVibe/Settings/AppearanceSettingsView.swift` — reuse, don't recreate.
- ✅ `NotationContainerView` has the MagnificationGesture pattern to mirror for `ScrollingSheetView`.
- ✅ `.sensoryFeedback` already used (ThemeCarouselPicker) — precedent for the API.
- ✅ `@AppStorage` for `hasSeenMicPermissionPrePrompt` is acceptable interim; SP-5's `PreferenceStoring` first concrete impl migrates it.

### Open (flagged for plan-time)

1. **P1-5 color field naming:** use `rangHandRH` / `rangHandLH` / `rangHandBoth` OR `rangRightHand` / `rangLeftHand` / `rangChord`? Match whatever `AppThemeDefinition.resolved` field already uses (grep confirms — likely `rightHandColor` / `leftHandColor` / `chordColor`, so Rang token names should be symmetric: `rangRightHand` / `rangLeftHand` / `rangBothHands`).
2. **P1-6 overlay placement:** top-of-key vs center-of-key for the R/L letter. Plan-time decision based on keyboard layout inspection.
3. **P1-10 pre-prompt trigger point:** integrate at VM's `loadSong` before `requestMicrophoneAccess()` OR at view-level via `.task { }`. Plan prefers VM-level for consistency with existing permission flow.
4. **Item 5 routing:** `NavigationLink(destination:)` vs `NavigationStack.path` + `.navigationDestination(for:)`. Plan uses whatever ProfileTab's existing link uses (consistency).

### Deliberate non-risks

- No release shipped → no back-compat concerns.
- Zero audio-thread work.
- Zero SwiftData work.
- Zero changes to SP-0/1/2/3 invariants (latency tests, coordinator APIs).

## 9. Exit checklist

SP-4 ships only when ALL of these are true:

- [ ] 6 items complete per §5 acceptance criteria.
- [ ] ~9-12 new tests green; all regression suites green.
- [ ] `/check` green.
- [ ] SwiftLint 0 new errors.
- [ ] Exit signals grep: all 6 pass (§2).
- [ ] Tracker updated: SP-4 row `✅ shipped` with tag SHA + merge SHA.
- [ ] Tag `sp-4-accessibility` pushed.

Next: **SP-5** Gen-AI harness (fresh session per the post-SP-3 context-budget analysis).
