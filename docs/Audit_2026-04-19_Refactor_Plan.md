# SurVibe Audit 2026-04-19 — Refactor Plan

> Prioritised, actionable punch list drawn from all 2026-04-19 audit docs.
> P0 = ship-blocker for iPad-first positioning. P1 = before next major release. P2 = nice-to-have.
> Effort: S (≤1 day), M (2–5 days), L (>1 week).
>
> **Status legend (added 2026-04-19 post-SP-0 + SP-1):**
> `DONE` = shipped to main · `DEFERRED-TO-SP-N` = carried forward into a named sub-project · `PENDING` = not yet scheduled.
> Live sub-project tracker: [docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md](superpowers/plans/SP-TRAJECTORY-TRACKER.md).

Cross-refs: `Audit_2026-04-19_Executive_Summary.md`, `Audit_2026-04-19_HIG_Compliance.md`, `Audit_2026-04-19_iPad_First.md`, `Audit_2026-04-19_iPhone.md`, `Audit_2026-04-19_Mac_Readiness.md`, `Audit_2026-04-19_Architecture.md`, `Audit_2026-04-19_GenerativeAI_HIG.md`.

---

## P0 — Ship-blocker (iPad-first positioning)

### P0-1. Sidebar-adaptable TabView — **DONE (SP-1, 685d1c7)**
- **What:** Apply `.tabViewStyle(.sidebarAdaptable)` on `ContentView`'s `TabView`.
- **Files:** `SurVibe/ContentView.swift:35`.
- **Effort:** S.
- **Acceptance:** On iPad regular-width, the tab bar renders with a sidebar toggle button; clicking it converts the tab bar into a left-edge sidebar. iPhone compact-width layout unchanged.
- **Reference:** [Tab bars > iPadOS](https://developer.apple.com/design/human-interface-guidelines/tab-bars#iPadOS).

### P0-2. NavigationSplitView for Songs + Learn — **DEFERRED-TO-SP-2**
- **What:** On `horizontalSizeClass == .regular`, wrap `SongsTab` and `LearnTab` in `NavigationSplitView { list } detail: { detail }`. Preserve compact `NavigationStack` path.
- **Files:** `SurVibe/SongsTab.swift`, `SurVibe/LearnTab.swift`, `SurVibe/Songs/SongLibraryView.swift`, `SurVibe/Learn/LessonLibraryView.swift`, `SurVibe/Navigation/AppDestination.swift`.
- **Effort:** M.
- **Acceptance:** On a 13" iPad in portrait, `SongsTab` shows Library in a 320–375pt primary column and `SongDetailView` fills the remainder. Tapping a song updates the detail column without pushing. iPhone UI unchanged.

### P0-3. CommandMenu for Practice + Songs + Navigation — **PARTIAL (Navigate + ⌘, DONE in SP-1; transport + surface commands DEFERRED-TO-SP-2)**
- **What:** Add `.commands { CommandMenu("Practice") { ... } ... }` to `SurVibeApp.body`. Include Space = play/pause, ⌘. = stop, ⌘W = wait-mode toggle, ⌘T = tanpura, ⌘L = library, ⌘N = new song, ⌘, = settings.
- **SP-1 shipped:** `CommandMenu("Navigate")` with ⌘1–⌘4 + `CommandGroup(replacing: .appSettings)` with ⌘,. Remaining transport / find / new commands land in SP-2 with `@FocusedValue` for per-surface dispatch.
- **Files:** `SurVibe/SurVibeApp.swift:219`.
- **Effort:** S.
- **Acceptance:** iPad connected to Magic Keyboard shows a menu bar with three menus; each shortcut works from any focused surface.

### P0-4. `.hoverEffect` on every tappable card — **PARTIAL (DoorCard + 5 ProfileTab rows DONE in SP-1; Songs / Learn / Theme / Achievement rows DEFERRED-TO-SP-2)**
- **What:** Add `.hoverEffect(.automatic)` to: `DoorCard`, `SongCardView`, `SongListRow`, `FilterChip`, `LessonCardView`, `CurriculumCardView`, `ThemePreviewCard`, `AchievementPreviewSection` row items.
- **SP-1 shipped:** `DoorCard.swift:96` and ProfileTab lines 243, 257, 269, 288, 304. Remaining cards land with SP-2's Songs/Learn deep-layout work.
- **Files:** `SurVibe/Components/DoorCard.swift`, `SurVibe/Songs/SongCardView.swift`, `SurVibe/Songs/SongListRow.swift`, `SurVibe/Songs/FilterChip.swift`, `SurVibe/Learn/LessonCardView.swift`, `SurVibe/Learn/Curriculum/CurriculumCardView.swift`, `SurVibe/Profile/ThemePreviewCard.swift`.
- **Effort:** S (per file, ~1 line).
- **Acceptance:** Trackpad pointer hovering any card shows the system highlight effect.

### P0-5. Piano `pitchRange` adapts to width — **DEFERRED-TO-SP-2**
- **What:** Replace hardcoded `Pitch(36)...Pitch(96)` with a computed range based on `GeometryReader` width. Compact: 61 keys (C2–C7). Regular: 73 keys (C2–C8) or 88 keys (A0–C8) depending on width.
- **Verified 2026-04-19:** Still hardcoded at `SurVibe/Audio/InteractivePianoView.swift:121` (`layout: .piano(pitchRange: Pitch(36) ... Pitch(96))`).
- **Files:** `SurVibe/Audio/InteractivePianoView.swift:120-128`, `SurVibe/PianoKeyboardView.swift`.
- **Effort:** M.
- **Acceptance:** iPhone SE shows 61 keys; 13" iPad landscape shows 88 keys; all taps still route to `onNoteOn`.

### P0-6. Migrate PlayAlongToolbar + PracticeControlsToolbar to `.toolbar {}` — **DEFERRED-TO-SP-2**
- **What:** Replace custom overlay `PlayAlongToolbar` with system `.toolbar { ToolbarItemGroup(placement: ...) { ... } }` so Liquid Glass is applied automatically.
- **Files:** `SurVibe/PlayAlong/PlayAlongToolbar.swift`, `SurVibe/PlayAlong/SongPlayAlongView.swift`, `SurVibe/Practice/PracticeControlsToolbar.swift`, `SurVibe/Practice/PracticeSessionView.swift`.
- **Effort:** M.
- **Acceptance:** Toolbars show Liquid Glass background that scrolls-under content; iPad regular-width renders leading/trailing groups.

---

## P1 — Before next release

### P1-1. Decompose PlayAlongViewModel — **DEFERRED-TO-SP-3** (flag `FeatureFlag.playAlongViewModelV2` landed in SP-0 F4 ready for A/B gating)
- **What:** Split 1,828-line class into `PlayAlongPlaybackCoordinator`, `PlayAlongInputRouter`, `PlayAlongScorer`, `PlayAlongChromeController`, thin `PlayAlongViewModel` facade.
- **Files:** `SurVibe/PlayAlong/PlayAlongViewModel.swift` (+ new files under `PlayAlong/`).
- **Effort:** L.
- **Acceptance:** No single class >400 lines; all existing integration tests pass; no behavior changes.

### P1-2. Live Activity for active practice — **PENDING**
- **What:** New Widget extension `SurVibePracticeActivity` using `ActivityKit`. Publishes: song title, elapsed time, accuracy %.
- **Files:** new target `SurVibeWidgets/`, new types in `SurVibe/Practice/`.
- **Effort:** L.
- **Acceptance:** Active practice shows Dynamic Island leading (song icon) + trailing (timer). Expanded view shows title + accuracy ring.

### P1-3. Landscape play-along layout — **DEFERRED-TO-SP-2**
- **What:** In `SongPlayAlongView`, branch on `verticalSizeClass == .compact` (iPhone landscape) or `horizontalSizeClass == .regular` (iPad) and place keyboard + notation side-by-side.
- **Files:** `SurVibe/PlayAlong/SongPlayAlongView.swift:69-...`.
- **Effort:** M.
- **Acceptance:** iPhone 17 Pro Max landscape is playable with ≥200pt notation visible; iPad 13" landscape uses the left 60% for notation, right 40% for keyboard.

### P1-4. Apple Pencil annotation on notation — **PENDING**
- **What:** Overlay a `PKCanvasView` on `ScrollingSheetView` gated behind a pencil icon toggle. Persist per-(userId, songId) strokes in SwiftData.
- **Files:** `SurVibe/PlayAlong/ScrollingSheetView.swift`, new `SurVibe/Models/NotationAnnotation.swift`.
- **Effort:** L.
- **Acceptance:** Pencil strokes persist across sessions and sync via CloudKit; reset button clears them.

### P1-5. Hand colors moved into Rang theme — **DEFERRED-TO-SP-4**
- **What:** Replace hardcoded `.blue / .red / .purple` defaults in `InteractivePianoView` with `.rangHandRH / .rangHandLH / .rangHandBoth` — defined in `SVCore/Theme/RangColorSystem.swift` with light+dark asset variants.
- **Files:** `SurVibe/Audio/InteractivePianoView.swift:78-90`, `Packages/SVCore/Sources/SVCore/Theme/RangColorSystem.swift`.
- **Effort:** S.
- **Acceptance:** Dim Mode, Light Mode, Dark Mode, and high-contrast all render correctly; WCAG AA passes on key highlights.

### P1-6. Differentiate-without-color on key highlights — **DEFERRED-TO-SP-4**
- **What:** When `@Environment(\.accessibilityDifferentiateWithoutColor) == true`, overlay "R" / "L" letter on highlighted keys.
- **Files:** `SurVibe/Audio/InteractivePianoView.swift`.
- **Effort:** S.
- **Acceptance:** VoiceOver + Differentiate Without Color enabled still distinguishes hands.

### P1-7. `accessibilityLabel` on Devanagari note views — **DEFERRED-TO-SP-4**
- **What:** Every `SargamNoteView` instance gets `.accessibilityLabel("Sa")` etc. — canonical transliteration.
- **Files:** `SurVibe/Notation/SargamNoteView.swift`, `SurVibe/Notation/SargamRenderer.swift`.
- **Effort:** S.
- **Acceptance:** English VoiceOver reads "Sa" rather than Devanagari character by character.

### P1-8. Pinch-to-zoom on notation — PARTIALLY DONE (hostile review 2026-04-19) · **REMAINDER DEFERRED-TO-SP-4**
- **Correction:** `NotationContainerView` already implements `MagnificationGesture` clamped 0.5x–3.0x at [line 171](SurVibe/Notation/NotationContainerView.swift:171). Scope reduces to:
  - Verify `ScrollingSheetView` (the play-along notation scroller) inherits the gesture — if it doesn't, add it there.
  - Add a double-tap to reset to 1.0x (not currently implemented).
- **Effort:** S (was M).
- **Acceptance:** Pinch scales notation smoothly; double-tap resets to 1.0x.

### P1-9. Optional skip on onboarding — **DEFERRED-TO-SP-4**
- **What:** Add "Skip for now" button on step 1 of `OnboardingContainerView`. On skip, applies defaults and dismisses.
- **Files:** `SurVibe/Onboarding/OnboardingContainerView.swift`, `SurVibe/Onboarding/OnboardingLanguageView.swift`.
- **Effort:** S.
- **Acceptance:** Skipping the flow writes defaults to `UserProfile`; user can run onboarding later from Settings.

### P1-10. Pre-prompt for mic permission — **DEFERRED-TO-SP-4**
- **What:** In-app affordance explaining why mic is needed *before* the system alert.
- **Files:** new `SurVibe/Components/MicPermissionPrePrompt.swift`, invoked from `PracticeSessionView` + `PlayAlong` entry.
- **Effort:** S.
- **Acceptance:** First time mic is requested, user sees a branded explanation + a "Continue" button that triggers the system prompt.

### P1-11. GenAI compliance harness (pre-build) — **DEFERRED-TO-SP-5** (SP-0 landed enabling pieces: `PreferenceStoring` protocol, `FeatureFlag.onDeviceAI`, analytics events `aiConsentShown/Granted/Revoked`)
- **What:** Build `AIGeneratedBadge`, `AIDisclosureSheet`, `AIFeedbackControl`, `PromptSanitiser`, Settings toggle `useAIFeatures`, analytics events. Even though no AI ships today, the harness must exist before the first provider lands.
- **Files:** `Packages/SVCore/Sources/SVCore/Components/`, `Packages/SVAI/Sources/SVAI/Sanitisation/`, `Packages/SVCore/Sources/SVCore/Analytics/AnalyticsEvent.swift`.
- **Effort:** M.
- **Acceptance:** `AIDisclosureSheet(feature: .coach)` renders correctly; toggling `useAIFeatures` halts all `AIProviderRouter` requests.

---

## P2 — Nice-to-have

### P2-1. Dim-mode verification across Liquid Glass surfaces — **PENDING**
- **Effort:** S. Files: the 3 `.glassEffect` users. Verify no legibility regression when Dim Mode is on.

### P2-2. `.sensoryFeedback` / `HapticEngine` on success paths — **PENDING**
- **Hostile-review correction 2026-04-19:** SVCore already ships a `HapticEngine` with three `UIFeedbackGenerator` instances ([Packages/SVCore/Sources/SVCore/Accessibility/HapticEngine.swift:13-15](Packages/SVCore/Sources/SVCore/Accessibility/HapticEngine.swift:13)) and `.sensoryFeedback(.selection, ...)` is already used in [ThemeCarouselPicker.swift:40](SurVibe/Profile/ThemeCarouselPicker.swift:40). Task is to *invoke* these on: achievement unlock, correct-note flash, XP award, lesson completion — not to introduce a new haptic stack.
- **Files:** `SurVibe/Components/AchievementUnlockToast.swift`, `SurVibe/Learn/LessonCompletionView.swift`, `SurVibe/PlayAlong/SongPlayAlongView.swift`.
- **Effort:** S.

### P2-3. `AppIntent` for "Start riyaz for N minutes" — **PENDING**
- Creates a Shortcut + Focus filter entry point.
- **Effort:** M.

### P2-4. Multi-window for play-along — **PENDING**
- `WindowGroup(for: Song.ID.self) { ... }` + `openWindow(value: song.id)`.
- **Effort:** L.

### P2-5. External display scene (mirror notation) — **PENDING**
- Secondary scene that displays `ScrollingSheetView` only; main iPad remains interactive.
- **Effort:** L.

### P2-6. `@FocusState` on lesson/song cards — **DEFERRED-TO-SP-2** (pairs with transport shortcuts)
- Arrow-key navigation through library cards.
- **Effort:** M.

### P2-7. SVAudio macOS port — **DEFERRED-TO-SP-6**
- Wrap `AudioSessionManager` in `#if os(iOS)`; add macOS no-op path; set `.platforms: [.iOS(.v26), .macOS(.v15)]`.
- **Effort:** M.

### P2-8. Designed-for-iPad Mac interim ship — **DEFERRED-TO-SP-6**
- Toggle `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES` **after** P0s land. Guarded by `FeatureFlag.macDestination` (SP-0 F4).
- **Effort:** S.

### P2-9. TipKit migration for in-context hints — **PENDING**
- Replace any "first-time" coach marks with TipKit `Tip`s.
- **Effort:** M.

### P2-10. Test coverage: SVAdvanced + SVSocial — **PENDING**
- Raise each to minimum 1 test per public type.
- **Effort:** S-M.

### P2-11. Add manual `schemaVersion` gate — **DONE (pre-SP-0, confirmed present at `SurVibeApp.swift:84`)**
- Original claim (2026-04-19 hostile review) said this gate was ABSENT. Re-verification 2026-04-19 post-SP-0 confirms `SurVibeApp.createProductionContainer` reads `UserDefaults.standard.integer(forKey: "survibe_schema_version")`, deletes the store on version bump, and resets seed content. `currentSchemaVersion = 7`.
- Item marked **DONE** — if the gate needs further hardening, file a new item.
- **Effort:** S (now 0).

### P2-12. Presentation detents on sheets — **PENDING**
- Audit every `.sheet(...)` for appropriate `.presentationDetents([.medium, .large])` + drag indicator.
- **Effort:** S-M.

### P2-13. Haptics on tab switch — **PENDING**
- `.sensoryFeedback(.impact(weight: .medium), trigger: selectedTab)` in `ContentView`.
- **Effort:** S.

### P2-14. Focus filters for riyaz mode — **PENDING**
- Integrate with iOS Focus to dim notifications during practice.
- **Effort:** M.

---

## Recommended execution order (fastest path to "iPad-first" grade)

**Sprint 1 (2 weeks):** P0-1 → P0-4 → P0-3 → P0-6 → P0-5 → P0-2
*Outcome: iPad UX jumps from "Missing" to "Good".*

**Sprint 2 (2 weeks):** P1-1 (decompose VM) + P1-3 (landscape) + P1-5/6/7 (color/accessibility) + P1-9 (skip onboarding).
*Outcome: Code health, iPhone UX, accessibility all level-up.*

**Sprint 3 (2–3 weeks):** P1-2 (Live Activity) + P1-4 (Pencil) + P1-11 (GenAI harness) + P1-8 (pinch zoom) + P1-10 (mic pre-prompt).
*Outcome: Platform depth on iPhone, iPad Pencil story, AI-safety runway ready.*

**Sprint 4 (1 week or opportunistic):** P2s as they fit. P2-7 + P2-8 unlock an interim Mac ship after iPad-first is done.

---

## What this plan does **not** touch

- `docs/Architecture_Audit_Report.md` v3.1 open items (MAJ-2 ChordScoreCalculator not wired, MIN-7a, MIN-21). Those remain separately tracked and don't need this audit to close them.
- Existing deferred items (Metal notation renderer, fingering suggestions).
- Content pipeline / song import work — not in scope for this audit.

---

## Audio latency safety (MANDATORY — added 2026-04-19)

SurVibe targets 3–10 ms audio latency. None of the P0/P1/P2 tasks may regress this
budget. Every task above inherits the guardrails below; two tasks (P1-1 VM split,
P2-7/8 Mac port) carry HIGH risk and may only land under the explicit contracts
here.

### Cross-cutting rules (apply to every phase)

- `/latency-check` is a merge gate for every task in this plan. Red build blocks merge.
- `LatencyContractTests.swift` p95 delta must be ≤ 0.5 ms vs the pre-task baseline.
- No new `await` boundaries on the note-on critical path (MIDI input → `AudioEngineManager.shared.noteOn`).
- Haptics (`UIImpact*FeedbackGenerator`, `.sensoryFeedback`) must be MainActor-dispatched, **never** called from audio tap or MIDI callback.
- UI changes that swap view lifecycle (rotation, size-class branching) must not re-init `AudioEngineManager`. VMs hosting audio state must outlive the view swap.

### Per-task latency risk

| Task | Risk | Guardrail |
|---|:---:|---|
| P0-1 sidebarAdaptable | ✅ None | — |
| P0-2 NavigationSplitView | ✅ None | — |
| P0-3 CommandMenu / keyboardShortcut | ⚠️ Low | Bind shortcuts to existing main-thread VM methods; no Task spawn per keypress |
| P0-4 hoverEffect sweep | ✅ None | — |
| P0-5 Piano pitchRange adapts to width | ⚠️ Low | Add test: pitchRange change must NOT call `SoundFontManager.load` or touch `AVAudioUnitSampler`. `InteractivePianoView` is view-only; sampler lives in `AudioEngineManager.shared`. |
| P0-6 Hand color tokens | ✅ None | — |
| P1-1 Decompose PlayAlongViewModel | 🔴 **HIGH** | See **VM split contract** below. Feature-flagged rollout required. |
| P1-2 Live Activity / Dynamic Island | ✅ None | Live Activity runs in separate process |
| P1-3 Landscape play-along | ⚠️ Medium | Rotation must not tear down VM. Hoist VM into parent scene. Add UI test: rotation mid-playback does not call `AudioEngineManager.start()` twice. |
| P1-4 Pencil on notation | ✅ None | UIKit overlay, no audio path |
| P1-5 Differentiate without color | ✅ None | — |
| P1-6 Devanagari accessibilityLabel | ✅ None | — |
| P1-7 FallingNotes reduce-motion | ✅ None | — |
| P1-8 Pinch-zoom completion | ✅ None | — |
| P1-9 Skip onboarding | ✅ None | — |
| P1-10 Mic pre-prompt | ⚠️ Low | Do not change the order of `AVAudioSession.setActive(true)` — only add a pre-prompt ahead of it |
| P1-11 GenAI harness | ⚠️ Low–Med | On-device LLM inference must NOT run during active play-along (CPU contention). Add `PlaybackState.isActive` gate in `SVAI.generate()`; add `testAIDoesNotRunDuringPlayback`. |
| P2-1 Toolbar → system `.toolbar{}` | ✅ None | — |
| P2-2 Wire haptics | ⚠️ Low | MainActor-only; never from audio tap |
| P2-3..6 (misc UX) | ✅ None | — |
| P2-7 Mac destination | ✅ None | Build config only |
| P2-8 Mac audio-session validation | 🔴 **HIGH** | macOS `AVAudioSession` differs (no activation, no category). Port `LatencyContractTests` to Mac CI with Mac-specific p95 budget (5–15 ms expected). Mac audio ships ONLY when those tests are green. |
| P2-11 schemaVersion gate | ✅ None | Startup-only |

### VM split contract (P1-1) — non-negotiable invariants

A naive split of `PlayAlongViewModel` into actors can add 1–10 ms of actor hopping
and destroy the 3–10 ms budget. This contract defines the only acceptable split.

1. **Single-hop note-on.** MIDI input → `AudioEngineManager.shared.noteOn(...)` stays synchronous on the arriving thread. No `await` boundary on the audio path. No new actor between MIDI callback and sampler.
2. **New actors receive copies, not calls.** Scoring, diagnostics, and chrome coordinators consume note events via `SPSCRingBuffer` snapshots or `Mutex<State>` reads. They are never called *from* audio-thread code.
3. **`MIDIInputManager` stays `NSLock`-guarded**, not `@MainActor`-isolated (CoreMIDI callbacks arrive on arbitrary threads — per CLAUDE.md).
4. **Lock-free display reads.** `MIDINoteHighlightCoordinator` owns the 60 Hz CADisplayLink and takes snapshots. The split preserves this pattern — the coordinator does not move to an actor.
5. **Regression gate.** `LatencyContractTests` + `LatencyProbe` p95 delta ≤ 0.5 ms vs pre-split baseline. Feature-flagged A/B; old VM deleted only after one sprint of clean p95 data.

Proposed split boundaries (all MainActor unless noted):
- `PlaybackCoordinator` — transport, wait-mode, seek; delegates to `SongPlaybackEngine`.
- `ScoringCoordinator` — pure computation over ring-buffer snapshots; off critical path.
- `WaitController` — already extracted; stays.
- `NoteRouter` (new) — the single site that calls `noteOn/off` on the engine; stays main-thread, no actor inside.
- View-chrome state moves into `SongPlayAlongView+Subviews.swift`.

### Mac port audio contract (P2-8)

- `AudioSessionManager.swift` gets a `#if os(macOS)` branch that skips `AVAudioSession.setCategory(...)` / `setActive(...)` (those APIs are iOS-only).
- Default sample rate on Mac is typically 48 kHz (vs 44.1 kHz on iOS); sample-rate-dependent math in `MicPitchDetector` / `YINPitchDetector` must be verified.
- Mac-specific `LatencyContractTests` target runs on CI with its own budget.
- AudioKit 5.6 + SoundpipeAudioKit support macOS — no dependency swap needed.

---
## Hostile-review verification — 2026-04-19

- Claims checked: 9 (items where specific file/line claims or "missing" assertions were load-bearing)
- Confirmed: 6
- Confirmed-but-imprecise (fixed): 0
- Unsupported (struck or corrected): 0
- Wrong (replaced): 3

### Notable corrections
- **P1-8 Pinch-to-zoom:** already implemented on `NotationContainerView:171`. Effort reduces from M to S; scope is just `ScrollingSheetView` inheritance + double-tap reset.
- **P2-2 Haptics:** `HapticEngine` in SVCore + `.sensoryFeedback` in `ThemeCarouselPicker` already exist. Task is to wire, not to build.
- **P2-11 schemaVersion:** confirmed ABSENT — was "verify" in original plan, now a clear open task.
