# MusicXML pipeline & Theme→Notation architecture review

**Date:** 2026-05-01
**Status:** decision pending
**Owner:** maheshwar
**No active users** — breaking changes are on the table.

---

## TL;DR

The app has **three parallel pipelines** producing "the same notation," **two data models with different units** (beats vs seconds), and **no single audio clock** driving the renderers. Apple's modern stack (`AVAudioSequencer` + `AVAudioTime` + `CADisplayLink.targetTimestamp`) gives us exactly the single-source-of-truth model we need. We should consolidate to it.

---

## 1. Current pipelines (problem)

```
                       ┌─────────────────────────────────────────────┐
.mxl  ──────►  Pipeline A — MXL import (PlayAlong)                  │
                MXLLoader → VerovioBridge.render → RenderedMIDI     │
                  → PartSplitter.split → PartSplit                  │
                    → song.midiData                                  │
                  └──┬──ExpectedNote (beats)                         │
                     │   → NoteEvent.fromExpectedNotes (×60/BPM)    │
                     │   → playback.noteEvents (seconds) ─► Bars/Sargam/SplitLane
                     └─►  SongNotationGenerator                      │
                         → SargamNote/WesternNote (beats) JSON      │
                         → song.sargamNotation / .westernNotation ─► ScrollingSheet
                       └─────────────────────────────────────────────┘

                       ┌─────────────────────────────────────────────┐
seed-songs.json ─► Pipeline B — Seed JSON (legacy, now wiped at v12)│
                    SargamNote/WesternNote arrays (beats)           │
                    NO midiData                                      │
                    NO learnerTrackIndices                           │
                       └─────────────────────────────────────────────┘

                       ┌─────────────────────────────────────────────┐
touch / MIDI ─────► Pipeline C — Play tab (recording)               │
                    ScratchpadState → [RecordedNote] (seconds)      │
                    TakePlaybackEngine clock                         │
                    Independent from songs                           │
                       └─────────────────────────────────────────────┘
```

### Why this is broken

- Pipelines A and B persist **two different formats** for the same conceptual data (notation).
- A's two outputs (`noteEvents` in seconds, `*Notation` JSON in beats) are **derived twice from the same Verovio render** but live separately. They drift the moment Verovio output changes.
- Renderers split between the two formats with **no shared clock**. `ScrollingSheetView` consumes beat-based JSON but is positioned by a second-based `currentTime` — silent unit mismatch.
- Pipeline C is fully isolated. Nothing connects user-recorded takes to Songs.

---

## 2. Apple-aligned target architecture

(Source: AVAudioSequencer, AVAudioTime, CADisplayLink, Liquid Glass docs — all primary apple.com.)

### 2.1 One canonical timeline

`AVAudioSequencer` (built from a single SMF on `Song.midiData`) is **the source of truth** for:

- Beat-stamped events (`AVMusicTrack` × N, with `AVMIDINoteEvent` etc.)
- Tempo map (`tempoTrack` — only place tempo lives)
- Track→sampler routing (`AVMusicTrack.destinationAudioUnit`)
- Beat↔second↔hostTime conversion (`seconds(forBeats:)`, `beats(forHostTime:)`, `hostTime(forBeats:)`)

We **stop persisting** beat-based JSON arrays for notation. Renderers iterate `sequencer.tracks[*].events` (or a cached projection rebuilt on song load) and read the playhead from the audio engine's clock. One source. One timeline. No drift.

### 2.2 Master clock

```swift
// Per-frame, in the renderer's CADisplayLink (or TimelineView(.animation)):
let nowBeats = sequencer.beats(forHostTime: displayLink.targetTimestamp)
renderer.draw(playheadAt: nowBeats)
```

`targetTimestamp` (next-frame presentation time) leads `timestamp` by one frame, so visuals arrive on screen synchronized with the audio output. This eliminates the "currentTime drifts past duration" bug entirely — playhead is computed per-frame from the engine's actual position, never accumulated.

### 2.3 Track→sampler routing fixes the `seqTracks=15 samplers=16` bug

Route by **track identity**, not array index:

```swift
for track in sequencer.tracks {        // skips tempoTrack
    let program = track.firstProgramChange()  // walk events
    let sampler = ensureSampler(for: program)
    track.destinationAudioUnit = sampler
}
```

GM Program Change drives sampler choice per track. Off-by-one impossible.

### 2.4 Theme→notation: re-skinning, not re-loading

Each theme picks a renderer. The renderer reads from the **same** `AVAudioSequencer` + the **same** master clock. Theme change = swap the View, not the data. No `loadArrangement` re-run. No clock reset.

```swift
switch theme.preset {
    case .immersiveBars, .midnightBars, .popEra:   BarsOnStaffView(sequencer: seq, clock: clock, theme: theme)
    case .sargamGlassBars:                         SargamDualRowView(sequencer: seq, clock: clock, theme: theme)
    case .neonRhythm, .synthesia:                  SplitLaneView(sequencer: seq, clock: clock, theme: theme)
    case .immersive, .midnight, .sargamGlass:      ScrollingSheetView(sequencer: seq, clock: clock, theme: theme)
}
```

### 2.5 Theme cascade is one transaction

```swift
withTransaction(.init(animation: .smooth)) {
    appearance.currentTheme = newTheme       // single observable mutation
}
// and the active notation view opts out of the animation:
.transaction(value: appearance.currentTheme) { $0.disablesAnimations = true }
```

The notation view drives its own per-frame animation via `TimelineView(.animation)`/`CADisplayLink`; it must not be dragged into the spring transaction. This kills the Profile theme-change hang at the architectural level.

### 2.6 Liquid Glass batching

`GlassEffectContainer` batches all theme cards into one render pass. Per-card `.glassEffect()` over an animating `LinearGradient` is a perf trap (Apple's words: "limit the use of Liquid Glass effects onscreen at the same time").

---

## 3. Architecture issues to decide

| ID | Issue | Severity | Decision required |
|---|---|---|---|
| **AI-01** | **Duplicate notation models.** `noteEvents` (seconds) and `sargamNotation`/`westernNotation` (beats) carry the same notes in different units. Renderers split between them. | **Critical** | Drop the JSON blobs entirely. Make the SMF (`song.midiData`) + a single in-memory projection the only model. |
| **AI-02** | **No master clock.** `playback.currentTime` is accumulated from `onBeatTick` callbacks. Drifts past song duration; renderers go blank. | **Critical** | Replace with per-frame `sequencer.beats(forHostTime: displayLink.targetTimestamp)`. |
| **AI-03** | **`ScrollingSheetView` reads the JSON path; other 3 renderers read `noteEvents`.** Two parallel render data flows for the same song. | **Critical** | All renderers consume one timeline (sequencer or its derived projection). Delete the JSON path. |
| **AI-04** | **MXL import drops fields.** Verovio render carries key sig, time sig, lyrics, dynamics, multi-tempo, RH/LH staff assignments — none persisted. | High | Persist a richer `RenderedMIDI` snapshot, OR re-render from `midiData` on demand and trust the sequencer for tempo/time and a separate `XMLMetadata` field for static info (keySig, timeSig, lyrics, etc.). |
| **AI-05** | **Track-to-sampler routing by index.** Causes off-by-one when `seqTracks ≠ samplers`. James Bond hits this. | High | Route by `track.destinationAudioUnit` after walking events for first Program Change. |
| **AI-06** | **Verovio SVG not persisted.** Re-rendered every load. Slow first paint. | Medium | Cache SVG (or precomputed beat→pixel layouts) on Song or a sidecar table. |
| **AI-07** | **Hand assignment heuristic.** PartSplitter sets all notes to staff=1 from SMF. Hand isolation can't work for MXL imports. | Medium | Read MusicXML `<staff>` at Verovio render time (Verovio knows this); thread through `RenderedMIDI.trackInfo` or per-note metadata. |
| **AI-08** | **Theme change wraps `apply` in `withAnimation(.spring)`.** Animates 8+ resolved colors × 9 cards × glass. Hangs Profile. | High | Use `withTransaction` + `.transaction(value:){$0.disablesAnimations=true}` on clock-driven children. Wrap cards in one `GlassEffectContainer`. |
| **AI-09** | **Beat↔second conversion duplicated** (`NoteEvent.fromExpectedNotes`, `SongNotationGenerator`, the bridge in `installArrangementBeatBridge`). | Medium | Single utility on `AVAudioSequencer`-equivalent (or extension). |
| **AI-10** | **Swar name derivation duplicated** (`NoteEvent.noteNames`, `SongNotationGenerator.noteNameInfo`). | Low | Move to `Swar` enum extension; both call sites use it. |
| **AI-11** | **Play tab pipeline is fully isolated** from Songs. User recordings have no path back to a Song. | Low | Out of scope for now — but worth noting we have *three* clocks (sequencer, take engine, mic detection) with no shared abstraction. |
| **AI-12** | **`ContentImportManager` doesn't write `keySignatureRaw`/`timeSignatureRaw`.** Drop themes default to 4/4 / C major regardless of MXL. | High | Write at import time. Read MusicXML directly (Verovio gives this) and persist string raw values. |
| **AI-13** | **No active users → CloudKit can be wiped.** SwiftData schema migrations historically painful (no `VersionedSchema` allowed). | Low | Take advantage now: redesign `Song` with the target schema, wipe local stores, wipe CloudKit container, ship clean. |

---

## 4. Recommended target schema for `Song`

Single canonical model, no derived JSON blobs:

```swift
@Model
final class Song {
    // Identity
    var slugId: String = ""
    var title: String = ""
    var source: String = "user"          // "user" | "bundled"

    // Musical content (single source of truth)
    @Attribute(.externalStorage)
    var midiData: Data?                  // SMF — produced by Verovio at import
    @Attribute(.externalStorage)
    var musicXMLData: Data?              // Compressed MusicXML — kept for re-render

    // Static metadata extracted once at import (cannot derive from MIDI alone)
    var keySignatureRaw: String = "C major"
    var timeSignatureRaw: String = "4/4"
    var defaultSaFrequencyHz: Double = 261.63   // C4

    // Pre-computed PartSplit projection (saves work on every load)
    var learnerTrackIndices: [Int]? = nil
    var accompanimentInstrumentSummary: String? = nil

    // Display
    var artist: String = ""
    var tempo: Int = 120                 // initial BPM (the SMF tempo track is canonical for playback)
    var difficulty: Int = 1
    // …
}
```

**Removed:** `sargamNotation`, `westernNotation`. They're regenerated at view-time from the sequencer iff a renderer wants beat lists.

---

## 5. Migration plan (no users → can wipe)

| Step | Risk | Effort |
|---|---|---|
| **M1** Define new `Song` schema (drop `sargamNotation`/`westernNotation`, add `musicXMLData`, `keySignatureRaw`, `timeSignatureRaw`, `defaultSaFrequencyHz` populated). | low | small |
| **M2** Bump seed version → v13. v13 migration: delete every `Song`, delete every `SongProgress`. Re-import only the bundled MXLs through the new pipeline. | low | small |
| **M3** Wipe CloudKit dev container (manually in CloudKit dashboard). | manual | trivial |
| **M4** Replace `SongNotationGenerator` + `installArrangementBeatBridge` + `playback.setCurrentTime` chain with a single `SequencerClock` actor that wraps `AVAudioSequencer` and exposes `currentBeats: Double` driven by `CADisplayLink.targetTimestamp`. | medium | medium |
| **M5** Refactor renderers to one signature: `init(sequencer: AVAudioSequencer, clock: SequencerClock, theme: AppThemeDefinition)`. Each renderer iterates `sequencer.tracks[*].events` lazily; no more `[NoteEvent]` array. | high | medium |
| **M6** Track→sampler routing in `MultiTrackSamplerGraph.loadMIDI`: walk `sequencer.tracks` post-load, set `destinationAudioUnit` per track based on first Program Change. | medium | small |
| **M7** Theme transition: switch `ThemeCarouselPicker.applyTheme` to `withTransaction`; wrap card grid in `GlassEffectContainer`. | low | small |
| **M8** Persist Verovio SVG to a sidecar `NotationCache @Model` keyed by `Song.slugId`. Renderers that need SVG (ScrollingSheetView) read from cache or trigger a one-time render. | medium | medium |
| **M9** `ContentImportManager.importMusicXMLAsSong` writes `keySignatureRaw`, `timeSignatureRaw`, `defaultSaFrequencyHz` from MusicXML at import time. | low | small |

**Suggested execution order:** M1 + M2 + M3 (clean slate). Then M6 + M9 (data correctness). Then M4 + M5 (clock unification — biggest user-visible win). M7 in parallel with M5 (small). M8 last (perf polish).

---

## 6. Recommended fixes (immediate, fits inside the migration plan)

| # | Fix | Dependency | Where it ships |
|---|---|---|---|
| **F-A** | Remove `withAnimation(.spring)` from `applyTheme`/`applyEra`. | none | M7 |
| **F-B** | Wrap theme cards in `GlassEffectContainer`. | none | M7 |
| **F-C** | Persist `keySignatureRaw`, `timeSignatureRaw` from MusicXML at import. | M9 | M9 |
| **F-D** | Persist `defaultSaFrequencyHz` from key signature. | M9 | M9 |
| **F-E** | Track→sampler routing by event walk. | M6 | M6 |
| **F-F** | New `SequencerClock` class — single `currentBeats` source. | M4 | M4 |
| **F-G** | Renderer-API unification (one init signature). | M5 | M5 |
| **F-H** | Delete `SongNotationGenerator`, `Song.sargamNotation`, `Song.westernNotation`, `decodedSargamNotes`, `decodedWesternNotes`. | M5 | M5 |
| **F-I** | Verovio SVG cache (`NotationCache @Model`). | M8 | M8 |

---

## 7. Open questions

1. **Wipe CloudKit dev container** — confirm OK to do, then proceed (no users).
2. **Bundled songs** — keep just Sukhkarta and James Bond, or include the new MXL files you mentioned? If new ones, share them and I'll wire them into v13.
3. **Verovio SVG storage size** — for ~20 songs SVG should be ~5–20MB total. CloudKit asset storage is fine. Confirm.
4. **Play tab integration** — out of scope for this redesign, or do we want a unified clock model that covers Play tab too?
5. **Hand assignment from MusicXML** — Verovio ought to expose `<staff>` per note, but we'd need to teach `VerovioBridge` to surface it. Worth doing in M9 or defer?

---

## 8. References

Primary Apple sources cited above (full URLs):

- AVAudioSequencer — https://developer.apple.com/documentation/avfaudio/avaudiosequencer
- AVAudioSequencer.hostTime(forBeats:error:) — https://developer.apple.com/documentation/avfaudio/avaudiosequencer/hosttime(forbeats:error:)
- AVMusicTrack — https://developer.apple.com/documentation/avfaudio/avmusictrack
- AVAudioUnitSampler — https://developer.apple.com/documentation/avfaudio/avaudiounitsampler
- AVAudioTime — https://developer.apple.com/documentation/avfaudio/avaudiotime
- AVAudioNode.lastRenderTime — https://developer.apple.com/documentation/avfaudio/avaudionode/lastrendertime
- CADisplayLink — https://developer.apple.com/documentation/quartzcore/cadisplaylink
- Liquid Glass — https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- GlassEffectContainer — https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- Transaction — https://developer.apple.com/documentation/swiftui/transaction
- View.transaction(value:_:) — https://developer.apple.com/documentation/swiftui/view/transaction(value:_:)
- SwiftData — https://developer.apple.com/documentation/swiftdata/preserving-your-apps-model-data-across-launches
- @Attribute — https://developer.apple.com/documentation/swiftdata/attribute(_:originalname:hashmodifier:)

Internal:
- Code archaeology report: this conversation, agent run 2026-05-01.
- Past D5 work (multi-staff): `SurVibe/Songs/SongImporterPartSplitTests.swift` review comment.
