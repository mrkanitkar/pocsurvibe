# Execution plan v2 — verified against code & Apple HIG

**Date:** 2026-05-01 (revision)
**Supersedes:** [`2026-05-01-execution-plan.md`](./2026-05-01-execution-plan.md) — kept for history
**Companion:** [`2026-05-01-musicxml-pipeline-review.md`](./2026-05-01-musicxml-pipeline-review.md)

---

## Verification summary

Two parallel verification passes were run:

1. **Code archaeology** — every file path, API signature, and dependency in v1 cross-checked against the actual repo.
2. **Apple HIG / dev guidance** — every architectural decision cross-checked against `developer.apple.com` (HIG, framework docs) and current WWDC content.

**Result:** plan is structurally sound, but six tasks (T1, T3, T6, T8, T10, T12) had under-counted scope, and HIG flagged eight Apple-recommended items the plan omitted. Estimated wall time increases from 3.5–5h to **7.5–9.5h**.

---

## Critical corrections from verification

### Bugs in v1 (must fix in v2)

| v1 task | Bug | Fix in v2 |
|---|---|---|
| **T1** | `SoundFontAuditionView.autoLoadBundledBanksIfPresent()` loads `MuseScore_General` from `Bundle.main` (the **main app** bundle), NOT `Bundle.module`. Deleting `Diagnostics/AuditionAssets/MuseScore_General.sf2` breaks audition. | Change audition to load from `Bundle.module` first, fallback to `Bundle.main`. THEN delete the duplicate. |
| **T3** | `AVMusicTrack.enumerateEvents(...)` does **not exist**. Apple's `AVAudioSequencer` API does not expose track events. Walking events requires parsing the SMF bytes directly. | Read program changes from SMF bytes during `loadMIDI` via a small SMF parser, OR have `VerovioBridge` surface per-track program in `RenderedMIDI.trackInfo` (already does for first PC). Use `trackInfo[i].program` and route by sequencer-track-index AFTER aligning track counts. Off-by-one fix is a 1-line route adjustment, not an event walk. |
| **T6** | Verovio's Swift toolkit does not expose original MusicXML structure (key, time, staff per note, lyrics). Plan assumed it does. | Add **T6a (new)** — `MusicXMLExtractor` that re-parses the XML string with `XMLParser` for keySig, timeSig, staff-per-note, lyrics, default tonic. ~300 LOC of new code. T6 (extending `RenderedMIDI`) becomes T6b (smaller). |
| **T8** | `SongImportSheet` currently only accepts **text paste** of MusicXML. No `fileImporter`. No `.mxl` UTI declaration in `Info.plist`. | T8 must (a) add `UTImportedTypeDeclarations` for `.mxl`/`.musicxml` to `Info.plist`, (b) add `.fileImporter` to `SongImportSheet`, (c) wrap URL access in `startAccessingSecurityScopedResource()`. |
| **T10** | `TakePlaybackEngine` constructor takes `MultiChannelEngineProtocol + HighlightSink + AVAudioEngine`; scheduling via `TakeSnapshot` only. No SMF entry point. | Add `loadSMFData(_:)` method that parses SMF and schedules via the existing graph. ~150 LOC. |
| **T12** | SVCore has no `Utility/` folder. `Swar` enum lives in **SVAudio**, not SVCore. Putting `MusicTime.swift` in SVCore creates an SVCore→SVAudio dependency (wrong direction in our DAG). | Put `MusicTime.swift` in `Packages/SVAudio/Sources/SVAudio/Utility/` instead. Same code, correct package. |

### HIG-required additions (T11/T14 + new T15)

| New scope | Why | Where |
|---|---|---|
| `Info.plist` `UTImportedTypeDeclarations` for MusicXML | Apple `fileImporter` requires custom UTI for `.mxl`/`.musicxml` (no system UTI exists). | T8 |
| Security-scoped resource handling | Apple `fileImporter` doc requires `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` around URL access. | T8 |
| Reduce Motion path for scrolling/falling-note renderers | HIG: "When Reduce Motion is active, ensure your app responds by reducing automatic and repetitive animations, including peripheral motion." Continuous note-scroll is exactly that. | T11/T14 |
| Color-independent hand encoding | HIG: "Convey information with more than color alone. Offer visual indicators, like distinct shapes or icons, in addition to color." | T11/T14 — RH/LH need shape variation (e.g., circle vs square noteheads), not just blue/red. |
| `notifyOthersOnDeactivation` on session teardown | HIG Playing audio: "Let other apps know when your app finishes playing temporary audio." | T15 (new) |
| Stage Manager resilience for `fullScreenCover` | HIG Multitasking: "make sure your app adapts gracefully to different screen sizes." Resize during a song must not desync clock. | T10 acceptance — add resize test. |
| Cite `AVAudioSequencer.hostTime(forBeats:error:)` in T10 commit | Primary-source justification for ripping out the manual accumulator. | T10 commit message |

### HIG follow-ups (out of scope, logged)

These are real HIG concerns but bigger than this plan; documented in `Open issues` below:

- VoiceOver alternative for notation views (rotor that reads "bar N beat M plays Sa")
- Theme picker placement — HIG prefers task-specific options near task surface; we can keep Profile + add a quick-switch in Play Along toolbar later
- App Store privacy & accessibility nutrition labels (TestFlight pre-flight)
- `MAMusicHaptics` for accessibility users (iOS 18+)

---

## Revised task list

### Wave 1 — independent cleanup (4 parallel agents)

| ID | Title | Δ from v1 | Acceptance |
|---|---|---|---|
| **T1'** | Move audition to `Bundle.module`-first SF2 lookup, then delete the 206MB duplicate | Adds 1 file to scope (`SoundFontAuditionView.swift`) | Build green; `du -sh SurVibe/Diagnostics/AuditionAssets` ≈ 31MB; audition still loads MuseScore_General into slot A on iPad |
| **T2'** | Theme cascade fix — drop `withAnimation(.spring)` from `applyTheme`/`applyEra`; wrap cards in `GlassEffectContainer` | Same as v1 | Theme tap responds within one frame on iPad; profile theme switch no longer hangs |
| **T3'** | Track→sampler routing fix — use `rendered.trackInfo[i].program` (already extracted by Verovio) and route correctly when `seqTracks ≠ trackCount` | **Reframed**: not an event walk. Use existing `trackInfo` and align indices. | James Bond plays with correct instruments (verified by ear + by `GRAPH-ROUTE` log lines showing track→sampler→program triples) |
| **T4** | Drop BODY-EVAL log to `.debug`-only | Same as v1 | audio_log.txt no longer has BODY-EVAL spam |

### Wave 2 — schema redesign (1 agent, sequential)

| ID | Title | Δ from v1 | Acceptance |
|---|---|---|---|
| **T5'** | New `Song` schema (drop `sargamNotation`/`westernNotation`/`decodedSargamNotes`/`decodedWesternNotes`; add `musicXMLData`/`keySignatureRaw`/`timeSignatureRaw`/`defaultSaFrequencyHz`); v13 wipe + re-seed; delete `SongNotationGenerator.swift` | **Adds**: test audit (66 references across packages — ~30 min) | Builds green incl. tests; iPad fresh install: only Sukhkarta + James Bond; audition still works |

### Wave 3 — import correctness + upload feature

Wave 3 changes shape: T6 splits into T6a (new XML parser) + T6b (extend RenderedMIDI). Sequential: T6a → T6b → T7 → T8. T9 is the only parallel item.

| ID | Title | Δ from v1 | Acceptance |
|---|---|---|---|
| **T6a** | NEW. `MusicXMLExtractor` — XML re-parse for keySig, timeSig, staff-per-note (RH/LH), lyrics, tonic Sa | New 300-LOC file in `Packages/SVAudio/Sources/SVAudio/Pipeline/MusicXMLExtractor.swift` + tests | Tests cover Sukhkarta MXL → keySig=`C`, timeSig=`4/4`, ≥1 lyric event, learner staff numbers. James Bond MXL → orchestra-appropriate sig + multiple staves. |
| **T6b** | Wire extractor output into `RenderedMIDI` (or sidecar struct) so import path can read it | Smaller than v1 T6 | `VerovioBridge.render` returns `(RenderedMIDI, MusicXMLMetadata)` or similar; existing call sites updated |
| **T7** | `ContentImportManager.importMusicXMLAsSong` + `SeedContentLoader` write the new Song fields | Same as v1 | Migration log on iPad shows new fields populated for both bundled MXLs |
| **T8'** | User MXL upload feature on Songs tab | Substantially bigger than v1: build the document picker UI, declare custom UTI in `Info.plist`, security-scoped resource access | iPad smoke test: tap import button → file picker filters to `.mxl`/`.musicxml` → choose user MXL from Files app → song appears with full notation; corrupt file shows inline error; security-scoped access correctly bracketed |
| **T9** | Verify no single-channel sound fallback exists; remove if any | Already-confirmed clean from verification | Grep returns zero non-comment matches |

### Wave 4 — clock adoption (1 agent)

| ID | Title | Δ from v1 | Acceptance |
|---|---|---|---|
| **T10'** | Add `TakePlaybackEngine.loadSMFData(_:instrumentProgram:)` method; route Songs Play Along through it; delete `installArrangementBeatBridge` + `ArrangementPlayer.onBeatTick` | Adds new method on TakePlaybackEngine (~150 LOC); commit message cites `AVAudioSequencer.hostTime(forBeats:error:)` for primary-source justification; **adds Stage Manager resize test** | Time pill stops at song end exactly; notation visible to last beat; pause/resume/scrub stays sync; Stage Manager resize mid-song doesn't crash or desync |

### Wave 5 — renderer unification (2 parallel)

| ID | Title | Δ from v1 | Acceptance |
|---|---|---|---|
| **T11'** | All 4 renderers consume `[NoteEvent]` + `currentTime`; ScrollingSheetView reshape; **add Reduce Motion path** (continuous scroll → discrete bar advance); **add hand shape variation** (RH circle, LH square, both = filled) | HIG additions explicit | All renderers compile against same signature; `Song.decodedSargamNotes` no longer referenced; Reduce Motion test on iPad shows discrete advance; color-blind sim shows hand differentiation by shape |
| **T12'** | `MusicTime.swift` in **SVAudio** (not SVCore) — beat↔seconds + Swar/Western name utility | Package fix from verification | Single canonical conversion utility in SVAudio; no cross-package coupling; grep for repeated `60.0 / bpm` → zero hits outside the utility |

### Wave 6 — polish (3 parallel)

| ID | Title | Δ from v1 | Acceptance |
|---|---|---|---|
| **T13** | Verovio SVG cache (`NotationCache @Model`) | Same as v1 | Repeated song opens skip Verovio re-render; cache-hit log emitted |
| **T14'** | Render accompaniment notes (color-dimmed) **with shape coding** (different shape from learner) | HIG addition: shape coding | Sukhkarta accompaniment visible alongside learner; both color-dimmed AND shape-distinct |
| **T15** | NEW. Audio session: pass `notifyOthersOnDeactivation` when stopping engine | New | Audio session deactivation notifies other apps (HIG requirement) |

---

## Updated parallelization map

```
                               WAVE 1 (parallel × 4)
                              ┌─────────────────────────┐
T1' (SF2 cleanup + audition fix) ─┤                     │
T2' (theme cascade) ──────────────┤   independent       │
T3' (track routing — reframed) ───┤                     │
T4 (log spam) ────────────────────┤                     │
                              └────────────┬────────────┘
                                           ▼
                                    WAVE 2 (sequential × 1)
                                   ┌─────────────────────┐
                                   │   T5'  schema + v13 │
                                   │   + 66-test audit   │
                                   └──────────┬──────────┘
                                              ▼
                            WAVE 3 (mostly sequential)
                          ┌────────────────────────────────┐
                          │ T9   (parallel anytime)        │
                          │                                │
                          │ T6a XML extractor              │
                          │   ▼                            │
                          │ T6b wire into RenderedMIDI     │
                          │   ▼                            │
                          │ T7 import wiring               │
                          │   ▼                            │
                          │ T8' upload feature + UTI       │
                          └────────────────┬───────────────┘
                                           ▼
                                   WAVE 4 (sequential × 1)
                                ┌─────────────────────────┐
                                │   T10' TakePlaybackEngine│
                                │   .loadSMFData + clock  │
                                │   adoption + StageMgr   │
                                └─────────────┬───────────┘
                                              ▼
                                   WAVE 5 (parallel × 2)
                                ┌─────────────────────────┐
                                │ T11' renderer unify +   │
                                │       HIG (motion/shape)│
                                │ T12' SVAudio MusicTime  │
                                └─────────────┬───────────┘
                                              ▼
                                   WAVE 6 (parallel × 3)
                                ┌─────────────────────────┐
                                │ T13 SVG cache           │
                                │ T14' accompaniment +    │
                                │       shape coding      │
                                │ T15 notifyOthers session│
                                └─────────────────────────┘
```

---

## Concrete agent-dispatch schedule

- **Round 1 (4 agents parallel):** T1', T2', T3', T4 — all independent
- **Round 2 (1 agent):** T5' — schema is too coupled for parallel
- **Round 3a (2 parallel):** T9 + T6a — T9 is grep audit, T6a is the XML extractor
- **Round 3b (1 agent):** T6b — needs T6a
- **Round 3c (1 agent):** T7 — needs T6b
- **Round 3d (1 agent):** T8' — needs T7; bigger than v1 (file picker + UTI + security-scope)
- **Round 4 (1 agent):** T10' — clock adoption + new SMF loader on TakePlaybackEngine
- **Round 5 (2 parallel):** T11', T12'
- **Round 6 (3 parallel):** T13, T14', T15

---

## Revised wall-time estimate

| Wave | v1 | v2 | Reason |
|---|---|---|---|
| 1 | 30–45 min | **45–60 min** | T1' adds audition fix |
| 2 | 45–60 min | **75–90 min** | T5' adds 66-test audit |
| 3 | 60–90 min | **3–4 h** | T6 split + T8' file picker UI |
| 4 | 30–45 min | **1.5–2 h** | T10' adds SMF loader method |
| 5 | 30 min | **45–60 min** | T11' adds Reduce Motion + shape coding |
| 6 | 30–45 min | **45–60 min** | T15 added |
| **Total** | **3.5–5 h** | **7.5–9.5 h** | – |

---

## Per-wave verification gates (revised)

- **Wave 1**: theme tap responds <16ms; James Bond audibly correct; audio_log.txt readable; `du` confirms 206MB savings.
- **Wave 2**: library has only 2 songs; audition still works.
- **Wave 3**: upload arbitrary MXL via Files app on iPad → song appears with full metadata (keySig, timeSig, Sa Hz, lyrics, RH/LH).
- **Wave 4**: time pill stops at song end; Stage Manager resize during a song doesn't desync.
- **Wave 5**: Drop themes render notation; Reduce Motion gives discrete advance; hand shapes distinct without color.
- **Wave 6**: repeated song opens are fast; accompaniment visible with distinct shape; audio session deactivation notifies others.

---

## Open issues (out of scope, logged for follow-up)

| ID | Item | HIG citation |
|---|---|---|
| **OI-01** | VoiceOver rotor for notation ("bar N beat M, RH plays Sa") | HIG Accessibility |
| **OI-02** | Theme quick-switch chip in Play Along toolbar (HIG: task-specific options near the task) | HIG Settings |
| **OI-03** | App Store **Privacy Nutrition Label** for user-uploaded MXLs in "User content" | App Store Connect |
| **OI-04** | App Store **Accessibility Nutrition Label** | App Store Connect (June 2025) |
| **OI-05** | `MAMusicHaptics` for accessibility users (iOS 18+) | HIG Music Haptics |
| **OI-06** | Dynamic audio session category — `.playback` on Play tab (no mic) vs `.playAndRecord` elsewhere | HIG Playing audio |
| **OI-07** | Songs Play Along migration from `fullScreenCover` to `NavigationStack` destination for better Stage Manager composition | HIG Multitasking |
| **OI-08** | `glassEffectUnion(id:)` on theme cards if we want selected/unselected morphing | Liquid Glass docs |

---

## Files explicitly being deleted (verified count)

| Path | Reason | Bytes saved |
|---|---|---|
| `SurVibe/Diagnostics/AuditionAssets/MuseScore_General.sf2` | Duplicate of `Packages/SVAudio/.../Resources/MuseScore_General.sf2` | 206MB |
| `SurVibe/Songs/SongNotationGenerator.swift` | Replaced by single canonical pipeline | small |
| `Song.sargamNotation` field + `decodedSargamNotes` computed | Replaced | – |
| `Song.westernNotation` field + `decodedWesternNotes` computed | Replaced | – |
| `installArrangementBeatBridge` (PlayAlongViewModel) | Replaced by TakePlaybackEngine clock | – |
| `ArrangementPlayer.onBeatTick` callback | Replaced by TakePlaybackEngine clock | – |
| UserDefaults key `com.survibe.activeSoundFontName` | One bank in production | – |

## Files explicitly being added (verified targets)

| Path | Purpose | LOC est |
|---|---|---|
| `Packages/SVAudio/Sources/SVAudio/Pipeline/MusicXMLExtractor.swift` | XML parser for keySig/timeSig/staff/lyrics (T6a) | ~300 |
| `Packages/SVAudio/Sources/SVAudio/Utility/MusicTime.swift` | beat↔seconds + Swar utility (T12') | ~120 |
| `SurVibe/Models/NotationCache.swift` | SVG cache @Model (T13) | ~60 |
| `Info.plist` UTI declarations for `.mxl`/`.musicxml` (T8') | – | ~30 (XML) |

---

## Ready to execute when you say go

When you confirm v2, I'll dispatch **Round 1: T1', T2', T3', T4** in parallel and report back when all four land green on the iPad. Wave gates between rounds will require your sign-off before proceeding.

If you want to descope HIG additions (Reduce Motion, shape coding, notifyOthers, UTI declarations) we can drop them and revert to roughly the v1 timeline — but I'd recommend keeping them since they're the difference between "passes review" and "passes review with accessibility credit."
