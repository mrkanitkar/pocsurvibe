# Execution plan — MusicXML pipeline unification

**Date:** 2026-05-01
**Companion to:** [`2026-05-01-musicxml-pipeline-review.md`](./2026-05-01-musicxml-pipeline-review.md)

## Verified facts (from code archaeology, not speculation)

| Fact | Evidence |
|---|---|
| Two copies of MuseScore_General.sf2 in repo (206MB × 2 = 412MB) | `find . -iname "*.sf2"` |
| GeneralUser-GS.sf2 (31MB) only in `SurVibe/Diagnostics/AuditionAssets/` | same |
| `TakePlaybackEngine` is public, in `Packages/SVAudio/Sources/SVAudio/Playback/TakePlaybackEngine.swift` | grep |
| Only one `SoundFontPlaying` conformer: `MultiChannelTouchSoundFont` (already multichannel-only) | grep `: SoundFontPlaying` |
| `SoundFontManager` referenced in protocol doc comment but does not exist as a conformer in current code | grep — stale doc |
| Songs library currently contains 3 rows (post-v12: Sukhkarta, James Bond + 1 leftover Jana Gana Mana from prior launch) | iPad audio_log.txt BACKFILL-SCAN lines |

## Decisions locked in (from user)

1. ✅ Wipe CloudKit dev container — no users, clean slate fine.
2. ✅ Two bundled MXLs (Sukhkarta, James Bond). User-MXL upload feature must work end-to-end on Songs tab.
3. ✅ MuseScore_General.sf2 is the **only** production bank. GeneralUser-GS stays only for the Profile audition POC.
4. ✅ Multichannel pipe only. (Audit confirms no fallback exists — directive is preserved.)
5. ✅ Songs Play Along **adopts Play tab's `TakePlaybackEngine` clock**, not a new SequencerClock class.
6. ✅ Hand assignment from MusicXML `<staff>` — do now, do not defer.
7. ✅ Remove all duplicate notation models, beat↔seconds helpers, swar derivation, soundfont copies.

## Task list

Each task is sized for a single subagent run, with explicit dependencies and a verifiable acceptance signal.

### Wave 1 — independent cleanup (parallel)

| ID | Title | Files touched | Depends on | Acceptance |
|---|---|---|---|---|
| **T1** | Delete duplicate MuseScore_General.sf2 in Diagnostics, simplify activeSoundFontURL | `SurVibe/Diagnostics/AuditionAssets/MuseScore_General.sf2` (delete) · `Packages/SVAudio/.../MultiTrackSamplerGraph.swift` · `SurVibe/Diagnostics/SoundFontAuditionView.swift` · `SurVibe/PlayAlong/PlayAlongViewModel.swift` | – | Build green; SoundFontAuditionView still picks up MuseScore_General from `Bundle.module` and GeneralUser-GS from main bundle; UserDefaults key `com.survibe.activeSoundFontName` removed; activeSoundFontURL returns `MuseScore_General` only; `git ls-files` shows the diagnostics SF2 gone; `du -sh SurVibe/Diagnostics/AuditionAssets` ≈ 31MB |
| **T2** | Theme cascade fix (Profile hang) | `SurVibe/Profile/ThemeCarouselPicker.swift` · `SurVibe/Profile/ThemePreviewCard.swift` | – | `applyTheme`/`applyEra` no longer use `withAnimation`; cards wrapped in `GlassEffectContainer`; theme tap on iPad responds within one frame (verified in audio_log.txt as `PROFILE-THEME-APPLY took <16ms`) |
| **T3** | Track→sampler routing by event walk (James Bond off-by-one) | `Packages/SVAudio/.../MultiTrackSamplerGraph.swift` (loadMIDI) | – | After loadMIDI runs, every `track.destinationAudioUnit` reflects the track's first Program Change (or fallback program=0); audio_log.txt shows new line `GRAPH-ROUTE track=N program=P sampler=I` per track; James Bond audibly correct on iPad |
| **T4** | Drop BODY-EVAL log to .debug, drop other per-frame logs from .info | `SurVibe/PlayAlong/SongPlayAlongView.swift` · others identified by `grep -n "BODY-EVAL" SurVibe Packages` | – | audio_log.txt no longer has BODY-EVAL spam during normal playback (debug-only os.Logger output retained) |

### Wave 2 — schema redesign + clean slate (sequential, single agent)

| ID | Title | Files touched | Depends on | Acceptance |
|---|---|---|---|---|
| **T5** | New Song schema, v13 wipe migration, CloudKit container reset | `SurVibe/Models/Song.swift` (drop `sargamNotation`, `westernNotation`, `decodedSargamNotes`, `decodedWesternNotes`; add `musicXMLData: Data?`, `keySignatureRaw: String`, `timeSignatureRaw: String`, `defaultSaFrequencyHz: Double`) · `SurVibe/SeedContentLoader.swift` (bump to v13, wipe all Songs + SongProgress, drop `backfillMissingNotationJSON` since fields no longer exist, drop `SongNotationGenerator` import) · delete `SurVibe/Songs/SongNotationGenerator.swift` · update tests that reference deleted fields | – | Builds green; iPad fresh-installs cleanly; v13 migration log line in audio_log.txt; only Sukhkarta + James Bond after migration; Profile A/B audition still functional |

### Wave 3 — import correctness + upload feature (parallel after T5)

| ID | Title | Files touched | Depends on | Acceptance |
|---|---|---|---|---|
| **T6** | MusicXML metadata extractor: keySig, timeSig, Sa Hz, RH/LH staff per note, lyrics | `Packages/SVAudio/.../VerovioBridge.swift` (extend RenderedMIDI / TrackInfo / ExpectedNote with staff number; surface MusicXML `<key>`, `<time>`, first `<note>`'s key context as Sa Hz; surface `<lyric>` events) · `Packages/SVAudio/.../PartSplitter.swift` (thread staff number into `ExpectedNote` if not already) · unit tests in `Packages/SVAudio/Tests/SVAudioTests/Pipeline/` | T5 | Tests cover Sukhkarta MXL → keySig=`C major`, timeSig=`4/4`, Sa Hz computed; James Bond MXL → keySig=`Eb minor` (or whatever its score has), staff numbers populated for multi-staff parts |
| **T7** | Wire metadata writes in ContentImportManager + SeedContentLoader | `SurVibe/ContentImportManager.swift` (importMusicXMLAsSong writes the new Song fields from RenderedMIDI/extractor) · `SurVibe/SeedContentLoader.swift` (importBundledMXLs same path) | T5, T6 | After v13 migration on iPad, audio_log.txt confirms `Imported MusicXML song slug=sukhkarta-dukhharta keySig=… timeSig=… SaHz=…`; SwiftData inspector / debug log shows the Song row has all 4 new fields populated |
| **T8** | Songs-tab user upload feature: SongImportSheet end-to-end | `SurVibe/Songs/SongImportSheet.swift` (verify document picker accepts `.mxl`/`.musicxml`/`.xml` UTI) · `SurVibe/Songs/SongImportViewModel.swift` (route through ContentImportManager.importMusicXMLAsSong, surface progress + errors) · entry point button somewhere visible on Songs tab if missing | T5, T7 | iPad smoke test: tap import button on Songs tab → file picker → choose user MXL from Files app → song appears in library with notation populated → tap → Play Along works on first try; failure modes (corrupt MXL, no learner part) show meaningful UI error |
| **T9** | Remove single-channel fallback hooks if found during T6/T7/T8 | TBD | – | grep for `legacy.*sound`, `fallback.*sound`, `single.*channel` in code shows zero matches outside of comments/docs |

### Wave 4 — clock adoption (sequential, single agent)

| ID | Title | Files touched | Depends on | Acceptance |
|---|---|---|---|---|
| **T10** | Adopt TakePlaybackEngine as the single Songs Play Along clock | `Packages/SVAudio/.../TakePlaybackEngine.swift` (verify it can be driven from MIDI data instead of `[RecordedNote]` — may need a constructor variant taking SMF Data) · `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift` (replace internal currentTime accumulator with TakePlaybackEngine.currentPositionSec) · `SurVibe/PlayAlong/PlayAlongViewModel.swift` (delete `installArrangementBeatBridge` clamp logic — clock is now sample-accurate from the engine) · `SurVibe/PlayAlong/Coordinators/ArrangementPlayer.swift` (remove `onBeatTick` callback path; clock lives outside this class) | T5 | Time pill on Sukhkarta stops at exactly the song duration (no overrun); notation stays visible to the last beat; audio and visuals stay synchronized when scrubbing/pausing/resuming; iPad audio_log.txt shows new clock-tick lines from TakePlaybackEngine |

### Wave 5 — renderer unification (parallel after T10)

| ID | Title | Files touched | Depends on | Acceptance |
|---|---|---|---|---|
| **T11** | One renderer signature; ScrollingSheetView reads `[NoteEvent]` like the other 3 | `SurVibe/PlayAlong/ScrollingSheetView.swift` (drop `decodedSargamNotes`/`decodedWesternNotes`, accept `noteEvents` + `currentTime` like BarsOnStaffView) · `SurVibe/PlayAlong/SongPlayAlongView.swift` contentArea dispatch updated · ensure `BarsOnStaffView`, `SargamDualRowView`, `SplitLaneView` all already match this shape (verify) | T10 | All four renderers accept `[NoteEvent]` + `currentTime` only; `Song.decodedSargamNotes` / `Song.decodedWesternNotes` no longer referenced anywhere; ScrollingSheetView in Drop themes shows actual notes for Sukhkarta + James Bond on iPad |
| **T12** | Beat↔seconds + Swar-name utility extraction | `Packages/SVCore/Sources/SVCore/Utility/MusicTime.swift` (new — `beatsToSeconds(beats:bpm:)`, `secondsToBeats(seconds:bpm:)`) · existing `Swar` enum extension for `swarName(forMIDI:)`, `westernName(forMIDI:)` · all call sites updated; `SongNotationGenerator.noteNameInfo` already gone after T5 | T5 | One canonical conversion utility; grep for repeated `60.0 / bpm` or `* secPerBeat` shows zero hits outside the utility file |

### Wave 6 — polish (parallel)

| ID | Title | Files touched | Depends on | Acceptance |
|---|---|---|---|---|
| **T13** | Verovio SVG cache | `SurVibe/Models/NotationCache.swift` (new @Model, `@Attribute(.externalStorage) var svgPagesData: Data`) · cache populate on first render · `ScrollingSheetView` reads cache | T5, T11 | Repeated opens of Sukhkarta no longer show the 3-5s Verovio render delay; audio_log.txt shows `NOTATION-CACHE hit` lines |
| **T14** | Render accompaniment notes in renderers (color-dimmed) | renderer files | T11 | Sukhkarta accompaniment visible in BarsOnStaffView (dimmed); user can tell what they're hearing |

## Parallelization map

```
                               WAVE 1 (parallel)                  WAVE 2 (sequential)
                              ┌───────────────────────┐         ┌──────────┐
T1 (SF2 cleanup) ─────────────┤                       │         │          │
T2 (theme hang) ──────────────┤   independent;        │ ──────► │   T5     │
T3 (track routing) ───────────┤   any agent           │         │ schema + │
T4 (log cleanup) ─────────────┤                       │         │  v13     │
                              └───────────────────────┘         └────┬─────┘
                                                                     │
                                                                     ▼
                                                         WAVE 3 (parallel after T5)
                                                       ┌───────────────────────────┐
                                                       │ T6 metadata extractor     │
                                                       │ T7 import wiring (needs T6)
                                                       │ T8 upload feature (T7)    │
                                                       │ T9 fallback purge         │
                                                       └────────────┬──────────────┘
                                                                    │
                                                                    ▼
                                                                ┌──────┐
                                                                │ T10  │
                                                                │clock │
                                                                └──┬───┘
                                                                   ▼
                                                       WAVE 5 (parallel after T10)
                                                       ┌──────────────────────────┐
                                                       │ T11 renderer unification │
                                                       │ T12 utility extraction   │
                                                       └────────────┬─────────────┘
                                                                    ▼
                                                          WAVE 6 (parallel)
                                                       ┌──────────────────┐
                                                       │ T13 SVG cache    │
                                                       │ T14 accompaniment│
                                                       └──────────────────┘
```

**Concrete agent dispatch:**

- **Round 1 (4 parallel agents)**: T1, T2, T3, T4
- **Round 2 (1 agent)**: T5 (single — schema is too coupled to risk parallel)
- **Round 3 (3 parallel agents)**: T6, T9, then T7 (sequential after T6), then T8 (sequential after T7) → realistically T6+T9 parallel, T7 after T6, T8 after T7
- **Round 4 (1 agent)**: T10
- **Round 5 (2 parallel agents)**: T11, T12
- **Round 6 (2 parallel agents)**: T13, T14

That gives ~6 sequential rounds with 1–4 parallel agents per round.

## Per-task budget

| Wave | Total tasks | Parallel agents | Estimated wall time per round |
|---|---|---|---|
| 1 | 4 | 4 | 30–45 min (each task is 50–150 LOC) |
| 2 | 1 | 1 | 45–60 min (schema + migration + tests) |
| 3 | 4 | 2-then-1-then-1 | 60–90 min (T6 is the largest — Verovio extension) |
| 4 | 1 | 1 | 30–45 min |
| 5 | 2 | 2 | 30 min |
| 6 | 2 | 2 | 30–45 min |
| **Total** | **14** | – | **3.5–5h** real wall time |

## Verification at every wave gate

Between waves, the user does a 30-second iPad smoke test:

- **After Wave 1:** Theme tap is instant; James Bond sounds right; audio_log.txt readable.
- **After Wave 2:** Library has only Sukhkarta + James Bond; audition still works.
- **After Wave 3:** Upload an arbitrary MXL via Files app on iPad → song appears in library with full notation.
- **After Wave 4:** Time pill stops at song end; notation stays visible to the last beat.
- **After Wave 5:** Switch to a Drop theme — notation renders correctly.
- **After Wave 6:** Repeated song opens are fast; accompaniment visible.

If any wave gate fails, we don't proceed.

## Files explicitly being deleted

| Path | Reason |
|---|---|
| `SurVibe/Diagnostics/AuditionAssets/MuseScore_General.sf2` | Duplicate of package resource (206MB save) |
| `SurVibe/Songs/SongNotationGenerator.swift` | Replaced by single canonical pipeline |
| `Song.sargamNotation` field | Replaced by single canonical pipeline |
| `Song.westernNotation` field | Replaced by single canonical pipeline |
| `Song.decodedSargamNotes` computed | Replaced by single canonical pipeline |
| `Song.decodedWesternNotes` computed | Replaced by single canonical pipeline |
| `installArrangementBeatBridge` (in PlayAlongViewModel) | Replaced by TakePlaybackEngine clock |
| `ArrangementPlayer.onBeatTick` callback | Replaced by TakePlaybackEngine clock |
| All `.onChange(of: progress?.preferredHands)` etc. | Stay (settings sheet → VM still need this — unrelated to schema) |
| UserDefaults key `com.survibe.activeSoundFontName` | One bank in production; user pref unnecessary |

## Files being added

| Path | Purpose |
|---|---|
| `Packages/SVCore/Sources/SVCore/Utility/MusicTime.swift` | Single beat↔seconds + swar/western name utility |
| `SurVibe/Models/NotationCache.swift` | SwiftData model for cached Verovio SVG (T13) |

## Out of scope for this plan

- Play tab unified clock (Play tab clock is fine; only adopting it into Songs Play Along)
- New theme designs
- Audio latency / pitch-detection changes
- CloudKit schema modeling beyond Song (SongProgress already migrated)
- Performance profiling for 100+ song libraries (deferred until we have actual scale)

---

## Ready to execute

When you say go, I'll dispatch Round 1 (T1–T4 in parallel) and report back when all 4 land green on the iPad. Then we proceed wave by wave with your sign-off at each gate.
