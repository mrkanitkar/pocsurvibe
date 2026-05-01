# Songs → Play Along Merge — Design Spec

- **Date:** 2026-05-01
- **Author:** maheshwar (with Claude Code)
- **Status:** Draft, awaiting user review
- **Scope:** Songs tab navigation flow + Play Along main view + new Settings sheet
- **Out of scope:** Songs tab grid (screen 9067), scoring engine, notation renderers, theme system

## Goal

When the user taps a song from the Songs tab, take them directly into the Play Along screen — ready to play. Eliminate the intermediate "song detail" screen by absorbing its setup controls (Tonic Sa, parts, preview, tanpura, loop, theme) into a Settings sheet on Play Along itself.

The user is on an iPad propped on a piano music stand, with both hands on a real piano keyboard. The screen must be readable at 50–80 cm and minimize chrome so attention stays on the notation.

## Non-goals

- No change to the Songs tab grid / library / search / filters
- No change to scoring, pitch detection, notation rendering, or theme presets
- No change to the Learn tab, Home tab, or Practice flow's behavior (Practice is **deleted** — see below — but no replacement is built here)
- No iPhone-specific design (iPad landscape is the target; iPhone is a secondary fallback)

## Reference

Design driven by Apple's Simpi Piano UX as reference for minimalism: a small icon row top-left, song info center, position/tempo top-right, large notation center, keyboard hidden when external piano is connected.

## Decisions made during brainstorming

| # | Decision | Reasoning |
|---|----------|-----------|
| D1 | Direct navigation Songs → Play Along (no detail screen) | User goal: focus on learning, fewer taps |
| D2 | Settings live behind a gear icon | "Configure-then-play" workflow; chrome stays minimal |
| D3 | Play comes before Settings in the icon row | Match Simpi convention; Play is the primary action |
| D4 | Settings is a `.sheet` with `.presentationDetents([.medium, .large])` (default `.medium`) and `.presentationBackgroundInteraction(.enabled(upThrough: .medium))` | HIG-blessed non-modal pattern; `.medium` keeps notation visible behind the sheet so the "non-modal play behind" promise actually holds; `.large` is opt-in for focused settings work |
| D5 | Practice flow deleted entirely | "No release yet, no back-compat" — orphaned code is liability |
| D6 | Tempo via `Menu` (50/60/75/100/125/150% presets + Custom… → fine slider) | HIG: long-press has no pointer/keyboard equivalent; menus do |
| D7 | Tonic Sa surfaced as a tappable chip in the title strip | Most consequential control — don't bury it under gear |
| D8 | On-screen keyboard hidden when MIDI device connected | Notation gets the freed real estate |
| D9 | Toolbar icons use `accessibilityLabel` + `accessibilityHint`, no under-icon text | HIG: under-icon text labels in tight rows visually fuse. (Note: `.help()` only sets accessibility hint on iOS/iPadOS — does NOT render a visible pointer-hover tooltip, contrary to its macOS behavior. Use `accessibilityHint` directly.) |
| D10 | Standard system back button (chevron.backward), not a custom "Exit" verb | HIG: don't invent verbs for standard navigation |

## Navigation change

**Before:** `Songs tab → SongCardView → SongDetailView (push) → "Play Along" (fullScreenCover) → SongPlayAlongView`

**After:** `Songs tab → SongCardView → SongPlayAlongView (push)`

Specifically:
- `AppDestination.songDetail(Song)` is **removed** from the routing enum.
- `AppDestination.practiceMode(Song)` is **removed** (Practice flow is deleted; see "Practice flow deletion" below).
- `SongLibraryView.swift:244` changes from `NavigationLink(value: AppDestination.songDetail(song))` to `NavigationLink(value: AppDestination.playAlong(song))`.
- `SongsTab.swift` drops the `.songDetail` and `.practiceMode` case branches in `.navigationDestination(for:)`.
- `PlayAlongSceneHost` is unchanged structurally — it still owns `PlayAlongViewModel` and takes a `Song`. It is now pushed onto the Songs tab's `NavigationStack`.
- The system back gesture (swipe from leading edge) and the toolbar back button both pop to `SongLibraryView`.

## Main view layout (iPad landscape)

```
┌────────────────────────────────────────────────────────────────────┐
│ [‹] [▶] [↻]  [⚙︎]              Sukhkarta Dukhharta                  │
│                              🎹 Yamaha P-125 · [Sa = C4 ▾] · 50 BPM │
│                                                       0:00 / 1:24  │
│                                                       [Tempo 100% ▾] │
│ ┌────────────────────────────────────────────────────────────────┐ │
│ │                                                                │ │
│ │                       NOTATION (full width)                    │ │
│ │                                                                │ │
│ └────────────────────────────────────────────────────────────────┘ │
│ [─── on-screen piano (only when no external MIDI) ───]            │
└────────────────────────────────────────────────────────────────────┘
```

### Toolbar surface (Liquid Glass)

Per CLAUDE.md: the floating toolbar row, title strip, time pill, and tempo Menu pill are presented inside a single horizontally-floating container with `.glassEffect(.regular)` on iOS 26 (Liquid Glass). Notation behind remains legible; the chrome reads as a translucent floating bar. The on-screen keyboard is **content**, not chrome — does NOT get glass effect.

### Top-left toolbar (4 icon buttons, in order)

1. **`chevron.backward`** — system back; pops the navigation stack
2. **`play.fill` / `pause.fill`** — primary action; tinted blue (`.tint(.accentColor)`); flips between Play and Pause based on `viewModel.playbackState`
3. **`arrow.counterclockwise`** — Restart: stops, seeks to 0, resets scoring HUD, then `viewModel.startSession()`
4. **`gearshape`** — opens the Settings sheet; **dimmed** (reduced opacity) but still tappable when `playbackState == .playing` (visual hint, not a hard disable, per HIG)

Icons separated by fixed `Spacer().frame(width: 12)` per HIG. No under-icon text labels. `.help()` modifier + VoiceOver `accessibilityLabel` on each. Hardware-keyboard shortcuts: Spacebar = Play/Pause, ⌘R = Restart, ⌘, = Settings, Esc = back.

### Title strip (top-center)

Two lines, centered:

- **Line 1:** Song title (semibold, `.headline`)
- **Line 2 (subtitle):** Horizontal stack of distinctly styled tokens (HIG: avoid mixing tappable controls with display-only text in a single inline run). Three tokens, separated by middle-dot dividers:
  - **Input badge** (read-only): SF Symbol `pianokeys` + device name (`Yamaha P-125`) when `viewModel.isMIDIConnected`; `mic.fill` + `Mic` when mic enabled and no MIDI; hidden when neither
  - **Sa chip** (tappable Menu): pill-shaped, tinted, rendered as `Sa = C4 ▾`. Tap opens an inline `Menu` with C3–C5 options. Persists to `SongProgress.preferredSaHz`. **Hidden until VM hydration completes** (avoids flicker from the default C4 to a stored value); show a 60 ms placeholder shimmer until `didInitialHydrate == true`.
  - **BPM badge** (read-only): `50 BPM`, plain text style, distinct from the Sa chip's tinted pill style

### Top-right cluster (vertical stack)

- **Time pill:** `{elapsed} / {total}` from `viewModel.currentTime` and `viewModel.duration`
- **Tempo `Menu`:** label `Tempo {percent}% ▾`. Menu items:
  - 50%, 60%, 75%, 100%, 125%, 150%
  - Divider
  - "Custom…" — **only enabled when the Settings sheet is closed**. SwiftUI permits only one `.sheet` per presentation context; presenting a Custom sheet over the open Settings sheet would silently fail. When Settings sheet is open, the "Custom…" item is disabled with a hint to use the Tempo row inside Settings (which has the same slider+stepper). When Settings sheet is closed, "Custom…" opens a small dedicated sheet (`.presentationDetents([.medium])` — using `.medium` rather than fixed-height `.height(220)` so Dynamic Type AX5 doesn't clip) containing a fine slider (0.5×–1.5×) plus a numeric stepper (HIG: *Sliders* — supplement with stepper)
  - Persists to `SongProgress.preferredTempoScale`

### Notation area (center)

- Existing renderer dispatch by theme is unchanged: `SargamDualRowView`, `BarsOnStaffView`, `ScrollingSheetView`, `SplitLaneView`
- Width is `screenWidth - sheetWidth` when settings sheet is open (sheet uses `.presentationBackgroundInteraction(.enabled)`)
- Reflows to fill the freed 280 pt when the on-screen keyboard hides

### On-screen keyboard (bottom)

- `InteractivePianoView` rendered conditionally on `viewModel.isMIDIConnected == false`
- Cross-fades on connect/disconnect (Reduce Motion: instant swap)
- Notation area animates to absorb the freed vertical space

### Live overlays kept (unchanged)

- Correctness flash banner (green/red, 400–500 ms)
- Stuck-hint overlay
- Compact scoring HUD
- Pitch feedback bar
- Results overlay on session complete (full-screen sheet)

## Settings sheet

### Container

- SwiftUI `.sheet(isPresented: $showSettings)` triggered by the gear icon
- `.presentationDetents([.medium, .large])` — default `.medium` so the user can still see notation/keyboard behind the sheet (HIG-aligned non-modal); user can drag up to `.large` for full-height browsing
- `.presentationDragIndicator(.visible)` — explicit grabber affordance (default is hidden when sheet has interactive dismissal)
- `.presentationBackgroundInteraction(.enabled(upThrough: .medium))` — non-modal **only at `.medium`**: user can scrub timeline, hit Pause, tap on-screen keys while sheet is open. At `.large` the sheet covers the screen and background touches are blocked (user dragged up explicitly to focus on settings).
- `.presentationCompactAdaptation(.none)` — on iPad, present as a sheet, not full-cover
- Liquid Glass: apply `.glassEffect(.regular)` to the sheet's background per project rule (notation behind remains legible, sheet feels like floating chrome)
- Internal `NavigationStack` for deeper screens (Tonic Sa picker, Tanpura settings, Loop builder, Theme picker). **Note:** swipe-down dismissal of the sheet does NOT preserve internal nav-stack depth across re-opens — re-opening Settings always starts at root. The "panel returns at prior depth" guarantee in §Edge cases applies only to the Results-overlay-on-top transient, not to dismiss/reopen.
- All toggle/picker changes apply live (no Save button); persisted to `SongProgress` immediately
- VoiceOver focus moves to the sheet title on `.onAppear` via an explicit `@AccessibilityFocusState` binding (not automatic — SwiftUI's default lands on the first traversal-order element)

### Contents (top-to-bottom)

**§ Header**
- Sheet title `Settings` + close ✕ button (top trailing)

**§ Song** *(read-only context card)*
- Title, artist, badges row: Difficulty · Raag · Language · Duration

**§ Tuning**
- `Tonic Sa` — disclosure row → push to picker (C3–C5). Mirrors the Sa chip in the title strip; either entry point works. Persists to `SongProgress.preferredSaHz`.

**§ Parts**
*(Note: these are two orthogonal concepts; both are surfaced.)*
- `I'll play this part` — visible only when `Song.learnerTrackIndices.count > 1`. Disclosure or segmented control listing track candidates (e.g., "Piano", "Harmonium"). Selects which MIDI track is the learner part. Persists to `SongProgress.preferredLearnerTrackIndex`.
- `Hands` — segmented control (Both / RH / LH). Visible only when `viewModel.hasMultipleStaves`. Persists to `SongProgress.preferredHands`.
- `Preview my part` — action row with `play.fill` icon. Plays the learner track for ~5 s (existing helper). Disabled while song is playing.
- `Preview backing` — same pattern for backing track.

**§ Practice aids**
- `Wait mode` — toggle. Persists to `SongProgress.waitModeEnabled`.
- `Click track` — toggle. Persists to `SongProgress.clickTrackEnabled`.
- `Click level` — segmented (Soft / Normal / Loud), revealed only when `clickTrackEnabled == true`. Persists to `SongProgress.clickTrackLevel` (String rawValue).
- `Tanpura` — disclosure row showing current state ("Off" or "Bhairavi") → push to existing `TanpuraSettingsSheet` content (refactored to support push). Persists to `SongProgress.tanpuraEnabled` and `SongProgress.tanpuraRaga`.
- `Loop section` — disclosure → push to existing `LoopBuilderView` content (refactored). Persists to `SongProgress.loopRegionStart` and `SongProgress.loopRegionEnd`.
- `Sound` — toggle (existing in-VM `isSoundEnabled`).

**§ Input**
- `MIDI device` — read-only row. Shows connected device name or "No device connected".
- `Microphone pitch detection` — toggle. Status row shows mic permission state if denied (with "Grant access" → opens `Settings.app`).

**§ Appearance**
- `Theme` — disclosure showing current theme name → push to existing `ThemeCarouselPicker` content (refactored). Theme stays a global preference (in `AppThemeManager`), not per-song.

### Sheet behavior on session events

- **Session completes while sheet open:** Results overlay (`fullScreenCover`) appears over the sheet. On Results dismiss, the sheet remains in the state it was in (preserves user context).
- **User taps Replay from Results:** Results dismisses; sheet remains open; new session starts.
- **Pause mid-session while sheet open:** No effect on sheet.
- **Reduce Motion:** Sheet cross-fades instead of slide-up (system-handled).

## Persistence model

### SongProgress changes

`SongProgress` (path: `SurVibe/Models/SongProgress.swift` — **not** in SVCore) becomes the canonical source for per-user, per-song preferences. New fields with explicit defaults:

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `preferredHands` | `String` | `"both"` | rawValue of Both/RH/LH enum |
| `preferredTempoScale` | `Double` | `1.0` | clamped `[0.5, 1.5]` |
| `preferredLearnerTrackIndex` | `Int` | `0` | matches `Song.learnerTrackIndices` |
| `waitModeEnabled` | `Bool` | `false` | |
| `clickTrackEnabled` | `Bool` | `false` | |
| `clickTrackLevel` | `String` | `"normal"` | rawValue of Soft/Normal/Loud enum |
| `tanpuraEnabled` | `Bool` | `false` | |
| `tanpuraRaga` | `String` | `""` | empty = use song default |
| `loopRegionStart` | `Int?` | `nil` | bar index; both must be non-nil to be active |
| `loopRegionEnd` | `Int?` | `nil` | |

`preferredSaHz: Double?` already exists — unchanged.

### Song model changes

These fields move out of `Song` (which represents song *content*) and into `SongProgress` (which represents user *state*):

- `Song.lastUsedTempoScale` → **removed**; replaced by `SongProgress.preferredTempoScale`
- `Song.defaultPracticeMode` → **removed**; replaced by `SongProgress.preferredHands`

(The `Song.learnerTrackIndices` field stays — it's metadata about the song's structure, not user preference.)

### Conflict resolution (CloudKit)

**Decision: keep one `SongProgress` model; rely on CloudKit's default whole-record last-write-wins.**

CloudKit (and SwiftData over CloudKit) cannot apply per-field merge strategies on a single record — the entire record is one CKRecord and conflicts resolve at the record level. The previously-floated "last-write-wins on pref fields only" was unimplementable.

Workable approach (no schema split):
- CloudKit-level merge: last-write-wins for the whole `SongProgress` record (CloudKit default)
- Application-level merge for additive fields (`bestScore`, `timesPlayed`, `xpEarnedTotal`, etc.): the existing `recordPlay(...)` helper already uses `max(existing, new)` and additive increments before persisting. These app-level merges run in `recordPlay` regardless of CloudKit conflict resolution.
- For the new pref fields (`preferredTempoScale`, `waitModeEnabled`, etc.): no app-level merge is needed — last-write-wins is the desired semantics.
- Practical consequence: if Device A writes `bestScore = 95` and Device B writes `preferredTempoScale = 0.8` in the same sync window, CloudKit will pick one record and discard the other. The `bestScore` could regress momentarily on the losing device until the next `recordPlay` call recomputes the max. This is acceptable because (a) `recordPlay` is the only writer to `bestScore` and it always re-applies max, and (b) prefs being last-write-wins is the desired UX.

Document this choice in the `SongProgress.swift` file header so future contributors don't re-introduce field-level merge expectations.

### VM hydration

- `PlayAlongViewModel.loadPersistedSettings(from: SongProgress)` — invoked in `.task` after fetching the row; hydrates VM state from prefs
- `PlayAlongViewModel.persistSettings(to: SongProgress)` — debounced writer (reuse existing 250 ms debounce pattern from `tanpura.effectiveSaHz`)
- Initial-seed guard: `didInitialHydrate: Bool` flag prevents the first hydration from triggering a re-write
- **First-launch policy (no SongProgress row exists yet for this song):**
  1. Do NOT overwrite VM state with field defaults from a freshly-created row — that would silently disable Wait/Click/Tanpura even if a returning user expects them on
  2. Instead: keep VM at its current state (which is itself default-on-first-launch, default-from-stored-state-on-resume), persist VM state INTO the new row
  3. Set `didInitialHydrate = true` after this seed write completes
  4. Subsequent VM mutations write through normally
- All UI elements that depend on per-song prefs (Sa chip, Tempo pill, etc.) hide or show placeholder until `didInitialHydrate == true` to avoid flicker from default → stored values

### Tempo property collapse

Today there are two VM properties (`tempoScale` and `arrangementTempoScale`) and a `clampTempoScale` helper that uses an inconsistent range. **Canonicalize:**

- Single property: `tempoScale: Double`, clamped to `[0.5, 1.5]`
- Delete: `arrangementTempoScale`, `clampTempoScale` legacy helper
- All callers (toolbar pills, slider, persistence) read/write `tempoScale` only

## Practice flow deletion (B2-a)

The Practice flow is currently **only** reachable from `SongDetailView.fullScreenCover(isPresented: $showPractice)`. With detail removed, it becomes orphaned. Per "no release yet, no back-compat" rule, delete the orphaned flow.

**CRITICAL:** `SurVibe/Practice/` contains 21 files, but several are **shared infrastructure used by the live PlayAlong flow** and MUST NOT be deleted. Plan must enumerate kept files explicitly.

### Files DELETED (orphaned by SongDetailView removal — verified single-entry-point):

- `SurVibe/Practice/PracticeSessionView.swift`
- `SurVibe/Practice/PracticeAlongView.swift`
- `SurVibe/Practice/ListenFirstView.swift`
- `SurVibe/Practice/PracticeSessionSummaryView.swift`
- `SurVibe/Practice/PracticeSessionViewModel.swift`
- `SurVibe/Practice/PracticeSessionViewModel+Monitoring.swift` (extension on the deleted VM)
- `SurVibe/Practice/PracticeSessionViewModel+Raga.swift` (extension on the deleted VM)
- `SurVibe/Practice/PracticeControlsToolbar.swift` (only used by `PracticeSessionView`)
- `SurVibe/Practice/PracticeHistoryView.swift` (only used by `PracticeSessionSummaryView`)
- `SurVibe/Practice/PracticeHUD.swift` (only used by `PracticeSessionView`)
- `SurVibe/Practice/SectionBreakdownView.swift` (only used by `PracticeSessionSummaryView`)
- `SurVibe/Practice/StatCard.swift` (only used by `PracticeHistoryView` / `PracticeSessionSummaryView`)
- `SurVibe/Practice/SourceChip.swift` (only used by Practice views)
- `SurVibe/Practice/StarRatingView.swift` (only used by `PracticeSessionSummaryView` — verify; if also used by `PlayAlongResultsOverlay`, KEEP)
- `SurVibe/Practice/NoteDetailListView.swift` (only used by `PracticeSessionSummaryView`)
- `SurVibe/Practice/WaitModeSettingsView.swift` (Practice-specific)
- Companion test files for each

### Files KEPT (shared with PlayAlong — DO NOT DELETE):

- `SurVibe/Practice/PracticeSessionRecorder.swift` — instantiated at `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift:413`; persists scores at session completion. **Not Practice-specific despite the name.**
- `SurVibe/Practice/PitchProximityMeter.swift` — rendered at `SurVibe/PlayAlong/SongPlayAlongView+Subviews.swift:19` (live pitch HUD)
- `SurVibe/Practice/WaitingIndicatorOverlay.swift` — verify usage; if used by PlayAlong, KEEP
- `SurVibe/Practice/WaitModeSettingsStore.swift` — verify; if backing the new settings sheet's Wait toggle, KEEP and migrate
- `SurVibe/Practice/SwiftDataEventLogger.swift` — verify; if used by PlayAlong scoring/persistence, KEEP

### Plan-time discipline

Before deleting any file in `SurVibe/Practice/`, the plan must:
1. Grep for the file's primary type name across the whole repo
2. Confirm only Practice-flow files reference it
3. If any non-Practice file references it, either KEEP and document, or move the file to a more appropriate directory (e.g., `SurVibe/PlayAlong/` for `PracticeSessionRecorder.swift`, `SurVibe/Components/` for `PitchProximityMeter.swift`) before deletion sweep

**Recommended plan ordering:**
1. Move shared files OUT of `Practice/` to their consumer directory (rename if needed for clarity, e.g., `PracticeSessionRecorder.swift` → `SurVibe/PlayAlong/SessionRecorder.swift`)
2. Delete remaining `Practice/` files in one pass
3. Compile; let the compiler catch any missed references

If Practice features are wanted later, they get re-added under the Learn tab as a separate brainstorm/spec.

## Edge cases

### Notation availability matrix

| Has notation | Has MIDI/scoring | Behavior |
|---|---|---|
| Yes | Yes | Normal play-along (full features) |
| Yes | No | Play button disabled; thin banner above notation: "Notation only — audio scoring not available for this song" |
| No | Yes | Notation area replaced by a `ContentUnavailableView` with title "No notation", description "Listen to the song and play by ear"; Play and scoring work normally |
| No | No | Play button disabled; full-screen `ContentUnavailableView` (`music.note.list` symbol, "No notation or audio data available", "Try a different song" action that calls back) — uses iOS 17+ `ContentUnavailableView` API, available on iOS 26+ target |

### MIDI device events

- **Connect mid-session:** Keyboard cross-fades out (Reduce Motion: instant); notation expands; subtitle updates with device name
- **Disconnect mid-session:** Keyboard cross-fades in; notation contracts; subtitle reverts; playback continues uninterrupted
- **Multiple devices:** First connected device wins (existing behavior preserved)

### Settings sheet + sub-screens

- All four nested screens (Tonic Sa picker, Tanpura settings, Loop builder, Theme carousel) are refactored to support **both** sheet presentation (legacy callers, if any) and push navigation (sheet-internal stack).
- If a session completes while user is at depth 2 in the panel's nav stack, the Results overlay still appears at the front; on dismiss, the panel returns at its prior depth.

### Mic permission

- The existing `MicPermissionPrePrompt` sheet (first-launch prompt) takes priority over the settings sheet — its `.sheet` is registered before the settings sheet in the view hierarchy.
- The Mic toggle in settings displays current permission state and routes to `Settings.app` if denied.

### Tonic Sa chip vs settings row

- Both entry points write to `SongProgress.preferredSaHz` and update `viewModel.tonicSaPitch`
- Chip in title strip is a quick `Menu` (C3–C5)
- Settings row pushes a richer picker with audible reference tone

### Restart action

A NEW method on `PlayAlongViewModel` (not an extraction — the existing `onReplay` from Results overlay only calls `startSession()` because Results is shown after natural session completion). Steps:

1. `viewModel.stopAndComplete(emit: false)` — terminates current playback without firing scoring/analytics events
2. `viewModel.seek(to: 0)` — moves transport to start
3. `viewModel.scoring.reset()` — clears notes hit, accuracy, streak, longest streak, star rating, XP-this-session
4. `viewModel.startSession()` — begins playback fresh

The existing `onReplay` callback (`SurVibe/PlayAlong/SongPlayAlongView.swift:312–321`) which currently does only `startSession()` is replaced with a call to the new `restart()` method, so Replay-from-Results and toolbar-Restart share the same path.

## Accessibility

- All four toolbar icons have `accessibilityLabel` and `accessibilityHint`; no under-icon text but `.help()` for pointer hover tooltips
- Tonic Sa chip announces as "Sa, currently C4, double-tap to change" (per CLAUDE.md: "Sa sharp" not "S#")
- Settings sheet announces "Settings panel, opened" on appear; ✕ labeled "Close settings"
- Reduce Motion: panel cross-fades; keyboard hide/show cross-fades; notation reflows without animation
- Dynamic Type: title strip uses `.headline` semantic font; subtitle uses `.subheadline`; settings rows use `.body`; tempo/time pills stay fixed-size (compact data-display)
- VoiceOver focus moves into the settings sheet on open; Esc gesture (two-finger Z) dismisses
- Hardware keyboard: Space, ⌘R, ⌘,, Esc as listed above

## Files affected

### Deleted
- `SurVibe/Songs/SongDetailView.swift`
- `SurVibe/Songs/SongDetailViewParts.swift`
- `SurVibe/Songs/PlaybackControlsView.swift` (orphaned)
- `SurVibe/Practice/PracticeSessionView.swift`
- `SurVibe/Practice/PracticeAlongView.swift`
- `SurVibe/Practice/ListenFirstView.swift`
- `SurVibe/Practice/PracticeSessionSummaryView.swift`
- `SurVibe/Practice/PracticeSessionViewModel.swift`
- `SurVibe/SurVibeTests/SongDetailViewPartsTests.swift` — port helpers and tests:
  - `noteName(_:)` (MIDI pitch → "C4" / "F#3" formatter) → port to `SurVibe/Notation/WesternNoteHelper.swift` if not already present (verify; existing helper has similar concerns)
  - `trackLabels(for:)` (derives track display labels from song metadata) → port to a new extension `SurVibe/Songs/Song+TrackLabels.swift` (`extension Song { static func trackLabels(for: Song) -> [String] }`)
  - Migrate the corresponding `@Test` cases to `WesternNoteHelperTests.swift` and a new `SongTrackLabelsTests.swift`
- Tests for any deleted Practice files
- `SurVibeTests/SongPlayAlongFieldsTests.swift` — entirely tests `Song.defaultPracticeMode` and `Song.lastUsedTempoScale`; both fields are removed, so the test file becomes meaningless. Delete; replacement coverage lives in new `SongProgress` tests.
- `SongDetailViewResolver` (private struct in `SongsTab.swift`) — dead code

### Modified
- `SurVibe/Navigation/AppDestination.swift` — remove `.songDetail`, `.practiceMode` cases
- `SurVibe/Navigation/AppRouter.swift` — update doc comment example referencing `.songDetail`
- `SurVibe/SongsTab.swift` — remove `.songDetail` and `.practiceMode` case branches; remove resolver
- `SurVibe/Songs/SongLibraryView.swift` — `NavigationLink(value: .playAlong(song))` (line ~244)
- `SurVibe/PlayAlong/SongPlayAlongView.swift` — new minimal toolbar; conditional keyboard; gear → sheet; Sa chip; tempo Menu; remove dead `notationAndChrome` toolbar instance
- `SurVibe/PlayAlong/PlayAlongToolbar.swift` — full rewrite as minimal 4-icon toolbar + title block + tempo/progress cluster
- `SurVibe/PlayAlong/PlayAlongViewModel.swift` — add `loadPersistedSettings`, `persistSettings`, `restart()`; collapse `arrangementTempoScale` into `tempoScale`; remove `clampTempoScale` legacy helper
- `SurVibe/PlayAlong/TanpuraSettingsSheet.swift` — refactor to support push navigation (extract content body)
- `SurVibe/PlayAlong/LoopBuilderView.swift` — same
- `SurVibe/Profile/ThemeCarouselPicker.swift` — same (note: lives under `Profile/`, not `PlayAlong/`)
- `SurVibe/Models/SongProgress.swift` — add new pref fields with defaults
- `SurVibe/Models/Song.swift` — remove `lastUsedTempoScale`, `defaultPracticeMode`
- `SurVibe/SurVibeTests/CrossAppThemeContractTests.swift` — update lines 24 (`SongDetailView.swift` reference) AND 28 (`PlaybackControlsView.swift` reference); both are deleted files
- `SurVibeTests/PlayAlong/PlayAlongToolbarStateTests.swift` — references `defaultPracticeMode`; rewrite tests against `SongProgress.preferredHands` instead
- `SurVibeTests/PlayAlong/ArrangementPlayerTests.swift` — references `defaultPracticeMode` (line ~184); rewrite
- `SurVibeTests/PlayAlong/PlayAlongToolbarTests.swift` — tests `PlayAlongToolbar.clampTempoScale` (lines 49–74). With `clampTempoScale` removed and tempo collapsed to a single canonical range, rewrite or delete this test file
- `SurVibeTests/PlayAlong/PlayAlongViewModelE1Tests.swift` — references `arrangementTempoScale`; rewrite to use `tempoScale`
- `SurVibeTests/LearnASongIntegrationTests.swift` — references `arrangementTempoScale`; rewrite to use `tempoScale`

### Created
- `SurVibe/PlayAlong/PlayAlongSettingsSheet.swift` — sheet container + section subviews
- `SurVibe/PlayAlong/PlayAlongSettingsRows.swift` — reusable row components (DisclosureRow, ToggleRow, SegmentedRow, ActionRow, ChipRow)
- `SurVibe/SurVibeTests/PlayAlongSettingsSheetTests.swift` — Swift Testing tests for sheet behavior + persistence wiring
- `SurVibe/SurVibeTests/SongPlayAlongViewLayoutTests.swift` — tests for conditional keyboard rendering, tempo menu, restart action

## Risks

- **`Song` schema change** (removing two fields): if any data has been seeded or shipped to TestFlight in development, those records lose those fields. Per project rule (no release yet), this is acceptable; document in commit message.
- **Last-write-wins on prefs** is a deliberate departure from the project's additive-only CloudKit rule. Limit the scope to the named pref fields. Other `SongProgress` fields (XP, accuracy, completion) remain additive-merge.
- **Refactoring three sheets** (Tanpura, Loop, Theme) to support push-navigation increases blast radius. Mitigation: extract the body of each into a `*Content` view that the sheet wraps; the panel pushes the same `*Content` view directly.
- **Persistence reactive loops:** with 9 new persisted fields, the existing `tanpura.effectiveSaHz` debounce pattern must be uniformly applied. Spec mandates a single shared debounce + initial-seed gate. If implementation deviates, expect oscillation bugs.
- **Tempo property collapse** touches every existing tempo call site. Risk of missed call site → silent ignored value. Mitigation: delete `arrangementTempoScale` first; let the compiler find every reference.

## Open questions (none blocking)

- Should the Sa chip in the title strip allow values outside C3–C5 (existing range)? Out of scope for this merge — keep current range.
- Should "I'll play this part" remember per-song or be reset on each session? Spec says per-song persistence; user can change in settings.
- Should "Restart" trigger an audible cue (countdown clicks)? Out of scope; preserves existing `startSession()` behavior.

## Success criteria

1. Tapping any song from the Songs tab pushes directly into Play Along — no detail screen
2. Settings sheet contains all configuration the old detail screen exposed (plus existing Play Along toolbar items), and persists per-song
3. On-screen keyboard is hidden when an external MIDI device is connected; notation expands to fill
4. No references to `SongDetailView`, `SongDetailViewParts`, `AppDestination.songDetail`, `.practiceMode`, or any deleted Practice file remain in the codebase
5. All existing PlayAlong tests pass; new tests cover the new layout, conditional keyboard, settings persistence, and tempo collapse
6. SwiftLint and `xcodebuild clean build` pass with zero warnings
7. VoiceOver, Reduce Motion, and Dynamic Type at AX5 all behave correctly on the new toolbar and sheet
