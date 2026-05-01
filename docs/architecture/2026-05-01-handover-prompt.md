# Handover prompt for new session

Copy-paste everything below the `---` line into your new session's first message. It is fully self-contained.

---

You are picking up the SurVibe iOS app's MusicXML pipeline unification mid-stream. The previous session did the architectural review and produced a verified execution plan; this session executes it.

## Operating envelope

- **Repo:** `/Users/maheshwar/Developer/SurVibe` (you are already in it)
- **Branch:** `main` (no users; we ship to main, no PR ceremony)
- **Device under test:** iPad Air (iOS 26.4.2) — id `00008101-00094D413463001E` — connected via USB
- **You have a 1M context window and 20× usage plan** — use it. Read entire files, dispatch many parallel agents, do not be stingy with tokens.
- **Do not stub or defer.** When the plan says "implement X" you implement X. The architecture is locked.

## Read these three docs first (in order, in full)

1. `docs/architecture/2026-05-01-musicxml-pipeline-review.md` — architecture review, 13 issues catalogued
2. `docs/architecture/2026-05-01-execution-plan.md` — original execution plan (v1, kept for history)
3. `docs/architecture/2026-05-01-execution-plan-v2.md` — **verified plan you will execute**

After reading, briefly confirm to the user that you've ingested the plan. Do not paraphrase the whole thing.

## What's already done (from prior session)

Commits on `main` you should expect to see at HEAD:

- `dfc847e docs(arch): execution plan v2 — verified vs code + Apple HIG`
- `a10b33e docs(arch): execution plan — 14 tasks across 6 waves`
- `d71ff30 docs(arch): MusicXML pipeline + theme→notation review`
- `2567945 seed(v12): unify song format on MXL — wipe JSON seeds + force re-import`
- `8758397 fix(PlayAlong): derive SF2 presets from accompaniment SMF, not full song` (now superseded — see below)
- `2774cc9 fix(PlayAlong): play FULL rendered MIDI through multi-sampler graph`
- `5432a27 diag(PlayAlong): comprehensive instrumentation + visible gear button`
- earlier: Songs↔Play Along merge waves 0–6 are merged

The current Songs library on the iPad has only Sukhkarta + James Bond (post-v12 wipe), both with `midiData` populated and notation JSON populated by the now-going-away backfill.

The audio_log.txt on the device is in `Documents/audio_log.txt` (pull via `xcrun devicectl device copy from --device 00008101-00094D413463001E --domain-type appDataContainer --domain-identifier com.survibe.SurVibe --source 'Documents/audio_log.txt' --destination /tmp/survibe_audio_log.txt`).

## What you will execute

Plan v2 has 14 tasks across 6 waves with the parallelization map:

```
Round 1: T1' T2' T3' T4              4 parallel agents
Round 2: T5'                          1 sequential agent
Round 3a: T9 T6a                      2 parallel
Round 3b: T6b                         sequential after T6a
Round 3c: T7                          sequential after T6b
Round 3d: T8'                         sequential after T7
Round 4: T10'                         1 sequential
Round 5: T11' T12'                    2 parallel
Round 6: T13 T14' T15                 3 parallel
```

Total 14 tasks, ~7.5–9.5 hours wall time.

## How to dispatch each task

For every task, read its row in `2026-05-01-execution-plan-v2.md` plus all "Δ from v1" notes. Then dispatch a subagent using the `Agent` tool with:

- **subagent_type:** `general-purpose` for most; `Explore` only for read-only investigation; never `feature-dev:code-architect` (tasks are already specced)
- **model:** `opus` for tasks touching multiple files / cross-package work (T5', T6a, T8', T10', T11'). `sonnet` is fine for the small mechanical tasks (T1', T2', T4, T9, T12', T13, T14', T15).
- **isolation:** `worktree` for parallel rounds (Round 1, Round 5, Round 6, Round 3a). Sequential rounds run in-tree.
- **prompt:** include the task ID, full Δ description from v2, the acceptance criteria, the "Files explicitly being deleted/added" rows that apply, AND a reminder to:
  - build with `xcodebuild -project SurVibe.xcodeproj -scheme SurVibe -derivedDataPath /private/tmp/SurVibe-DD -destination 'id=00008101-00094D413463001E' -allowProvisioningUpdates build`
  - install with `xcrun devicectl device install app --device 00008101-00094D413463001E /tmp/SurVibe-DD/Build/Products/Debug-iphoneos/SurVibe.app`
  - launch with `xcrun devicectl device process launch --device 00008101-00094D413463001E --terminate-existing com.survibe.SurVibe`
  - pull logs and grep for the specific BACKFILL/TOOLBAR/AUDIO-ROUTE/etc. string named in the acceptance criteria
  - commit with a clear message referencing the task ID; if SwiftLint blocks, fix and re-commit (do not add `// swiftlint:disable` blanket directives without justification)

When dispatching parallel rounds, send all the agents in **one message** with multiple `Agent` tool calls so they actually run concurrently.

## Wave gates (mandatory user sign-off between rounds)

After each round completes, summarize results to the user (which tasks landed, build state, key log lines verifying acceptance) and **wait for explicit "go" before starting the next round**. Do not chain rounds without a sign-off — the user is testing on a real iPad between waves.

## Things you must not do

- Do not introduce a `SequencerClock` actor or any new clock class. We adopt `TakePlaybackEngine` (T10') — that's the answer.
- Do not use `withAnimation(.spring)` around mutations on `AppThemeManager`. Use `withTransaction` + child `.transaction(value:){ $0.disablesAnimations = true }` per HIG.
- Do not store SF2 user preferences. One bank in production: `MuseScore_General.sf2` from `Bundle.module`. `GeneralUser-GS.sf2` stays only in `SurVibe/Diagnostics/AuditionAssets/` for the Profile audition POC.
- Do not bring back `Song.sargamNotation` / `westernNotation` / `decodedSargamNotes` / `decodedWesternNotes` — they're being deleted in T5'.
- Do not introduce a parallel `[NoteEvent]` array path in renderers — all 4 renderers consume the same `[NoteEvent]` + `currentTime` after T11'.
- Do not commit anything that breaks `xcodebuild` for the iPad device destination. Build green or roll back.
- Do not invent new tasks. If something seems missing, surface it as an "open issue" (OI-NN) and ask the user — don't expand scope unilaterally.

## Things you must do

- Use parallel `Agent` calls for parallel rounds.
- Always include `-derivedDataPath /private/tmp/SurVibe-DD` on every `xcodebuild` invocation (CLAUDE.md storage hygiene rule).
- After every commit, install + launch on iPad and pull `audio_log.txt` to verify the acceptance signal in the log.
- Cite primary Apple sources in commit messages where relevant (T10' should cite `developer.apple.com/documentation/avfaudio/avaudiosequencer/hosttime(forbeats:error:)`).
- Update `MEMORY.md` with `[Pipeline unification underway — current wave]` once you start, and clear it when done.
- Use the `mcp__ccd_session__mark_chapter` tool to mark each wave boundary so the session is navigable.
- Use `TodoWrite` to track the 14 tasks across 6 waves; update statuses in real time.

## First action when you load in

1. Read the three docs (review, v1, v2) in full. (You have 1M context — read them complete, not excerpted.)
2. Read `CLAUDE.md` and `.claude/rules/audio.md` and `.claude/rules/app-target.md` for project rules.
3. Confirm git HEAD matches `dfc847e` (or has more commits — check what landed).
4. Confirm iPad is reachable: `xcrun devicectl list devices 2>&1 | grep -i ipadair`
5. Tell the user "ready to start Round 1 — T1'/T2'/T3'/T4 in parallel" and **wait for "go"**.

## Round 1 dispatch (when user says go)

Send a single message with **four parallel `Agent` tool calls**:

- T1' — SF2 cleanup + audition fix → opus model, worktree isolation
- T2' — theme cascade fix → sonnet model, worktree isolation
- T3' — track→sampler routing reframed → opus model, worktree isolation
- T4 — BODY-EVAL log to debug → sonnet model, worktree isolation (small task)

Each agent prompt should include the full v2 task row, its acceptance criteria, the iPad build/install/launch commands, and a directive to commit with `<type>(<package>): <description> [T1']` style messages.

After all four return, merge their worktrees in dependency-free order (none of these collide), build the merged HEAD on the iPad, verify all four acceptance signals in `audio_log.txt`, and report to the user.

## If you hit a blocker not covered above

Stop. Don't improvise. Tell the user the blocker, cite the file/line, propose options A/B/C, and wait for direction. We're rebuilding the foundation — wrong calls compound.

## Locked decisions (do not relitigate)

1. CloudKit dev container wipe: ✅ approved (no users)
2. Single soundfont in production: `MuseScore_General.sf2`, no user preference
3. Songs Play Along adopts `TakePlaybackEngine` clock (do not build a separate `SequencerClock`)
4. Hand assignment from MusicXML `<staff>` — extract via XML re-parse (T6a), not deferred
5. Schema redesign: drop the duplicate JSON blobs; canonical = `midiData` + extracted metadata
6. Multichannel sound pipe only — already verified clean, no fallback to remove
7. HIG additions kept in scope (Reduce Motion, shape coding, UTI, security-scoped resource, notifyOthers)

End of handover.
