# Play Tab v2 — Parallel Execution Plan

> Companion to [docs/superpowers/plans/2026-04-29-play-tab-v2.md](./2026-04-29-play-tab-v2.md) (commit `84df16f`).
>
> The base plan describes 16 TDD tasks (§16 split into 4 sub-tasks, totalling 19). This document re-organises them into **dependency-aware waves** so multiple subagents can execute in parallel using the worktree-isolation pattern.

---

## Why this exists

The base plan is sequential — fine for a single human or single agent. With a 1M-context-window orchestrator and the ability to dispatch isolated worktree subagents, we want to collapse total wall-clock time. The longest critical path is **Wave 0 → T1 → T3+T5 → T6 → T14 → T15**: roughly 6 wall-clock waves vs the 16 sequential commits the base plan implies (≈2.5× speedup).

Two execution rules govern parallelism:

1. **Each subagent runs in an isolated git worktree** (`Agent({ isolation: "worktree" })`). Tasks touching the same files run in different waves OR resolve via auto-merge. The orchestrator merges back into the trunk after each wave's tests pass.
2. **Latency-critical wiring (T6) is always single-agent.** Phase 1 / Phase 2 input handling is the riskiest code in the plan; running parallel agents here is a bug-multiplier.

---

## Task numbering — recap from base plan

| # | Task | Surface |
|---|---|---|
| T1 | SVCore value types (`RecordedNote`, `RecordedSustainEvent`, `MusicalDuration`, `QuantizedNote`, `QuantizedScore`, `HighlightSink`) | SVCore |
| T2 | Move `SargamLabeler` + `SargamLabel` to SVCore | SVCore + app |
| T3 | Rewrite v1 `RecordedNote` call sites | App target |
| T4 | `RecordedTake` `@Model` + `ModelContainer` registration | App target |
| T5 | `ScratchpadState` | App target |
| T6 | Wire scratchpad to `MIDIInputManager` + touch (Phase 1 / 2) | App target — **latency critical** |
| T7 | Soft / hard cap UI | App target |
| T8 | `Quantizer` | SVCore |
| T9 | `MIDISerializer` + golden fixture | SVCore |
| T10 | `MusicXMLSerializer` + golden fixture | SVCore |
| T11 | `MXLPackager` | SVAudio |
| T12 | `MultiChannelEngineProtocol` extension + `ProductionMultiChannelEngine` impl | SVAudio |
| T13 | `TakePlaybackEngine` + `HighlightSink` conformance | SVAudio + app |
| T14 | Bottom strip + Expanded Timeline Sheet (Staff tab) | App target |
| T15 | Waterfall tab + visual-sync hookup | App target |
| T16a | Save sheet + take materialization | App target |
| T16b | Takes list sheet (CRUD + delete-undo + rename) | App target |
| T16c | Export sheet + Quantize sheet + ShareLink | App target |
| T16d | Unsaved Scratchpad Guard + ContentView/AppRouter wiring | App target |

---

## Dependency graph (textual)

```
Wave 0 — 4 parallel agents, no inter-task deps
├── T1   SVCore value types
├── T2   Move SargamLabeler            (independent of T1; different SVCore subdir)
├── T11  MXLPackager (SVAudio)         (only depends on ZIPFoundation, already a dep)
└── T12  MultiChannelEngineProtocol    (only adds methods to existing SVAudio types)

Wave 1 — 5 parallel agents, after T1 lands
├── T3   Rewrite v1 RecordedNote sites (depends on T1)
├── T4   RecordedTake @Model           (depends on T1)
├── T5   ScratchpadState               (depends on T1)
├── T8   Quantizer                     (depends on T1)
└── T9   MIDISerializer                (depends on T1)

Wave 2 — 4 parallel agents + 1 sequential, after Wave 1
├── T10  MusicXMLSerializer            (depends on T1+T8)
├── T13  TakePlaybackEngine            (depends on T1+T9+T12)
├── T16a Save sheet + materialize      (depends on T4+T5)
├── T16b Takes list                    (depends on T4)
└── T6   ★ SEQUENTIAL ★ Phase 1/2 wiring (depends on T3+T5)
        Runs alongside the four parallel agents in its own worktree;
        merges last in this wave because the merge target moves the most.

Wave 3 — 4 parallel agents, after Wave 2
├── T7   Soft/hard cap UI              (depends on T5+T6)
├── T14  Bottom strip + Expanded Sheet (depends on T5+T6+T13)
├── T16c Export + Quantize + Share     (depends on T4+T8+T9+T10+T11)
└── T16d Unsaved guard + ContentView   (depends on T5+T6)

Wave 4 — 1 agent
└── T15  Waterfall tab + visual sync  (depends on T13+T14)
```

A Mermaid version of the same graph lives in the `validate_and_render_mermaid_diagram` tool history of the orchestrator session.

---

## File-conflict map (to plan merge order within a wave)

When two tasks in the same wave touch the same file, the orchestrator merges them in a deterministic order to minimise rebase cost.

| File | Tasks that touch it |
|---|---|
| `Packages/SVCore/Sources/SVCore/Models/Play/*` | T1 (creates) |
| `Packages/SVCore/Sources/SVCore/Music/SargamLabeler.swift` | T2 (creates via `git mv`) |
| `Packages/SVCore/Sources/SVCore/Music/Quantizer.swift` | T8 (creates) |
| `Packages/SVCore/Sources/SVCore/Music/MIDISerializer.swift` | T9 (creates) |
| `Packages/SVCore/Sources/SVCore/Music/MusicXMLSerializer.swift` | T10 (creates) |
| `Packages/SVCore/Sources/SVCore/Protocols/HighlightSink.swift` | T1 (creates) |
| `Packages/SVAudio/Sources/SVAudio/Pipeline/MXLPackager.swift` | T11 (creates) |
| `Packages/SVAudio/Sources/SVAudio/Protocols/MultiChannelEngineProtocol.swift` | T12 only |
| `Packages/SVAudio/Sources/SVAudio/Playback/ProductionMultiChannelEngine.swift` | T12 only |
| `Packages/SVAudio/Sources/SVAudio/Playback/TakePlaybackEngine.swift` | T13 (creates) |
| `SurVibe/Models/RecordedTake.swift` | T4 (creates) |
| `SurVibe/SurVibeApp.swift` (ModelContainer) | T4 |
| `SurVibe/Play/ScratchpadState.swift` | T5 (creates) |
| `SurVibe/Play/PlayTabViewModel.swift` | T3, T6, T7, T14, T16a, T16d *(heaviest contention; serialise within each wave)* |
| `SurVibe/Play/PlayTab.swift` | T6, T7, T14, T16a, T16b, T16c, T16d *(heavy contention)* |
| `SurVibe/Play/PlayTabToolbar.swift` | T6, T16a, T16b, T16c, T16d *(menu items)* |
| `SurVibe/Play/LiveHighlightStaffView.swift` | T3 (preview fixtures) |
| `SurVibe/Play/RecordingStripView.swift` | T6 (deleted) |
| `SurVibe/Play/PlayTabBottomStrip.swift` | T14 (creates) |
| `SurVibe/Play/ExpandedTimelineSheet.swift` | T14 (creates), T15 (modifies) |
| `SurVibe/Play/TimelineStaffView.swift` | T14 (creates) |
| `SurVibe/Play/TimelineWaterfallView.swift` | T15 (creates) |
| `SurVibe/Play/TakesListSheet.swift` | T16b (creates) |
| `SurVibe/Play/SaveTakeSheet.swift` | T16a (creates) |
| `SurVibe/Play/ExportTakeSheet.swift` | T16c (creates) |
| `SurVibe/Play/QuantizeSheet.swift` | T16c (creates) |
| `SurVibe/Play/UnsavedScratchpadGuard.swift` | T16d (creates) |
| `SurVibe/PlayAlong/MIDINoteHighlightCoordinator.swift` | T13 (additive `HighlightSink` extension) |
| `SurVibe/ContentView.swift` | T16d |
| `SurVibe/Navigation/AppRouter.swift` | T16d |

**Conflict-aware merge order within each wave:**

- **Wave 1** — merge in order: `T3 → T4 → T5 → T8 → T9`. T3 lands first because it's the only Wave-1 task that *modifies* an existing file (`PlayTabViewModel.swift`); the rest only create new files. Conflicts are nil if T3 lands first.
- **Wave 2** — merge `T10 → T16b → T16a → T13 → T6`. T6 last because it has the largest delta on `PlayTabViewModel.swift` and `PlayTab.swift`; deferring its merge keeps the rebase target stable for the smaller agents.
- **Wave 3** — merge `T16c → T7 → T16d → T14`. T14 last because it adds the bottom strip and expanded sheet glue, the largest UI surface in the wave.

If `git merge` reports a conflict, the orchestrator opens the file, reconciles by hand, and re-runs the wave's tests before proceeding. This should be rare — the file-conflict map is conservative.

---

## Worktree dispatch pattern

Each wave-N task is dispatched as:

```
Agent({
  description: "Tn — short title",
  subagent_type: "general-purpose",
  model: "opus",
  isolation: "worktree",
  prompt: "<task-specific prompt — see §Task prompts below>"
})
```

The runtime creates a temporary worktree off the current branch, runs the agent there, and returns the new branch name + path. The orchestrator then:

1. `git fetch <worktree-path>` to load the agent's commits.
2. `git merge --no-ff <agent-branch>` into the trunk worktree.
3. Run the wave's verification gate (see below).
4. If green → continue. If red → rollback the merge, dispatch a follow-up subagent with the failure context.

---

## Verification gates

A wave only ends when **all of**:

1. **Per-task tests pass.** Each subagent's final commit must end with green local tests scoped to its files.
2. **Cross-task integration build is green.** Orchestrator runs `xcodebuild -scheme SurVibe -destination "platform=iOS Simulator,name=iPad Pro 13-inch" build` after each merge.
3. **Wave N's combined test suite passes.** Orchestrator runs `xcodebuild test` (full suite) after the *last* merge of the wave.
4. **No new SwiftLint errors.** `/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml` is clean.
5. **Latency invariant preserved (Wave 2 only)** — after T6 merges, the orchestrator runs the manual smoke test from base-plan Task 6 Step 9 (play notes, watch highlight feel) on the iPad Pro simulator.

---

## Task prompts (for parallel dispatch)

The subagent prompts below are self-contained — the dispatched agent has zero context from this conversation. Each prompt:

- Names the exact base-plan task by number.
- Tells the agent to read the spec + base plan + the relevant section.
- Calls out only the files the agent should touch.
- Demands TDD (test first, fail, implement, pass, commit).
- Demands they DO NOT modify any file outside their lane.

Common preamble (paste at the start of every task prompt):

> You are implementing Play Tab v2 task **Tn** of the SurVibe project. Working directory: this worktree. Base plan: `docs/superpowers/plans/2026-04-29-play-tab-v2.md` (commit `84df16f`). Spec: `docs/superpowers/specs/2026-04-29-play-tab-v2-design.md` (commit `7e23d3a`). Read the base-plan task block for Tn carefully — it has every step, code sample, exact file paths, and commit message. Follow the steps verbatim using TDD. Do NOT modify any file outside the file list in the task. When done, ensure all tests pass, no new SwiftLint warnings, then commit. Reply with the final commit SHA only.

Per-task additions:

| Wave | Task | Specifics |
|---|---|---|
| 0 | T1 | Files: `Packages/SVCore/Sources/SVCore/Models/Play/*.swift`, `Packages/SVCore/Sources/SVCore/Protocols/HighlightSink.swift`, plus matching tests. NEVER touch the SurVibe app target. |
| 0 | T2 | `git mv SurVibe/Play/SargamLabeler.swift Packages/SVCore/Sources/SVCore/Music/SargamLabeler.swift` (and the same for `SargamLabel.swift` if it exists separately). Update `SurVibeTests/Play/SargamLabelerTests.swift` to drop `@testable import SurVibe` and add `import SVCore`. Update `SurVibe/Play/LiveHighlightStaffView.swift` to add `import SVCore` if needed. |
| 0 | T11 | Files: `Packages/SVAudio/Sources/SVAudio/Pipeline/MXLPackager.swift`, `Packages/SVAudio/Tests/SVAudioTests/Pipeline/MXLPackagerTests.swift`. Use ZIPFoundation already in `Packages/SVAudio/Package.swift`. |
| 0 | T12 | Files: `Packages/SVAudio/Sources/SVAudio/Protocols/MultiChannelEngineProtocol.swift`, `Packages/SVAudio/Sources/SVAudio/Playback/ProductionMultiChannelEngine.swift`, plus a slot-API test. Method names + `Int` slot type are mandatory. |
| 1 | T3 | ONLY touch v1 `RecordedNote` call sites: `SurVibe/Play/PlayTabViewModel.swift:24-33,246,352`, `SurVibe/Play/LiveHighlightStaffView.swift:169-222`, `SurVibe/Play/RecordingStripView.swift:89-91,102`. Do NOT delete `RecordingStripView.swift` — that happens in T6. |
| 1 | T4 | Files: `SurVibe/Models/RecordedTake.swift`, `SurVibe/SurVibeApp.swift` (only the `ModelContainer` line), `SurVibeTests/Play/RecordedTakeTests.swift`. |
| 1 | T5 | Files: `SurVibe/Play/ScratchpadState.swift`, `SurVibeTests/Play/ScratchpadStateTests.swift`. Do NOT touch `PlayTabViewModel.swift`. |
| 1 | T8 | Files: `Packages/SVCore/Sources/SVCore/Music/Quantizer.swift`, tests. |
| 1 | T9 | Files: `Packages/SVCore/Sources/SVCore/Music/MIDISerializer.swift`, tests, golden fixture under `Packages/SVCore/Tests/SVCoreTests/Resources/Play/sa-re-ga-ma.mid`. Update `Packages/SVCore/Package.swift` to add the resource bundle declaration if missing. |
| 2 | T6 | ★ LATENCY CRITICAL ★ Read base-plan Task 6 in full. Phase 1 / Phase 2 contract is non-negotiable. Use `Synchronization.Mutex<UInt64?>` for the reference-ticks accessor (project supports iOS 26 only — `Mutex` is available). Run the latency smoke test before final commit. |
| 2 | T10 | Files: `Packages/SVCore/Sources/SVCore/Music/MusicXMLSerializer.swift`, tests, golden fixture `sa-re-ga-ma.musicxml`. |
| 2 | T13 | Files: `Packages/SVAudio/Sources/SVAudio/Playback/TakePlaybackEngine.swift`, `TakeSnapshot.swift`, `TakePlaybackProviding.swift`, plus tests. ALSO: append a one-line `extension MIDINoteHighlightCoordinator: HighlightSink {}` to `SurVibe/PlayAlong/MIDINoteHighlightCoordinator.swift` (add `import SVCore` if missing). Verify the four method signatures match exactly. |
| 2 | T16a | Files: `SurVibe/Play/SaveTakeSheet.swift` (NEW). Add `saveTake(...)` method + `saveTakeSheetPresented` flag to `PlayTabViewModel.swift` only as additions — don't touch the input dispatcher. T6's parallel agent will edit other parts of the same file; conflicts at merge time are expected and easy. |
| 2 | T16b | Files: `SurVibe/Play/TakesListSheet.swift` (NEW). Add `takesListSheetPresented` flag to `PlayTabViewModel.swift` only. |
| 3 | T7 | Files: `SurVibe/Play/PlayTab.swift` (banner + alert overlay), `PlayTabViewModel.swift` (`shouldShowSoftCapBanner` + `softCapBannerDismissed` + `shouldShowHardCapModal` + binding helper). |
| 3 | T14 | Files: `PlayTabBottomStrip.swift`, `ExpandedTimelineSheet.swift`, `TimelineStaffView.swift` (NEW). Wire bottom strip in `PlayTab.swift`, add `expandedSheetPresented` flag to `PlayTabViewModel.swift`. |
| 3 | T16c | Files: `ExportTakeSheet.swift`, `QuantizeSheet.swift` (NEW). Wire from a take row's "Export" button (added inline in `TakesListSheet.swift` if needed). |
| 3 | T16d | Files: `UnsavedScratchpadGuard.swift` (NEW), `ContentView.swift` (`.onChange` handler), `Navigation/AppRouter.swift` (`switchTab` interception), `PlayTabToolbar.swift` (New session menu item). |
| 4 | T15 | Files: `TimelineWaterfallView.swift` (NEW), modify `ExpandedTimelineSheet.swift` to wire `MIDINoteHighlightCoordinator` as the `HighlightSink`. |

---

## Wave-end checklists

After every wave the orchestrator runs:

```bash
# 1. Build
xcodebuild -scheme SurVibe -destination "platform=iOS Simulator,name=iPad Pro 13-inch" build 2>&1 | tail -20

# 2. Test (scoped per wave for speed; full suite at end-of-wave)
xcodebuild -scheme SurVibe -destination "platform=iOS Simulator,name=iPad Pro 13-inch" test 2>&1 | tail -30

# 3. Lint
/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml

# 4. SVCore + SVAudio package tests
( cd Packages/SVCore && swift test ) && ( cd Packages/SVAudio && swift test )
```

Wave-2 also runs the **manual latency smoke test** after T6 merges:

1. Boot iPad Pro 13" simulator.
2. Open Play tab.
3. Play 4–5 notes via on-screen keyboard.
4. Confirm visual highlight feels identical to current `main` (sub-frame).
5. Toolbar recording dot appears after first note.
6. Tap Undo — last note disappears from `scratchpad.noteCount`.

Anything other than ✅ on all six → revert T6, dispatch a fix subagent.

---

## Estimated wall clock

Sequential execution (base plan): 19 commits × ~10 min/task ≈ 3 h 10 m.

Parallel execution (this plan): 5 waves × ~12 min/wave ≈ 60 m.
- Wave 0: 4 agents in parallel × ~10 min + merge ≈ 12 min
- Wave 1: 5 agents × ~10 min + merge ≈ 12 min
- Wave 2: 5 agents × ~12 min (T6 longer) + merge + smoke ≈ 15 min
- Wave 3: 4 agents × ~10 min + merge ≈ 12 min
- Wave 4: 1 agent × ~8 min + merge ≈ 10 min

**~3× wall-clock speedup** — consistent with the dependency depth (longest path = 5 nodes vs 19 commits).

---

## Final-pass corrections folded into the base plan

The base plan was updated after a final tactical verification (commit reflects this). Subagents reading the base plan transparently get:

1. `PlayTabViewModel(engine:, midiInput:, highlightCoordinator:)` — three-arg ctor in every instantiation.
2. `AudioEngineManager.shared.engine` — actual property name (was `.avEngine` in early drafts).
3. `HighlightSink` declares `sustainDown(channel:) / sustainUp(channel:)` to match `MIDINoteHighlightCoordinator`'s actual signatures.
4. Tab rollback routes through `AppRouter.switchTab(to:)` — `ContentView` already has `.onChange(of: router.currentTab)` that mirrors the rollback.
5. `MXLPackager` handles ZIPFoundation's failable `Archive(accessMode: .create)?` init.
6. `RecordedTake.self` registered in BOTH `SurVibeApp.appSchema` AND `SwiftDataTestContainer.schema`.
7. v1 strip-cap test deletion list is concrete (4 tests) + 1 rewrite.
8. `ProductionMultiChannelEngine.swift` lives in `Playback/`.
9. Phase-1 reference-tick state uses `Synchronization.Mutex<UInt64?>`.

Subagents do NOT need to re-verify these claims — the base plan already encodes them.

---

*End of parallel-execution plan.*
