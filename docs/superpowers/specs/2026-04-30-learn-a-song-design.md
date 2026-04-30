# Learn-a-Song — Design Spec

**Date:** 2026-04-30
**Status:** Spec — pending plan
**Owner:** SurVibe team
**Supersedes:** Current play-along path (broken; see §12)

---

## 1. Summary

Turn the existing Songs-tab play-along screen into a working "Learn this song" experience. The user picks an MXL from their library, sees the piano part on grand staff (or falling notes), plays it on iPad keyboard or USB MIDI, gets scored note-by-note, and **hears the rest of the arrangement (vocals, harmonium, tabla, strings, etc.) playing in the background, locked to the same tempo they picked**.

This is the core SurVibe value loop. Today the "Play Along" entry point exists in the UI but does nothing when tapped (regression — see §12). This spec replaces that broken path end-to-end.

## 2. User scenario

1. User opens **Songs** tab. Sees their imported library in the sidebar (existing behavior).
2. User imports a new song via **+** (Files picker) → drops one of `james-bond-theme.mxl`, `sukhakarta-dukhaharta.mxl`, `vande-mataram.mxl`, `indian-national-anthem.mxl`. Imported via existing `SongImportSheet`/`SongImporter`. (Verified: these files are 5–15 KB each, multi-part arrangements.)
3. Detail pane (`SongDetailView`) shows song header, **Parts section** with a default learner part picked by `PartSplitter` and the list of accompaniment instruments, and a **Play Along** button.
4. User taps **Play Along** → `PlayAlongSceneHost` mounts `SongPlayAlongView`.
5. User picks tempo `0.5×` from the toolbar slider, leaves Backing on `On`, taps Play.
6. **A 1-bar audible count-in plays at the selected tempo** (4 metronome clicks for 4/4, 3 for 3/4, etc.). Then the full arrangement begins. The grand staff cursor (or falling notes) advances. The next note glows on the on-screen keyboard.
7. User plays the keyboard. Each press feeds `MIDIInputManager` → `ScoringAdapter` → `NoteScoreCalculator`; verdict bubbles appear (✓ / late / wrong). Their piano sound plays through the same sampler graph at zero added latency.
8. The accompaniment never waits for the user — fixed-tempo (Mode A). If the user falls behind, they miss notes; the song goes on.
9. End of song → `PlayAlongResultsOverlay` shows accuracy %, per-section breakdown, stars. Existing path.

## 3. Goals & non-goals

**Goals**
- Make Play Along functional end-to-end on the four bundled test MXLs.
- Play multi-instrument backing in tempo-locked sync with on-screen cursor.
- Score user MIDI input against the learner part, sample-accurate timing.
- Tempo scaling **0.5×–1.5×** live, with no audible time-stretch artifacts.
- End-to-end input-to-sound latency ≤ 12 ms p50 / ≤ 18 ms p99 on iPad.
- **Section loop** drill mode (tap measure numbers to set start/end).
- **Hand isolation**: Both / RH / LH practice modes for two-staff piano parts.
- **Lyrics**: Verovio-native rendering on the staff that carries them, always visible when MusicXML has lyrics.

**Non-goals (deferred to future specs)**
- PDF / photo OMR import.
- ABC text / Sargam text import.
- Score-following / adaptive tempo (Mode C).
- Wait-for-user mode (Mode B). The existing `PlayAlongWaitController` stays in code but is disabled in the new UI for v1; revisited later.
- Microphone / pitch-from-voice input. Play Along is **MIDI-input only**, matching the Play tab guardrail.
- Bluetooth MIDI input — explicitly unsupported (>400 ms drift documented; see §7).
- New tabs or full-screen redesign.

## 4. Architecture

```
                          MXL file (10–80 KB)
                                  │
                                  ▼
                          VerovioBridge.render()                  [REUSE]
                                  │
                                  ▼
                  RenderedMIDI { data, trackInfo[…] }             [REUSE]
                                  │
                                  ▼
                          PartSplitter                            [NEW]
                                  │
                  ┌───────────────┴───────────────┐
                  ▼                               ▼
            LearnerScore                  AccompanimentMIDI
            [{beat, pitch, dur}]          (Data, learner tracks removed)
                  │                               │
                  ▼                               ▼
            ScoringAdapter ◄── MIDIInputManager   ArrangementPlayer        [NEW]
            (wraps               [REUSE]          (wraps MultiTrackSamplerGraph)
            NoteScoreCalculator)                       │
            [REUSE+adapt]                              ▼
                  │                            MultiTrackSamplerGraph      [REUSE,
                  │                                    │                    + tempo fix]
                  │                                    ▼
                  │                            AVAudioSequencer
                  │                            (sequencer.rate = tempoScale)
                  │                                    │
                  │                                    ▼
                  │                            16× AVAudioUnitSampler
                  │                            ←── MuseScore_General.sf2
                  │                                    │
                  ▼                                    ▼
             PlayAlongChromeState              AudioEngineManager (256 frames @ 44.1 kHz)
             (current beat, scoring HUD)              │
                  │                                    ▼
                  ▼                                speaker
             SongPlayAlongView                  [REUSE]
             (existing UI: falling notes /
              scrolling sheet / keyboard /
              scoring HUD / results overlay)
             [REUSE, +Parts/Backing controls]
```

### One clock, one tempo

`AVAudioSequencer` is the master clock. Its `currentPositionInBeats` drives the display cursor (read in display loop, ±5–50 ms jitter is tolerated for visual; not used for scoring). Its `rate` property is the only tempo knob — set once when user changes the tempo slider.

User-input scoring uses **CoreMIDI host-tick timestamps** (`MIDITimeStamp`, microsecond precision), converted to beats using the original tempo map and the current `sequencer.rate`. This is the rock-solid timing path; sequencer-position reads never enter the scoring loop.

## 5. Components

### 5.1 New components

#### `PartSplitter` (Packages/SVAudio/Sources/SVAudio/Pipeline/)

Decides which voice/staff is the learner part, returns two MIDI sequences. Also identifies per-staff sub-tracks for hand isolation and which staves carry lyrics.

```swift
public struct PartSplit: Sendable {
    public let learner: LearnerScore                 // expected notes for scoring
    public let accompaniment: Data                   // SMF bytes for sequencer
    public let learnerInstrumentLabel: String        // "Piano", "Voice (transposed)"
    public let accompanimentInstruments: [String]    // ["Harmonium", "Tabla", "Strings"]
    public let learnerTrackIndices: [Int]            // for reverse mapping if user changes choice
    public let learnerStaves: [StaffSpec]            // 0, 1, or 2 entries (RH/LH support)
    public let lyricsStaffTrackIndex: Int?           // track containing <lyric>; visible always
}

public struct StaffSpec: Sendable {
    public let staffNumber: Int        // MusicXML <staff> value: 1 = RH (treble), 2 = LH (bass)
    public let role: HandRole          // .rightHand / .leftHand / .singleStaff
    public let noteIDs: [UUID]         // expected-note IDs assigned to this staff
}

public enum HandRole: Sendable { case rightHand, leftHand, singleStaff }

public enum LearnerSelection: Sendable {
    case auto                        // splitter picks
    case trackIndex(Int)             // user override from Parts picker
}

public struct LearnerScore: Sendable {
    public let notes: [ExpectedNote]
    public let originalBPM: Double
    public let beatsPerMeasure: Int
}

public struct ExpectedNote: Sendable, Identifiable {
    public let id: UUID
    public let beat: Double           // beats from start, original tempo
    public let durationBeats: Double
    public let midiNote: UInt8
    public let measureNumber: Int
}

public struct PartSplitter {
    public init() {}
    public func split(_ rendered: RenderedMIDI, selection: LearnerSelection = .auto) throws -> PartSplit
}
```

**Prerequisite: extend `VerovioBridge` SMF parser to capture track-name meta events.** The current parser at `Packages/SVAudio/Sources/SVAudio/Pipeline/VerovioBridge.swift:191-277` skips meta events. Add capture of meta type 0x03 (Sequence/Track Name) and 0x04 (Instrument Name) into `TrackInfo`:

```swift
public struct TrackInfo: Sendable {
    public let channel: UInt8
    public let program: UInt8
    public let isPercussion: Bool
    public let trackName: String?       // NEW — meta 0x03
    public let instrumentName: String?  // NEW — meta 0x04
}
```

If meta-name extraction proves unreliable on Verovio output (verify against the four bundled MXLs in the plan stage), the algorithm falls back to GM-program-only selection.

**Auto-selection algorithm** (ordered):
1. If any track's `trackName` or `instrumentName` matches `/piano|pianoforte/i` → that's the learner.
2. Else if any track's `program` is in GM Piano family (0–7) → first one wins.
3. Else if a track's name matches `/voice|vocal|melody|lead/i` → that track (display warning: "Playing voice melody on piano").
4. Else fallback: first non-percussion track with the most notes (likely the melody).

The user can override via the Parts picker in `SongDetailView`. Override re-runs `split(_:selection: .trackIndex(N))`.

The percussion track (`isPercussion == true`, channel 10) is always accompaniment, never learner.

**Display labels for the Parts picker**: prefer `instrumentName ?? trackName ?? gmProgramName(program)`, where `gmProgramName` is a static lookup table for the 128 GM programs (e.g., 0→"Acoustic Grand Piano", 19→"Church Organ"). The lookup table is a small sidecar in SVAudio (~3 KB).

#### `ArrangementPlayer` (SurVibe/PlayAlong/Coordinators/)

Owns one `MultiTrackSamplerGraph` configured with the accompaniment MIDI. Exposes:

```swift
@Observable @MainActor
final class ArrangementPlayer {
    var isEnabled: Bool = true                  // Backing toggle "On"
    var tempoScale: Float = 1.0                 // 0.5...1.0
    private(set) var currentBeat: Double = 0    // sampled at display rate

    func load(_ split: PartSplit) async throws
    /// Starts a 1-bar audible count-in at the current tempo, then begins arrangement.
    /// Count-in clicks come from the same sampler graph (channel-10 metronome patch) so
    /// they're tempo-locked to the arrangement and to scoring's host-time clock.
    func start(atBeat: Double = 0, countInBars: Int = 1)
    func pause()
    func resume()
    func stop()
    func setTempoScale(_ rate: Float)           // forwards to sequencer.rate; range 0.5...1.5

    // Section loop (Q7+Q12)
    /// Loop region in measures. nil disables looping. First iteration plays count-in;
    /// subsequent iterations skip count-in. Loops indefinitely until stop() or
    /// clearLoop() is called.
    func setLoop(_ region: LoopRegion?)

    // Hand isolation (Q8+Q11)
    /// Which hand the user is playing. Default .both.
    var practiceMode: PracticeMode

    /// When practiceMode is .rightHand or .leftHand, controls whether the silent
    /// hand still plays audibly through the sampler. Default true.
    var hearOtherHand: Bool

    // Voice / lyrics audibility (Q13)
    // Voice staff (when present and the user is not playing it) is always audible
    // by default; no toggle in v1. Spec §13 voice-audibility decision.
}

public struct LoopRegion: Sendable {
    public let startMeasure: Int    // 1-indexed, inclusive
    public let endMeasure: Int      // 1-indexed, inclusive
}

public enum PracticeMode: Sendable {
    case both
    case rightHand        // RH-only; LH plays/silent per hearOtherHand
    case leftHand         // LH-only; RH plays/silent per hearOtherHand
}
```

Lives in app target (not SVAudio) because it composes app-level coordinators with the SVAudio pipeline.

#### `ScoringAdapter` (Packages/SVLearning/Sources/SVLearning/Practice/)

Bridges live MIDI input to the existing `NoteScoreCalculator`. **`NoteScoreCalculator` is a caseless enum exposing only static methods** (verified at `NoteScoreCalculator.swift:10`); it is not instantiable. The adapter calls `NoteScoreCalculator.score(...)` statically.

```swift
@MainActor
public final class ScoringAdapter {
    public init(score: LearnerScore, tonicSaPitch: UInt8 = 60)  // C4 = Sa default

    /// Feed a MIDI note-on with host-tick timestamp.
    /// `hostTime` is captured at the CoreMIDI callback site (NOT after a MainActor hop).
    /// Returns the matched expected note + score, or nil if no expected note in window.
    public func ingest(midiNote: UInt8, velocity: UInt8, hostTime: HostTime,
                       sequencerStartHostTime: HostTime, currentTempoScale: Float) -> NoteVerdict?

    /// Beat where the next expected note is, for display lookahead.
    public func nextExpected(afterBeat: Double) -> ExpectedNote?

    /// Mark expected notes whose window has fully passed without input as missed.
    public func sweepMissed(currentBeat: Double) -> [UUID]
}

public struct NoteVerdict: Sendable {
    public let expectedID: UUID
    public let score: NoteScore           // existing type, NoteScoreCalculator.score(...) output
    public let timing: TimingClass        // .perfect / .good / .late / .early / .miss
    public let timingDeltaSeconds: Double // signed, real-time
}

public struct SessionScoreSummary: Sendable {
    public let notesAttempted: Int
    public let notesCorrect: Int          // right key in any timing window
    public let notesMissed: Int           // expected note window passed without input
    public let notesExtra: Int            // unmatched user keypresses (not blocking but tracked)
    public let timingAccuracyPercent: Double  // 100 * mean(perfect=1, good=0.7, late/early=0.4, miss=0)
    public let notesCorrectPercent: Double    // 100 * notesCorrect / max(1, notesAttempted)
    public let composite: NoteScore           // existing per-note scoring aggregated
}
```

**Results-overlay display** leads with two distinct numbers — `Notes correct: 100%` and `Timing: 78%` — instead of a single conflated percentage. The composite `NoteScore` aggregate is shown smaller, below the headline metrics, with a "what's this?" tap explaining the 50/30/20 weighting. This preserves honest signal: "I hit the right keys" and "I hit them at the right time" are different skills, and the headline must reflect that.

`HostTime` is a typed wrapper over `UInt64` mach ticks, defined in SVCore so the contract is stable across SVAudio / SVLearning / app-target boundaries:

```swift
// SVCore/Sources/SVCore/Audio/HostTime.swift
public struct HostTime: Hashable, Sendable {
    public let rawTicks: UInt64
    public init(rawTicks: UInt64) { self.rawTicks = rawTicks }
    public static func now() -> HostTime { .init(rawTicks: mach_absolute_time()) }
    public func seconds(since other: HostTime) -> Double { /* mach_timebase_info convert */ }
}
```

Timing windows (real seconds, **not** beats — they don't contract on slow practice):
- Perfect: ±60 ms · Good: ±150 ms · Late/Early: ±300 ms · Miss: outside.

**MIDI-input scoring weight caveat.** With MIDI input the pitch is exact, so `NoteScoreCalculator.pitchAccuracyScore(deviationCents: 0) = 1.0` always. Under the existing 50/30/20 (or 45/25/15/15 with velocity) weighting, every correctly-keyed note gets the full pitch component automatically. This is **acceptable** for v1 — the score still discriminates timing and duration accurately and matches the user's expectation that "playing the right key" is binary on a piano. We document this in the Results overlay so users understand the pitch component reflects "right key" not "in-tune singing." If user feedback later shows scores are too lenient, re-weight in v2 (timing 50% / duration 30% / pitch 20% for MIDI mode).

MIDI-note → swar-string conversion (`NoteScoreCalculator.score` expects `expectedNote: String` like "Sa", "Re", "Ga"…) is done inside the adapter using the user's tonic Sa pitch (`tonicSaPitch`, default C4=60, configurable via tanpura settings). `pitchDeviationCents` is always passed as `0` for MIDI input. `ragaContext` is passed as `nil` for v1 song play-along (raga-aware scoring is for raga drills, not song learning).

### 5.2 Changed components

#### `MultiTrackSamplerGraph` (SVAudio)

**Replace** `setTempo(rate:)` to drive `sequencer.rate` instead of `timePitch.rate`. Pre-release, no compatibility shim.

```swift
public func setTempoScale(_ rate: Float) {
    let clamped = max(0.5, min(1.5, rate))
    sequencer.rate = clamped
    // timePitch.rate stays at 1.0 (passthrough)
}
```

`timePitch` stays in the graph as a 1.0 passthrough so the audio path is unchanged. The audition POC's tempo slider is rewired to call `setTempoScale` and behaves identically from the user's POV (same playback at slower speed) but without the 50–100 ms time-stretch latency.

Existing tests in `MultiChannelEngineParityTests` are updated to assert `sequencer.rate` semantics.

#### `PlaybackCoordinator` (SurVibe/PlayAlong/Coordinators/)

Currently broken (see §12). Refactor to delegate playback to two cooperating engines:

- **Learner playback**: stays scheduled `noteEvents` for the falling-notes / sheet visualization (pre-existing pattern). No audio is emitted from this path — the user provides the audio by playing.
- **Arrangement playback**: new `ArrangementPlayer` owns the audible backing.

`tempoScale` setter now updates BOTH:
- learner schedule timeline (existing visualization clock)
- `arrangement.setTempoScale(tempoScale)`

These share a single `startHostTime: UInt64` captured at `start()`, used by `ScoringAdapter` for timing math.

#### `SongDetailView` (SurVibe/Songs/)

Add a **Parts** section between metadata and action buttons:

```
┌──────────────────────────────────────────────────┐
│ Parts                                            │
│   I'll play:    [ Melody (Piano) ▼ ]             │
│   Backing:      Harmonium · Tabla · Strings      │
│                 (3 instruments)                  │
│   Tonic Sa:     [ C4 ▼ ]   (matches tanpura)     │
│   [ ▶ Preview my part ]   [ ▶ Preview backing ]  │
└──────────────────────────────────────────────────┘
[ Play Along ]   [ Practice ]
```

The **Tonic Sa picker** surfaces the tonic the scoring adapter uses for MIDI-note → swar-string conversion. Default is whatever the user set in the tanpura settings sheet for this song (existing behavior — `SongProgress.preferredSaHz`). Visible here too because for Indian repertoire the tonic choice changes which keyboard keys are correct, and the user needs that affordance in line with the part choice. Range: C3–C5.

**Preview my part** plays the learner's MIDI track once at 1.0× through the same sampler so the user knows the target before attempting. **Preview backing** plays the accompaniment-only path. Both are previews, not Play Along sessions — no scoring, no count-in.

The picker enumerates tracks from `RenderedMIDI.trackInfo`. Selection persisted on `Song` as `learnerTrackIndex: Int?` (default nil = auto).

#### `PlayAlongToolbar` (SurVibe/PlayAlong/)

Add four new controls:

```
… [ Backing: ◉ On  ○ Click  ○ Off ]   [ Tempo: 0.5× ─⬤── 1.5× ]
   [ Hands: ◉ Both  ○ RH  ○ LH ]      [ Loop: m.□ – m.□  ▶ ]
   [ Click level (when Backing=Click): Soft / Normal / Loud ]
```

- **Backing**: `On` (default) — `ArrangementPlayer.isEnabled = true`, metronome off. `Click` — arrangement off, metronome on. `Off` — silent.
- **Tempo slider** — 0.5×–1.5× (Q10), continuous, default 1.0×.
- **Hands** — Both / RH / LH (Q8). When the song's learner part has only one staff, RH and LH chips are disabled with tooltip *"This score has only one staff."* When RH or LH is selected, a follow-up toggle "Hear the other hand" appears (default ON, Q11).
- **Loop** — two measure-number tappers. Tap empty `m.□` for start, displays a small numpad / inline incrementer; tap second `m.□` for end. `▶` activates the loop. While looping, a banner shows *"Looping m.9–12 · tap Stop to end."* (Q7+Q12.)
- **Click level** — only visible when Backing=`Click`. Soft / Normal / Loud presets (Q2).

Slider granularity: 0.05 steps (5% increments) with snap-to-major (0.5, 0.75, 1.0, 1.25, 1.5).

#### `SongImporter` (SVLearning)

Add to import pipeline: after Verovio render succeeds, run `PartSplitter` once and persist the auto-selected `learnerTrackIndex` plus `accompanimentInstruments` summary on the `Song` model. Avoids re-rendering on every detail-view open.

**Accepted file extensions**: `.mxl` (zipped MusicXML), `.musicxml`, `.xml` (plain MusicXML — common from MuseScore export and some online sources). The importer detects format by content sniff (zip magic for MXL, `<?xml` for plaintext) rather than extension alone. Files that aren't MusicXML at all surface a clear error: *"This doesn't look like a MusicXML file. SurVibe accepts .mxl, .musicxml, and .xml exports."*

#### `SongLibraryEmptyState` (existing — copy update)

When the Songs sidebar is empty, the existing empty-state view (`Packages/SVLearning/.../Songs/SongLibraryEmptyState.swift`) gets explicit guidance:

> *"No songs yet. Drop in a `.mxl`, `.musicxml`, or `.xml` file from MuseScore, your teacher, or your own composition. Multi-instrument songs play their backing while you practice the piano part."*

Plus a single bundled **"Try a sample"** button that imports `Sukhkarta_Dukhharta.mxl` from app resources so first-launch isn't a dead end.

#### `Song` (SVCore SwiftData @Model)

New fields (all per-song, single user assumed in v1; multi-user-per-device is forward-compat work and will move these to a per-user-per-song relationship later):

```swift
var learnerTrackIndex: Int?               // Q1 / Q4: nil = auto-pick at load
var accompanimentInstrumentSummary: String? // display-only summary
var defaultPracticeMode: String?          // "both" | "rightHand" | "leftHand"
var lastUsedTempoScale: Double?           // remembered per song
```

Pre-release: full **drop-and-recreate** of the SwiftData store on next launch (Q6). No migration; clean schema. `PracticeSession` model is replaced with the new shape carrying `notesCorrectPercent`, `timingAccuracyPercent`, `notesAttempted`, `notesMissed` directly (Q6).

Multi-user note: when the planned multi-user-per-device feature lands, `learnerTrackIndex` / `defaultPracticeMode` / `lastUsedTempoScale` become per-user-per-song. Plan accordingly when picking the SwiftData entity shape — keep them on `Song` for now but add a `SongUserPreference` junction model later. No work in this spec.

## 6. Data flow at runtime

```
User taps Play Along on Sukhkarta:
   │
   ▼
PlayAlongSceneHost(song:)
   │
   ▼
PlayAlongViewModel.task:
   ├─ load song.mxlData → VerovioBridge.render() ............. ~250 ms
   ├─ PartSplitter.split(rendered, .auto or .trackIndex) ..... ~5 ms
   ├─ ArrangementPlayer.load(split) → graph + sequencer ...... ~80 ms
   ├─ ScoringAdapter(score: split.learner)
   ├─ PlaybackCoordinator.loadSong(song, learner: split.learner)
   │   (parses learner notes for falling-notes visualization)
   └─ ready
   │
   ▼
User taps Play in toolbar:
   │
   ├─ AudioEngineManager.start (already running in most cases)
   ├─ startHostTime = mach_absolute_time()
   ├─ ArrangementPlayer.start(atBeat: 0)
   │   → sequencer.rate = tempoScale
   │   → sequencer.start()
   ├─ PlaybackCoordinator.startScheduling()
   │   → display timeline begins; no audio emitted from this path
   └─ display loop running
   │
   ▼
Per frame (16 ms):
   ├─ TimelineView reads ArrangementPlayer.currentBeat (sampled)
   ├─ Falling notes / sheet cursor advances
   ├─ ScoringAdapter.sweepMissed(currentBeat) → highlight missed notes
   └─ NextExpectedNote glow on keyboard
   │
   ▼
On user keypress (or USB-MIDI event):
   ├─ MIDIInputManager fires AsyncStream<MIDIInputEvent>
   │   timestamp = MIDITimeStamp (host ticks, mach_absolute_time)
   ├─ Sampler note-on (zero-added-latency feedback)
   ├─ ScoringAdapter.ingest(midiNote, velocity, hostTime,
   │                        sequencerStartHostTime, tempoScale)
   │   → converts hostTime → beats, matches against expected notes in ±300 ms window
   │   → returns NoteVerdict
   └─ HUD updates: ✓ / late / wrong, running accuracy
   │
   ▼
On tempo slider change:
   ├─ ArrangementPlayer.setTempoScale(rate) → sequencer.rate = rate
   ├─ PlaybackCoordinator.tempoScale = rate (visualization timeline)
   └─ ScoringAdapter notes new tempo for hostTime → beat conversion
   │
   ▼
On end of arrangement:
   ├─ ArrangementPlayer detects sequencer.isPlaying flips to false
   ├─ PlaybackCoordinator.completeSession()
   ├─ Existing PlayAlongResultsOverlay presented
   └─ PracticeSessionRecorder writes results to SwiftData (existing)
```

## 7. Latency budget

End-to-end input-to-sound, on-screen tap or USB MIDI. **Apple does not document an exact achievable floor**; the table below is a measured target, not an Apple-promised number:

| Stage | Time |
|---|---|
| MIDI event capture (CoreMIDI / touch) | 0–1 ms |
| AsyncStream → main actor hop | 1–2 ms |
| Sampler note-on | <1 ms |
| AVAudioEngine output buffer (256 frames @ **48 kHz native iPad rate** = 5.33 ms) | ~5.3 ms |
| Speaker / headphone output stage | 2–4 ms |
| **Total p50 target** | **~10 ms** |
| **Total p99 target** | **~15–18 ms** |

Targets: **p50 ≤ 12 ms, p99 ≤ 18 ms.** Validated only by on-device measurement (see §9.4); not by Apple-documented guarantee.

### Sample-rate decision

Existing `AudioSessionManager` is configured at 44.1 kHz / 256 frames. iPad's native hardware rate is 48 kHz. Running at 44.1 kHz forces an OS-level sample-rate-conversion (SRC) stage that adds latency and CPU. **Action in this work:** switch project audio session to 48 kHz / 256 frames (5.33 ms IO buffer). All references to "44.1 kHz" and "5.8 ms" elsewhere in code/comments must be updated as part of the change. Resampling of the SF2 (which contains 44.1 kHz samples) is handled by `AVAudioUnitSampler` internally at sample-load time; no per-note runtime cost.

### Buffer-grant verification

`AVAudioSession.setPreferredIOBufferDuration(_:)` is **a hint**, not a guarantee — Apple explicitly documents that the OS may grant a different duration. After session activation, the app must read `AVAudioSession.sharedInstance().ioBufferDuration` and:

- If granted ≤ 7 ms: proceed normally.
- If granted 7–12 ms: log warning, proceed (latency target may be missed at p99).
- If granted > 12 ms: surface a one-time toast — *"Audio buffer is larger than ideal; latency may feel sluggish. This can happen if another audio app is interfering."* — and continue with degraded latency. (No fatal — the feature still works.)

This check happens in `AudioSessionManager` once per session activation. CI gate (§13) asserts the granted value on the reference device.

### Bluetooth MIDI

Apple iOS imposes a Bluetooth LE connection interval floor of **11.25 ms** ([Apple Bluetooth Design Guidelines](https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf)). BLE MIDI is not sample-accurate; observed end-to-end jitter on consumer setups regularly exceeds the spec's ±300 ms scoring window. Combined with handshake overhead and packet aggregation, a Bluetooth MIDI keyboard is incompatible with sample-accurate scoring.

**Detection mechanism:** CoreMIDI does not expose a public transport-type property. The detection is heuristic — query `kMIDIPropertyDriverOwner` on each newly-connected source endpoint at `MIDIInputManager`'s endpoint-add callback. Apple's BLE MIDI driver returns a recognizable owner string (Apple's BTLE MIDI driver bundle ID). This is documented but heuristic — must be tested against real BLE MIDI hardware in §9.4.

**`MIDIInputEvent` has no endpoint metadata** (verified). Detection therefore must happen at the source-enumeration layer in `MIDIInputManager`, NOT per-event. Implementation: maintain a set of "blocked endpoint IDs" (Bluetooth-owned). When the endpoint is added, set the input-port connection state to "blocked" — incoming events from that endpoint are dropped at the `MIDIReadBlock` site (before they enter `noteOnStream`).

**Bluetooth MIDI behavior** (refined after persona review — original "hard block" felt punitive to users with BLE-only keyboards):

- **Default mode**: Bluetooth source is allowed for sampler triggers (you hear yourself play) but **scoring is suppressed** for events from that source. The session enters a "Practice (no scoring)" state.
- **Toolbar chip** (replacing the original full-banner): *"Practice mode — Bluetooth MIDI delay disables scoring. [Why?]"* Tapping "Why?" opens a short explainer popover (one paragraph: BLE 11.25 ms interval floor, jitter, timing window).
- **Results overlay** at end of song: shows progress (notes played, sections covered) but no accuracy %, no stars. Copy: *"Practice complete. Plug in a USB MIDI keyboard to enable scoring."*
- **Hard block path** (kept for safety): if a Bluetooth source emits events with timestamp anomalies that would corrupt the timing math (e.g., timestamps from the future, > 1 s in the past), drop those individual events and log. No banner.

This preserves the value of "play along to backing" for the user, while being honest that scoring requires wired input. Detection mechanism (`kMIDIPropertyDriverOwner`) and endpoint-level dispatch logic unchanged from above; the difference is what we DO when a BLE source is detected.

### Latency instrumentation

`LatencyProbe` records `HostTime.now()` at MIDI-in callback and at the next sampler `AURenderCallback`, computes the delta, logs p50/p99 via `os.signpost` every 10 seconds while Play Along is active. **Wrapped in `#if DEBUG`** (no release-mode dead code). Surfaced in the Diagnostics panel for QA.

## 7a. Audio session, route changes, background

Verified gaps in original draft. Required behavior:

- **Category**: `AVAudioSession.Category.playback` with `.mode = .default` and `.options = [.mixWithOthers]` (allows tanpura drone from another app to coexist if user wants — though we ship our own tanpura). Set at app launch in `AudioSessionManager.activate()`. **Not** `.playAndRecord` — Play Along does not record mic input.
- **Route-change handling**: subscribe to `AVAudioSession.routeChangeNotification`. On `.oldDeviceUnavailable` (USB MIDI keyboard unplugged, headphones removed): pause Play Along, surface a toast — *"Audio device disconnected. Tap Play to resume."* — and ensure the audio engine stays alive (no `engine.stop()`). Existing `AudioSessionManager` has partial handling; extend.
- **Interruption resume**: on `AVAudioSession.interruptionNotification` with `.began`: pause `ArrangementPlayer` and `PlaybackCoordinator`. On `.ended` with `.shouldResume`: call `AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)` then resume on user tap (do not auto-resume — user may have started a call).
- **Background audio**: add `audio` to `UIBackgroundModes` in `Info.plist`. Backing arrangement should continue to play if the user backgrounds during practice (per Apple HIG for music-learning apps). Scoring pauses (no foreground UI to update); arrangement does not. On return to foreground, resume scoring from the current beat without rescheduling expected notes already past.

## 8. Error handling

All errors surface through existing `PipelineError` and `PlaybackCoordinator.errorMessage`. New cases:

| Failure | Surface |
|---|---|
| MXL has zero playable tracks | "This song doesn't contain any playable parts." Block Play Along. |
| `PartSplitter` cannot identify a learner part | Default to first non-percussion track + warning toast: "Couldn't auto-detect a piano part — using the first melodic track. Pick a different part in the song details if needed." |
| `MuseScore_General.sf2` not loaded (missing resource) | App-level fatal at engine init — already handled in `ProductionMultiChannelEngine`. Build-time guard: SwiftLint custom rule fails the build if the file is missing on CI. |
| `AVAudioSequencer.load(from:)` rejects MIDI bytes | "This song's data is corrupted. Try re-importing." Block Play Along. |
| `AVAudioSession` interrupted (call, Siri) | Existing handler in `AudioSessionManager` pauses; user resumes from toolbar. |
| Bluetooth MIDI source connected while Play Along is open | Banner (see §7) + scoring & sampler muted from that source. |

All `PipelineError` paths log via `os.Logger` (subsystem `com.survibe`, category `PlayAlong`) and `PipelineFileLog` (existing).

## 9. Testing

### 9.1 Unit (Swift Testing)

- `PartSplitterTests`:
  - All four bundled MXLs: assert auto-selected learner is the piano/melody track, assert accompaniment includes the expected instruments.
  - Synthetic MXL with explicit `Piano` part name → selection rule 1.
  - Synthetic MXL with no part names, GM Piano program → selection rule 2.
  - Synthetic MXL with `Voice` only → selection rule 3 + warning surfaced.
  - Pure-percussion MXL → throws `noPlayableLearnerPart`.
  - Override `LearnerSelection.trackIndex(N)` returns the expected split.
- `ScoringAdapterTests`:
  - HostTime → beat conversion correct at 0.5×, 0.75×, 1.0×.
  - Note in perfect/good/late/early/miss windows yields correct `TimingClass`.
  - Wrong pitch within window: `score.pitchAccuracy < 0.5`.
  - `sweepMissed` only marks notes whose late window has fully passed.
- `MultiTrackSamplerGraphTests` (updated):
  - `setTempoScale(0.5)` sets `sequencer.rate == 0.5`, `timePitch.rate == 1.0`.
  - Position progresses at correct beat rate at 0.5× over 4 seconds.

### 9.2 Integration

- `LearnASongIntegrationTests` (XCTest, real `AVAudioEngine`):
  - Load `sukhakarta-dukhaharta.mxl`, start arrangement, after 2 seconds assert sequencer position ∈ expected range.
  - Inject 4 simulated MIDI input events at known host times → verify `NoteVerdict` stream matches expected timing classes.
  - Tempo change mid-playback: arrangement audibly slows (no glitch), beat timeline math stays consistent.

### 9.3 UI

- `SongDetailViewTests` (snapshot): Parts section visible, picker enumerates tracks, override persists.
- `PlayAlongToolbarTests` (snapshot): Backing segmented control reflects state.

### 9.4 Manual / device

- Run on iPad with USB MIDI keyboard (Korg microKEY or similar):
  - Measure p50/p99 latency via `LatencyProbe`. Must hit ≤ 12 ms / ≤ 18 ms.
  - All four bundled songs play arrangement audibly correct at 0.5×, 0.75×, 1.0×.
  - Plug in Bluetooth MIDI keyboard → banner appears, scoring suppressed.
  - VoiceOver pass on Songs detail Parts section + toolbar Backing control.

## 10. Telemetry

PostHog events (via `AnalyticsManager`):
- `play_along_started` — props: `songID`, `tempoScale`, `backingMode`, `learnerTrackOverride: Bool`.
- `play_along_completed` — props: `accuracy`, `durationSec`, `notesScored`, `notesMissed`.
- `play_along_aborted` — props: `cause: "user_stop" | "interruption" | "error"`.
- `bluetooth_midi_blocked` — props: `endpointName` (anonymized hash).

## 11. Decisions log (locked 2026-04-30)

| # | Decision | Rationale |
|---|---|---|
| D1 | **Tempo model A** — fixed-tempo backing with user-selected scale 0.5×–1.0× | Real musical experience, buildable in weeks. Score-following deferred. |
| D2 | **Canonical storage = `.mxl`** (zipped MusicXML); MIDI is derived | Lossless for staff render; ~5–10× smaller than raw XML; matches MuseScore/Soundslice/Verovio. |
| D3 | **Tempo control = `AVAudioSequencer.rate`**, NOT `AVAudioUnitTimePitch.rate` | TimePitch is a time-stretch DSP stage that adds buffering latency; not appropriate for play-along. `AVAudioSequencer.rate` scales the MIDI playback timeline (Apple-documented at [AVAudioSequencer.rate](https://developer.apple.com/documentation/avfaudio/avaudiosequencer/rate)) and does not invoke time-stretch DSP. Pre-release: replace TimePitch path entirely; `timePitch.rate = 1.0` passthrough. Range and live-mutation behavior are not formally documented by Apple — verify in §9.4. |
| D4 | **Latency target ≤ 12 ms p50 / ≤ 18 ms p99** at **48 kHz / 256 frames** (5.33 ms IO buffer) | Achievable on M-series iPad based on hardware spec; Apple does NOT guarantee a specific number. `setPreferredIOBufferDuration` is a hint — see §7 buffer-grant verification. Switching project sample rate from 44.1 kHz to 48 kHz to match iPad hardware. |
| D5 | **Bluetooth MIDI: scoring suppressed, sound allowed** ("Practice mode") in Play Along | iOS BLE connection-interval floor 11.25 ms; jitter exceeds scoring window. But persona review flagged that hard-blocking BLE input feels punitive to users with BLE-only keyboards (GarageBand habit). Compromise: allow BLE for sampler triggers (you hear yourself), suppress scoring + stars, show a "Practice mode" chip with "Why?" affordance. Detection via `kMIDIPropertyDriverOwner` heuristic; dispatch decision at endpoint-add. |
| D6 | **Scoring timing via CoreMIDI host-tick timestamps**, not sequencer position reads | `MIDITimeStamp` is a `mach_absolute_time` `UInt64` (sub-µs precision; Apple-documented at [MIDITimeStamp](https://developer.apple.com/documentation/coremidi/miditimestamp)). `AVAudioSequencer.currentPositionInBeats` is suitable for ~16 ms display-cursor reads but is not Apple-documented as suitable for sample-accurate timing reads off the render thread; use only for visualization. Wrap host time as typed `HostTime` in SVCore. Capture host time at the CoreMIDI callback site (CoreMIDI thread), then hop to MainActor for scoring. |
| D7 | **Sound bank = MuseScore_General.sf2** (already shipped at `Packages/SVAudio/.../Resources/`, ~215 MB, MIT, gitignored, manual placement) | Already integrated; FluidR3-quality GM bank covers all four bundled songs. **Memory caveat**: `AVAudioUnitSampler.loadSoundBankInstrument` mmap behavior is undocumented; resident memory should be profiled on the lowest-spec target iPad in §9.4. If RSS exceeds budget, fall back to a stripped sub-SF2 containing only the GM programs the bundled songs use (~10× smaller). Tracked as Q3 in §15. |
| D8 | **Reuse `SongPlayAlongView` end-to-end**, no new tab, no full-screen redesign | ~25 files of working UI exist (falling notes, sheet, scoring HUD, tanpura, results, wait-mode infrastructure). Pre-release flexibility doesn't mean throwing away work that fits the new feature. |
| D9 | **Two new UI affordances only**: Parts section in `SongDetailView`, Backing segmented control in `PlayAlongToolbar` | Fits existing toolbar/detail patterns; discoverable in places users already look. |
| D10 | **MIDI-input-only Play Along** (touch + USB MIDI; no microphone, no Bluetooth) | Matches Play tab guardrail. Pitch-from-mic is a different feature. |
| D11 | **Bundle splits at import time**, not on each detail-view open | One Verovio render + split per song; persisted on `Song`. |
| D12 | **`PlayAlongWaitController` stays in code, disabled in v1 UI** | Mode B (wait-for-user) is valuable but not v1 scope. Keep code for future re-enable. |

## 12. Replacing the broken Play Along path

Current state: tapping Play Along from `SongDetailView` mounts `PlayAlongSceneHost(song:)` → `PlayAlongViewModel` → `PlaybackCoordinator.loadSong(_:)`. Something in this chain is broken — no playback occurs.

**Plan-stage prerequisite (Day 1):** spend ~1 day reading the existing chain end-to-end (`PlayAlongSceneHost`, `PlayAlongViewModel.task`, `PlaybackCoordinator.loadSong`, recent commits since the Wave 4/5 merge on 2026-04-18) and isolating the actual fault before discarding code. The "broken" symptom may be a missing guard, an unhandled error swallowing the load failure, or a regression from a recent merge. Document the fault root-cause in the implementation plan's Day 1 deliverable, then decide whether to:

- (a) preserve more of the existing architecture and patch the fault, then layer `ArrangementPlayer` on top, OR
- (b) proceed with the rewrite this spec describes.

Default is (b) — the rewrite is justified by the multi-instrument backing requirement that the current path doesn't support — but a 1-day diagnosis pass is cheap insurance against repeating a fault we don't understand.

This spec's plan replaces the path rather than diagnosing it (with the Day-1 caveat above):
- `PlaybackCoordinator` keeps its visualization-timeline duties only.
- New `ArrangementPlayer` owns audible playback.
- They share `startHostTime` and `tempoScale`.
- The "`soundFont.playNote(...)` for scheduled notes" pattern in `PlaybackCoordinator` is removed — there is no audio path through `PlaybackCoordinator` anymore. All scored audio comes from the user; all backing audio comes from `ArrangementPlayer`.

This deliberately simplifies. We do not maintain two playback paths.

## 13. Migration & rollout

Pre-release, no users — straight ship. CI gate:

1. Build passes with `MuseScore_General.sf2` placed.
2. All unit tests pass.
3. All four bundled MXLs load and play arrangement on simulator.
4. On-device latency probe reports p50 ≤ 12 ms on a reference iPad (M2).

## 13a. Known gaps deferred to follow-up specs

Surfaced by the persona review. Section loop, hand isolation, lyrics, and speed > 1.0× were pulled INTO v1 scope (see §3 Goals, §5.1 PartSplitter, §5.2 PlayAlongToolbar). Remaining v2 candidates:

- **Transposition** to keyboard range (e.g., shift down 2 semitones). Re-render via Verovio with `<transpose>` element. Workaround in v1: re-import a transposed MusicXML.
- **Recording playback / share.** "Hear what I just played" + "send my cousin a badge." `PracticeSessionRecorder` already records; surfacing it is UI-only.
- **Audio output route warning.** When user has no headphones AND no MIDI-keyboard speakers AND iPad is set to a quiet route. Soft-warning toast.
- **Voice-staff "Sing the words" mute toggle** (Q13 alternative B). v1 ships with voice always audible when present (the natural full-arrangement experience for Indian repertoire). Add an opt-out toggle in v2 if user feedback wants it.
- **Multi-user-per-device** profiles. Spec assumes single default user for v1. When multi-user lands, `Song.learnerTrackIndex` / `defaultPracticeMode` / `lastUsedTempoScale` move to a `SongUserPreference` junction model.
- **Karaoke-style highlighted lyrics strip** (Q9 alternative B). v1 uses Verovio-native lyrics rendering only.

## 14. Import-format scope and out-of-scope

**In scope for v1:** `.mxl`, `.musicxml`. Both go through Verovio → `PartSplitter` → full Play Along with backing.

**MIDI imports (`.mid`):** accepted by `SongImporter` but flagged. Whole MIDI is treated as the learner part; `PartSplitter` is bypassed; backing is silent. Detail view shows a banner: *"This song was imported from MIDI. Notation is approximate, and there's no backing arrangement."* Re-import as MusicXML to upgrade the experience.

**Explicitly out of scope** (deferred to future specs):
- PDF / photo OMR.
- ABC / Sargam text imports.
- Mode B wait-for-user, Mode C score-following.
- Mic / pitch-from-voice.
- Bluetooth MIDI.
- Speed > 1.0×.
- Cloud / shared library / community uploads.
- `MNX` format (W3C, not yet stable).

## 15. Open questions — RESOLVED 2026-04-30

All six prior open questions are now decided. Recorded for traceability:

- **Q1 — `learnerTrackIndex` scope.** **Per-song.** Stored on `Song.learnerTrackIndex`. Multi-user-per-device is future work; when it lands, fields move to a `SongUserPreference` junction model.
- **Q2 — Click mode volume.** **Master volume + Click level preset (Soft / Normal / Loud)**, surfaced in toolbar only when Backing=`Click`.
- **Q3 — 215 MB SF2 memory profile.** **Ship full SF2 always; no fallback build.** §9.4 still profiles RSS for awareness, but no stripped sub-SF2 path.
- **Q4 — Verovio meta-3/4 emission.** **Extend SMF parser to read meta-3 / meta-4 with GM-program fallback when absent.** Plan-stage pre-flight test on the four bundled MXLs.
- **Q5 — `AVAudioSequencer.rate` live mutation.** **Apply live during playback; verify in §9.2.** Fall back to pause-apply-resume only if real-device testing shows egregious glitches.
- **Q6 — `PracticeSession` schema.** **Drop-and-recreate the SwiftData store with new shape carrying `notesCorrectPercent` / `timingAccuracyPercent` / `notesAttempted` / `notesMissed` directly.** Pre-release; no migration.

**Newly added scope decisions** (Q7–Q13):

- **Q7 — Section loop UX.** **Tap measure numbers** to set start/end. Two `m.□` tappers in the toolbar.
- **Q8 — Hand-isolation detection.** **MusicXML `<staff>1</staff>` / `<staff>2</staff>`.** RH/LH chips disabled when only one staff exists.
- **Q9 — Lyrics rendering mechanism.** **Verovio-native** — included in the rendered SVG. Voice/lyrics-bearing staff is **always visible** when MusicXML has lyrics, even when the user picks a non-voice learner part.
- **Q10 — Tempo upper cap.** **0.5×–1.5×.** Matches existing `MultiTrackSamplerGraph` clamp.
- **Q11 — Hand isolation audibility.** **Toggle "Hear the other hand," default ON.** Visible only when RH-only or LH-only is selected.
- **Q12 — Loop count-in & termination.** **First-iteration count-in only**; subsequent loops snap straight back. **Loop indefinitely until user stops.**
- **Q13 — Voice staff audibility when learner is non-voice.** **Voice is audible** as part of the full arrangement. No mute toggle in v1.

## 16. Independent review (2026-04-30)

This spec was reviewed independently against (a) the actual codebase and (b) Apple Developer documentation. Findings landed back into the spec via the following amendments:

- **§5.1 PartSplitter**: track-name selection rule depends on `TrackInfo.trackName/instrumentName`, which the current `VerovioBridge` SMF parser does NOT capture. Spec now includes the parser extension as a prerequisite, with GM-program-only fallback.
- **§5.1 ScoringAdapter**: `NoteScoreCalculator` is a caseless enum with static methods, not instantiable. Constructor signature corrected. MIDI-input scoring weight caveat (50% pitch is automatic for correct keys) acknowledged with an explicit v2 re-weight option.
- **§5.1 HostTime typed wrapper** in SVCore replaces raw `UInt64` crossing package boundaries.
- **§7 sample rate**: switched from 44.1 kHz (existing project config) to 48 kHz (iPad native). Recomputed IO buffer to 5.33 ms.
- **§7 buffer-grant verification**: `setPreferredIOBufferDuration` is a hint, not a guarantee — added post-activation verification with three-tier behavior.
- **§7 Bluetooth detection**: replaced unsubstantiated "400 ms drift" claim with the documented 11.25 ms iOS BLE connection-interval floor. Specified `kMIDIPropertyDriverOwner` heuristic at endpoint enumeration (no public transport API exists). Acknowledged `MIDIInputEvent` carries no endpoint metadata, so detection happens at endpoint-add, not per-event.
- **§7 latency claims**: dropped "sample-accurate, zero-DSP-latency" superlatives. Latency is a measured target, not Apple-promised.
- **§7a (new)**: audio session category (`.playback` + `.mixWithOthers`), route-change handling, interruption resume semantics, background-audio entitlement.
- **§7 LatencyProbe**: `os.signpost` + `#if DEBUG` gating.
- **§D7 SF2 memory caveat**: `AVAudioUnitSampler` mmap behavior undocumented; profile on lowest-spec iPad; stripped sub-SF2 fallback option added as Q3.
- **§D6**: dropped "±5–50 ms jitter" undocumented claim; soft-language only.
- **§12 Day-1 diagnosis prerequisite**: spend 1 day root-causing the broken path before committing to full rewrite.

Net effect: spec is more conservative on Apple-API claims, more concrete on detection mechanisms, and adds two prerequisite work items (Verovio parser extension; project sample-rate switch) to the LOC budget.

## 17. Persona review (2026-04-30)

Stress-tested as **Ravi, 45, intermediate hobbyist** importing a MusicXML of *Vande Mataram* with a Bluetooth MIDI keyboard. Five real friction points surfaced and folded back into the spec:

- **§2 Count-in**: a 1-bar audible count-in now plays before the arrangement starts. Without it, every first attempt fails the opening bars. Implementation: `ArrangementPlayer.start(countInBars:)` schedules count-in clicks on a metronome channel before triggering the arrangement.
- **§7 Bluetooth MIDI fallback**: original "hard block" downgraded to "Practice mode (no scoring)" — BLE input still drives the sampler so the user hears themselves play, scoring is suppressed, results overlay shows progress without accuracy. Honest about the limitation, not punitive.
- **§5.2 Tonic Sa picker** added to `SongDetailView` Parts section: surfaces the existing-but-buried `SongProgress.preferredSaHz` setting in the place where users decide what they're playing. Two preview buttons added: "Preview my part" + "Preview backing" (was: backing only).
- **§5.1 Scoring display split**: results overlay now leads with **two** numbers — *Notes correct: X%* and *Timing: Y%* — instead of one conflated 92%. Composite `NoteScore` shown smaller below with a "what's this?" affordance. Honest signal: hitting the right key and hitting it on time are different skills.
- **§13a Known gaps**: section loop, hand isolation, transposition, lyrics, speed > 1.0×, recording-playback/share, audio-route warning — explicitly listed as v2 candidates so they don't get re-discovered as missing.

Plus minor:
- **`SongLibraryEmptyState`** copy update + "Try a sample" button so first-launch isn't a dead end.
- **`.xml`** plain MusicXML accepted alongside `.mxl` and `.musicxml` (sniff content, not extension).

Net effect: ~250 LOC added (count-in scheduler, Sa picker UI, results-overlay split, BLE practice-mode dispatch, empty-state button). Updated total ~2,580 LOC; estimate stays at 4 weeks build + 1 week tuning.

---

## Component LOC summary

| Component | New | Edit | Total |
|---|---|---|---|
| `PartSplitter` (SVAudio) | 300 | — | 300 |
| `PartSplitterTests` | 250 | — | 250 |
| `ArrangementPlayer` (app) | 250 | — | 250 |
| `ScoringAdapter` (SVLearning) | 150 | — | 150 |
| `ScoringAdapterTests` | 200 | — | 200 |
| `MultiTrackSamplerGraph` tempo fix | — | 30 | 30 |
| `VerovioBridge` SMF meta-3/4 parser extension | 80 | — | 80 |
| `HostTime` typed wrapper (SVCore) | 40 | — | 40 |
| `gmProgramName` lookup table | 60 | — | 60 |
| `AudioSessionManager` 48 kHz switch + buffer-grant + route + interruption | — | 120 | 120 |
| `MIDIInputManager` Bluetooth-source blocklist + Practice-mode dispatch | 130 | — | 130 |
| Count-in scheduler in `ArrangementPlayer` | 60 | — | 60 |
| Tonic Sa picker (Parts section) + "Preview my part" button | 90 | — | 90 |
| Results overlay split (Notes correct / Timing %) | — | 80 | 80 |
| `SongLibraryEmptyState` copy + "Try a sample" button | — | 40 | 40 |
| `.xml` content-sniff in `SongImporter` | — | 30 | 30 |
| **Section loop** (toolbar UI + LoopRegion model + ArrangementPlayer setLoop) | 280 | 40 | 320 |
| **Hand isolation** (PartSplitter staves + practice-mode in ArrangementPlayer + toolbar UI + "Hear other hand" toggle) | 230 | 40 | 270 |
| **Lyrics** (Verovio render-with-lyrics flag + voice-staff-always-visible logic) | 50 | 30 | 80 |
| **Speed range 1.0× → 1.5×** (slider config + toolbar copy) | — | 20 | 20 |
| **Click level preset** (Soft/Normal/Loud) UI + sampler velocity offset | 80 | — | 80 |
| Voice/lyrics staff display logic in render pipeline | 60 | — | 60 |
| `PlaybackCoordinator` rework | — | 200 | 200 |
| `Song` model fields | — | 10 | 10 |
| `SongImporter` part-split persistence | — | 80 | 80 |
| `SongDetailView` Parts section | 120 | — | 120 |
| `PlayAlongToolbar` Backing control | 60 | — | 60 |
| `LatencyProbe` (debug only) | 80 | — | 80 |
| Integration tests | 200 | — | 200 |
| **Total** | **~2900** | **~720** | **~3620** |

Estimate: 5–6 weeks build + 1 week tuning/test on device. Reflects the four newly-in-scope features (section loop, hand isolation, lyrics, speed > 1.0×) plus the Click-level preset added by Q2.
