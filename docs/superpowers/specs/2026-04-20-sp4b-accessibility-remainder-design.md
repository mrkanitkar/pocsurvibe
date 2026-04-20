# SP-4b — Accessibility Remainder (Design Spec)

> Sub-project: SP-4b
> Date: 2026-04-20
> Predecessors: SP-4a (`sp-4-accessibility @ d916fa2`, merge `b6d340e`)
> Successor: SP-4c (Live Activity + Pencil + focus-ring polish)
> Audit items covered: P2-6, P2-12, P2-13 (from `docs/Audit_2026-04-19_Refactor_Plan.md`)

## 1. Purpose

Close the accessibility remainder from the 2026-04-19 audit that was not in SP-4a's narrow scope. Three independent items, all UI-only, all main-thread, no audio path touched.

## 2. HIG + API grounding (verified 2026-04-20)

- **`FocusState`** (Apple SwiftUI doc): a property wrapper for *observing* focus; programmatic focus-move requires setting the wrapped value directly (`focusedSongID = nextID`). SwiftUI does **not** auto-wire arrow keys for grid/list traversal.
- **`onKeyPress(_:action:)`** (iOS 17+): the documented primitive for hardware-keyboard input on a focused view. SurVibe targets iOS 26 so available unconditionally.
- **`presentationDetents(_:)`** + **`presentationDragIndicator(_:)`**: drag indicator belongs on *resizable* sheets only (≥2 detents); single-detent compose sheets stay grabber-less per the Mail / Messages precedent cited in HIG > Sheets (updated 2026-03-24).
- **`SensoryFeedback.selection`**: Apple's `sensoryFeedback(_:trigger:)` doc example uses `.selection` for state toggles. Correct semantic fit for tab switching; lighter than `.impact`.
- **Sheet HIG (iPadOS):** "prefer page or form sheet presentation styles on iPadOS" → detents are primarily an iPhone concern. Design below applies detents at the sheet content level so iPhone benefits without affecting iPad auto-centred sheets.

## 3. Scope

### 3.1 P2-6 — Arrow-key card navigation

Wire explicit arrow-key handlers on the already-focused lesson and song cards. Initial focus on first card when the library appears via hardware keyboard (guarded so search field isn't stolen from).

**Files touched:**
- `SurVibe/Learn/LessonLibraryView.swift` (list — linear nav: `.upArrow`, `.downArrow`)
- `SurVibe/Songs/SongLibraryView.swift` (2-col grid — row/col nav: `.up/down/left/rightArrow`)

**Mechanism:**
- Extend each card's existing `.onKeyPress(.return)` chain with arrow-key handlers.
- Handler computes `nextIndex` from `viewModel.filteredLessons` / `filteredSongs` and sets `focusedLessonID` / `focusedSongID`.
- Grid navigation assumes 2 columns (`.adaptive(minimum: 160)` practical column count on iPhone + split iPad). Down-arrow moves `index + 2`; last-row partials clamp to last item.
- Initial focus: `.onAppear { if focusedLessonID == nil, let first = vm.filteredLessons.first { focusedLessonID = first.lesson.id } }` — guarded so re-appearance after dismissing a sheet doesn't steal focus from the search field.

**Extract-for-testing:**
A pure `nonisolated static func` index helper:

```swift
enum LibraryFocusNavigator {
    static func nextIndex(
        for direction: FocusDirection,
        currentIndex: Int,
        count: Int,
        columns: Int
    ) -> Int? {
        // returns nil for no-op (edge); Int for new index
    }
    enum FocusDirection { case up, down, left, right }
}
```

Single definition lives in a shared file `SurVibe/Navigation/LibraryFocusNavigator.swift`. Both `LessonLibraryView` (columns=1, list) and `SongLibraryView` (columns=2, grid) call `LibraryFocusNavigator.nextIndex(...)` from their arrow-key handlers.

### 3.2 P2-12 — Sheet detent audit

Five sheets categorised per HIG:

| Sheet | File:line | Detents | Drag indicator |
|---|---|---|---|
| Song detail (read-only info) | `SongLibraryView.swift:92` | `[.medium, .large]` | `.visible` |
| Song import (multi-tab compose) | `SongLibraryView.swift:97` | `[.large]` | default (hidden) |
| Song edit (multi-tab compose) | `SongLibraryView.swift:101` | `[.large]` | default (hidden) |
| Import warnings | `SongImportSheet.swift:81` | `[.medium]` | `.visible` |
| Edit warnings | `SongEditView.swift:76` | `[.medium]` | `.visible` |

Modifiers applied on the sheet's content view inside each `.sheet { ... }` closure, not on the `.sheet(...)` call site.

Compose sheets (import + edit) stay `.large` with no grabber. The explicit `.presentationDetents([.large])` documents intent (even though `.large` is the default) and prevents accidental detent bleed from nested sheets.

### 3.3 P2-13 — TabView selection haptic

**File:** `SurVibe/ContentView.swift`
**Add:** `.sensoryFeedback(.selection, trigger: selectedTab)` immediately after `.tabViewStyle(.sidebarAdaptable)` (line 64).

One line. No helpers, no wrapper.

## 4. Architecture decisions

### AD-1 — `.selection` haptic, not `.impact`

Audit suggested `.impact(weight: .medium)`. Overridden here because:
- Apple's doc example for `sensoryFeedback` uses `.selection` for state toggles.
- `.selection` is semantically correct for tab switching (picker-like nav).
- `.impact(.medium)` would be heavier than iOS-system precedent (iOS native tab bar uses no haptic; when apps add one, `.selection` matches platform feel).

### AD-2 — Explicit arrow-key handling over hoping for SwiftUI defaults

Audit Option A ("rely on SwiftUI defaults") would not satisfy the audit's actual user outcome. Apple `FocusState` docs confirm SwiftUI does not auto-traverse grids/lists by arrow key; the platform primitive is `onKeyPress`. Implemented explicitly.

### AD-3 — 2-column assumption for Songs grid

`SongLibraryView` uses `LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))])`. At iPhone + split-iPad widths this practically resolves to 2 columns; at wide iPad it may render 3+. The arrow-key math uses a compile-time 2-column assumption. Full GeometryReader-driven column count deferred (see §6); the mismatch on wide iPad is graceful (arrow keys still move forward/backward, just not diagonally perfect), not broken.

### AD-4 — Grabber only on resizable sheets

HIG-aligned: compose sheets (import, edit) have single detent, no grabber. Read-only detail + warning sheets have two/one detent but are resizable *or* ephemeral, grabber visible to advertise the resize / swipe-dismiss affordance.

### AD-5 — Detent modifiers at content level, not call site

Current codebase pattern is `.sheet(...) { ContentView() }` and the content view itself applies `.presentationDetents(...)`. Consistent with `ComingSoonSheet:76`, `TanpuraSettingsSheet:123`, `MicPermissionPrePrompt:60`. Preserves this pattern.

## 5. Testing

### 5.1 Unit tests

`SurVibeTests/LibraryFocusNavigatorTests.swift` — Swift Testing framework.

Cases:
- `downArrowFromFirstItemAdvancesOneRow()` — columns=2, index=0, count=6, direction=.down → 2
- `downArrowFromLastRowReturnsNil()` — columns=2, index=4, count=6, direction=.down → nil (last row)
- `rightArrowFromEndOfRowReturnsNil()` — columns=2, index=1, count=6, direction=.right → nil
- `leftArrowFromStartOfRowReturnsNil()` — columns=2, index=0, direction=.left → nil
- `linearDownOnOneColumnList()` — columns=1, index=2, count=5, direction=.down → 3
- `linearUpFromZeroReturnsNil()` — columns=1, index=0, direction=.up → nil
- `downArrowFromPartialLastRowReturnsNil()` — columns=2, index=4, count=5 (odd count, last row has 1), direction=.down → nil
- `rightArrowFromLastItemReturnsNil()` — columns=2, index=count-1, direction=.right → nil

Target: 8 tests, all covering the pure index math.

### 5.2 Manual QA (no unit tests — SwiftUI-internal)

**P2-12 detents:**
- iPhone 15 Pro sim: trigger each sheet via its call path (song detail via long-press menu, import via toolbar, edit via long-press on user song, warnings by forcing an import error).
- Verify: detail sheet opens at medium, can drag to large; import/edit open at full; warning sheets open at medium with grabber visible.
- iPad Air 13" (M3): sheets render as page/form sheets (iPadOS default), detents don't visibly apply (HIG-expected behaviour — verify no regression).

**P2-13 haptic:**
- Physical iPhone (haptics don't fire in simulator): switch tabs via tap and via ⌘1–⌘4 shortcut. Verify `.selection` haptic fires for both paths.
- Verify no haptic on initial launch (before `selectedTab` changes).

**P2-6 arrow nav:**
- iPad + Magic Keyboard: open Songs tab, press Tab to focus first card, press right-arrow → focus moves to column 2; down-arrow → next row; left at col 0 → no-op; Return → opens song.
- Same flow on Lessons tab, verify up/down only (no left/right).
- After switching tabs and returning, verify initial focus re-establishes.

### 5.3 Latency regression gate

`/latency-check` merge gate. Expected no-op for all three items (UI-only, no audio code touched).

`LatencyContractTests.featureFlagToggleDoesNotRestartEngine` + `rotationDoesNotRestartAudioEngine` must stay green. p95 delta ≤ 0.5 ms.

## 6. Out of scope for SP-4b — routed to SP-4c

The following items surfaced during brainstorming but are NOT part of SP-4b. Each is tagged with its route so none are lost:

### Deferred to SP-4c (accessibility-polish bundle)

| Item | Reason |
|---|---|
| Custom focus-ring styling on focused lesson/song cards | SwiftUI renders a system ring on focused `NavigationLink`. Custom ring (e.g., `themeManager.resolved.accentColor` overlay) is a visual-polish layer that pairs better with SP-4c's other UI-polish work (Pencil overlay, Live Activity styling). |
| Escape-to-clear-focus on library cards | Minor UX polish; not required to deliver arrow-key nav. Pairs with focus-ring polish above. |
| `@FocusState` on HomeTab `DoorCard`s | Not in audit P2-6 (which specifies lesson/song cards only). Routed to SP-4c as an opportunistic extension while the focus-ring work is in-flight. |
| `@FocusState` on ProfileTab rows | Same reasoning as DoorCards. |
| `GeometryReader`-driven dynamic column count for Songs grid arrow-key math | Addresses AD-3's 2-column assumption on wide iPad. Graceful-today, polish-later. |

### Rejected (decision, not deferral)

| Item | Decision |
|---|---|
| `.impact(weight: .medium)` haptic on tab switch | Rejected per AD-1 (`.selection` matches HIG and platform precedent). |
| Drag indicators on `MicPermissionPrePrompt` / `TanpuraSettingsSheet` | Already correctly configured in SP-4a / prior work. No change. |
| Unit tests for `presentationDetents` / `sensoryFeedback` behaviour | Presentation detents and haptic firing are SwiftUI-internal and not unit-testable. Manual QA only. |

### Explicitly **not** in the trajectory at all

Nothing added here that isn't already in the audit catalogue. All "out of scope" entries above either route to SP-4c or are rejected decisions.

## 7. Non-goals

- No audio-path changes.
- No coordinator / ViewModel changes.
- No new cross-package dependencies.
- No new analytics events (existing `.tabSelected` on `ContentView:84` sufficient).
- No localisation strings introduced.
- No SwiftData model changes.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Arrow-key handler on a `NavigationLink` consumes the key before SwiftUI can propagate it | `.onKeyPress` return `.handled` vs `.ignored` — handlers return `.handled` to stop propagation. Tested manually on iPad + Magic Keyboard during QA. |
| `focusedSongID = first.lesson.id` in `.onAppear` steals focus from search field on re-appearance | Guarded on `focusedSongID == nil`. Search field owns its own focus when active; our guard prevents re-assignment. |
| `.presentationDragIndicator(.visible)` on an `.alert`-style nested warnings sheet looks odd | These are `.sheet(isPresented:)` not alerts. Drag indicator is HIG-correct for resizable / swipe-dismissable sheets. Verified in manual QA. |
| Wide-iPad multi-column grid breaks arrow-key math | AD-3 documented limitation; graceful degradation (still navigates linearly), not broken. |

## 9. Acceptance criteria

- ✅ `LibraryFocusNavigatorTests` — 8 tests pass (Swift Testing).
- ✅ All 5 sheets in §3.2 have explicit detents + correct drag-indicator state.
- ✅ `ContentView.swift` has `.sensoryFeedback(.selection, trigger: selectedTab)`.
- ✅ Manual QA passes per §5.2.
- ✅ `LatencyContractTests` 3/3 green; p95 delta ≤ 0.5 ms.
- ✅ SVCore 93/93 green.
- ✅ Pre-existing PlayAlong suites (8 suites, ~64 tests) all green.
- ✅ Zero hardcoded platform checks (`#if os(iOS)` / `UIDevice` / `UIInterfaceOrientation`) introduced — grep clean.
- ✅ Zero new `@unchecked Sendable`, `try!`, force-unwrap, `ObservableObject`, `DispatchQueue.main.async`.

## 10. Tag + merge

- Branch: `feat/sp-4b-accessibility-remainder`
- Tag: `sp-4b-accessibility-remainder` on merge SHA.
- Tracker row: `SP-4b` in `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md` §Status table → mark ✅ shipped with tag + merge SHA + commit count.

## 11. File-count budget

- **New files: 2** — `SurVibe/Navigation/LibraryFocusNavigator.swift`, `SurVibeTests/LibraryFocusNavigatorTests.swift`.
- **Modified files: 5** — `LessonLibraryView.swift`, `SongLibraryView.swift`, `SongImportSheet.swift`, `SongEditView.swift`, `ContentView.swift`.
- Total touch: 7 files. Scope-fit matches SP-4a's narrow-cut velocity (~2–3 days).

---

*Spec author: Claude (Opus 4.7). Reviewed by: [pending — user review gate after spec-self-review].*
