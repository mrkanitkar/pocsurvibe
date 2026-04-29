# Play Tab v2 — Riyaz Recorder

> Status: Brainstorm-approved spec, ready for plan.
> Date: 2026-04-29
> Author: Claude (brainstorming) + Mahesh (decisions)
> Supersedes: nothing — extends Play tab v1 (`docs/superpowers/specs/2026-04-28-play-tab-design.md`).

---

## 1. Goals

Expand the Play tab so a student can:

1. Play a full song (up to ~5,000 notes / ~5 minutes) on the iPad piano or external MIDI keyboard, not just a 16-note strip.
2. View the entire performance on a grand staff that scrolls / scrubs.
3. Save selected performances as named "takes" that persist across launches.
4. Play back a saved take through the iPad sampler — with speed control, hand-soloing, and visual sync on the staff and keyboard.
5. Export takes as **MusicXML 4.0**, **MXL**, and **Standard MIDI File** via the iOS share sheet.

The Play tab remains a free-noodle space first. All save / export / take-management UI is hidden behind progressive disclosure so the casual user never has to see it.

## 2. Non-goals (deferred to v3+)

- **Microphone / vocal input.** Hard guardrail — Play tab is keyboard-only (iPad on-screen + external MIDI). Mic is the Practice tab's job.
- **Tempo / metronome / click track during recording.** Tied up with the rhythm-fidelity decision (§4.1) — revisit when designing v3 quantization.
- **Implicit bar lines on the live staff.**
- **Instrument-swap on playback.** (Take always plays back with its recording-time instrument.)
- **A–B loop / region playback.**
- **Transpose / Sa-shift on playback.**
- **Record-along / overdub.**
- **MusicXML pedal markings** (CC 64 captured + emitted to MIDI; MusicXML pedal lines deferred).
- **MusicXML dynamics text** (velocity captured + emitted to MIDI; pp/p/mf/f text deferred).
- **Notation PDF export.**
- **iCloud Drive auto-sync** of takes (share-sheet handles all sharing).
- **Audio export to .m4a.** Deferred. Apple's offline-render API requires a *second* `AVAudioEngine` instance plus interleaved-scheduling logic against `manualRenderingSampleTime`; the engineering cost (≈2 days) is out of scope for v2. Students can render audio externally via MuseScore from the exported MusicXML.
- **Sa drone / Tanpura on Play tab.** Deferred — the existing `TanpuraEngine` uses a separate `AVAudioPlayerNode` (not the multi-channel sampler). Bringing a bank-driven drone into the multi-channel engine is a v3 task. Practice tab continues to use `TanpuraEngine` as-is.
- **Auto-save scratchpad to disk for crash recovery.** Targeted as a v2.1 fast-follow if user-loss reports come in.

## 3. Non-regression contract

**Scope**: SurVibe has not shipped to users. There are no field-deployed takes, no CloudKit-stored recordings, and no third-party MusicXML/MIDI files in the wild. So this contract is **internal-only**: it protects the developer experience and the test suite, not user-facing back-compat.

**Hard requirements** (must not break):

- **Existing tests in `SurVibeTests/Play/` must keep passing.** Any test that needs to change because of a deliberate v2 design choice gets updated in the same commit as the producing change, and the change is justified in the commit body.
- **PlayTab v1 noodling case must keep working** — instrument selection, MIDI input, touch input, visual highlight, Sargam labels — at parity or better latency.
- **`playTouchNote` / `stopTouchNote` / `stopAllTouchNotes` API on slot 0 stays unchanged.** Live touch is the most safety-critical audio path; v2 only adds new APIs alongside.
- **No new compiler warnings.** Existing `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` invariant holds.

**Free to change** (no users, no migrations):

- `RecordedNote`'s field set can grow without preserving a v1 initializer. Existing call sites get updated in the same diff.
- Removing the v1 16-note `RecordingStripView` is fine — no user data depends on it.
- Schema for `RecordedTake` is greenfield; no migration plan required.
- File formats (.musicxml, .mid, .mxl) get to be whatever spec-correct shape we ship — no "must round-trip with old SurVibe export."

Net effect: the spec leans on "extend in place where convenient, replace where cleaner" rather than back-compat gymnastics.

## 4. Decisions locked from brainstorming

(Each row records the decision, the rationale, and which question it came from.)

| # | Decision | Source |
|---|---|---|
| 4.1 | **Soft cap 1,500 notes / hard cap 5,000 notes per scratchpad.** Soft cap shows a "save this and start fresh?" banner. Hard cap pauses capture (audio still plays — just no more capture). | Q1-D |
| 4.2 | **Capture wall-clock timestamps** (sub-frame, sample-accurate). No upfront BPM, no metronome. Quantization happens *only* at MusicXML/MXL export, with a quantize sub-sheet (BPM picker + tap-tempo + time-sig + grid). MIDI export emits real-timing SMF (PPQ=1000, tempo 60 BPM = 1 ms/tick). | Q2-B+ |
| 4.3 | **Always-recording scratchpad** + explicit **Save** snapshots full scratchpad as a take. **New Session** clears scratchpad with guard. | Q3-C, C1 |
| 4.4 | **Compact live staff (today's UI) + tap-to-expand timeline sheet** for review/playback (Staff tab + Waterfall tab). **Tab navigation away from Play clears scratchpad** with confirm-or-cancel guard. **Saved takes persist** in SwiftData (Path 1). | Q4-C, Path 1 |
| 4.5 | **Playback features**: Play/Pause/Restart, same instrument as recording, speed (0.5×–1.5×), hand solo (treble/bass split at MIDI ≥60), visual sync on staff + keyboard via existing `MIDINoteHighlightCoordinator`. | Q5: ★+A+C+E+G |
| 4.6 | **Take metadata** (default): editable title, auto duration, auto note count. Optional: raga tag, free-text teacher notes (in "Edit details" expandable). | Q6-6a |
| 4.7 | **Export formats**: MusicXML 4.0, MXL, Standard MIDI File (Type 0). m4a deferred. | Q6-6b |
| 4.8 | **Share path**: iOS share sheet only. Files / iCloud / WhatsApp / Mail / AirDrop all reachable via the share sheet. | Q6-6c-α |
| 4.9 | **Student-experience layer**: undo last note, sustain-pedal capture + MIDI export, velocity capture + playback + MIDI export, empty-state hints, recording indicator + duration counter, graceful errors (MIDI disconnect, sampler fallback), delete take, rename take, unsaved-scratchpad guard prompt. | Q7-1,2,3,4,5,6,9,10,11 |
| 4.10 | **Architectural fit**: extend in place — pure types + quantizer + MusicXML/MIDI serializers in SVCore; `TakePlaybackEngine` + `MXLPackager` in SVAudio; `RecordedTake` `@Model` and all UI in the SurVibe app target (CloudKit constraint). | Q8-A |
| 4.11 | **Sa pitch on saved takes**: stored at recording time; Sargam labels in playback view always re-rendered against the take's stored Sa, not the global current Sa. Take row shows a "Sa = C" badge so it's visible. | Q10-a |
| 4.12 | **Background recording**: pause capture when app is backgrounded; resume on foreground. Required because without a `UIBackgroundModes: ["audio"]` declaration, CoreMIDI packets are *dropped* (not queued) while suspended. v2 does not declare audio background mode. | Q11-a |

## 5. Architecture

### 5.1 Module / package allocation

```
SVCore  (foundation, no AVFoundation, no AudioKit, no zip)
├── Play/RecordedNote.swift                    -- value type (extend existing)
├── Play/RecordedSustainEvent.swift            -- value type
├── Play/QuantizedNote.swift                   -- value type, output of Quantizer
├── Play/MusicalDuration.swift                 -- enum (whole, half, quarter, eighth, 16th, dotted variants, tuplets)
├── Play/Quantizer.swift                       -- pure logic (BPM + grid + time-sig in → QuantizedScore out)
├── Play/MusicXMLSerializer.swift              -- pure logic (QuantizedScore → MusicXML 4.0 string, no namespace, DTD declared)
├── Play/MIDISerializer.swift                  -- pure logic (RecordedNote+Sustain → SMF Type-0 bytes, PPQ 1000, 60 BPM tempo meta)
├── Play/SargamLabeler.swift                   -- MOVED from app target; pure value-type mapping
└── Play/SargamLabel.swift                     -- value type (already exists, moves alongside)

SVAudio  (depends on SVCore, has AudioKit + ZIPFoundation + AVFoundation)
├── Playback/TakePlaybackEngine.swift          -- @MainActor, schedules notes/sustain to slot 2 with playhead sync
├── Playback/TakePlaybackProviding.swift       -- protocol for testability
├── Playback/MXLPackager.swift                 -- ZIPFoundation; mimetype-first uncompressed entry, container.xml, score.musicxml
└── Protocols/MultiChannelEngineProtocol.swift -- EXTENDED: + playNoteOnSlot, stopNoteOnSlot, allNotesOffOnSlot, scheduleMIDIEvent (default impl on protocol so existing mocks compile)

SurVibe (app target — owns SwiftData models per CLAUDE.md rule)
├── Models/RecordedTake.swift                  -- @Model, holds take metadata + .externalStorage Data blobs
├── Play/ScratchpadState.swift                 -- @MainActor @Observable, ephemeral, owns the live recording buffer
├── Play/PlayTabViewModel.swift                -- EXTENDED: scratchpad/take/export coordination
├── Play/RecordedNote.swift                    -- (existing struct) moved to SVCore; existing call sites updated to import SVCore
├── Play/PlayTabToolbar.swift                  -- EXTENDED: ● recording dot + duration, ↶ Undo, ⋯ overflow
├── Play/PlayTabBottomStrip.swift              -- NEW: subtle timeline strip, scrubber, expand button
├── Play/ExpandedTimelineSheet.swift           -- NEW: Staff/Waterfall/Notes tabs, transport bar
├── Play/TimelineStaffView.swift               -- NEW: horizontal-scroll grand staff with playhead, viewport-culled
├── Play/TimelineWaterfallView.swift           -- NEW: vertical bars per key, time flows down
├── Play/TakesListSheet.swift                  -- NEW: list of saved takes (delete/rename/open)
├── Play/SaveTakeSheet.swift                   -- NEW: title + details on save
├── Play/ExportTakeSheet.swift                 -- NEW: format checkboxes + Quantize sub-sheet
├── Play/QuantizeSheet.swift                   -- NEW: BPM picker + tap-tempo + time-sig + grid
├── Play/UnsavedScratchpadGuard.swift          -- NEW: confirmation dialog + tab-rollback helper
└── ContentView.swift                          -- EXTENDED: route guard hooks for tab change + AppRouter.switchTab interception
```

### 5.2 Data model

```swift
// SVCore/Sources/SVCore/Play/RecordedNote.swift
//
// REPLACES the v1 internal struct at SurVibe/Play/PlayTabViewModel.swift:24.
// All v1 call sites are updated in the same commit. Since the project has no
// shipped users, schema migration is not a concern.

public struct RecordedNote: Identifiable, Equatable, Sendable, Codable, Hashable {
    public let id: UUID
    public let midi: UInt8                  // 0–127
    public let velocity: UInt8              // 1–127 (0 reserved for "off-only" sentinel; not used in arrays)
    public let velocity16Bit: UInt16        // MIDI 2.0 high-resolution velocity, 0 if absent
    public let onTimeSec: TimeInterval      // wall-clock relative to scratchpad/take start
    public let offTimeSec: TimeInterval     // wall-clock; equals onTimeSec while note is still open
    public let channel: UInt8               // CoreMIDI channel, default 0

    public init(id: UUID = UUID(), midi: UInt8, velocity: UInt8, velocity16Bit: UInt16 = 0,
                onTimeSec: TimeInterval, offTimeSec: TimeInterval, channel: UInt8 = 0) { … }
}
```

The legacy `timestamp: Date` field is dropped — `onTimeSec` (relative to scratchpad start) is the canonical timing primitive. v1 callers that displayed a wall-clock badge use `scratchpad.startedAt + onTimeSec` to recompute.

```swift
// SVCore/Sources/SVCore/Play/RecordedSustainEvent.swift

public struct RecordedSustainEvent: Sendable, Codable, Hashable {
    public let timeSec: TimeInterval
    public let down: Bool                   // CC64 ≥64 = down, else up
    public let channel: UInt8
}
```

```swift
// SurVibe/Models/RecordedTake.swift
// Lives in app target — SwiftData @Model classes must share the module that
// owns the CloudKit container (.claude/rules/app-target.md).

import Foundation
import SwiftData

@Model
public final class RecordedTake {
    @Attribute(.unique) public var id: UUID
    public var title: String                                  // "Take 5 · 29 Apr 19:42" or user-edited
    public var createdAt: Date
    public var instrumentProgram: UInt8                       // GM 0–127 from recording session
    public var saPitchMidi: UInt8                             // for Sargam re-rendering on playback (decision 4.11)
    public var ragaTagId: String?                             // optional, references existing raga catalog
    public var teacherNotes: String                           // free text, default ""
    public var durationSec: Double                            // computed at save time
    public var noteCount: Int

    @Attribute(.externalStorage) public var notesData: Data?  // JSON-encoded [RecordedNote]
    @Attribute(.externalStorage) public var sustainData: Data? // JSON-encoded [RecordedSustainEvent]

    @Transient public var cachedNotes: [RecordedNote]?         // decoded on demand
    @Transient public var cachedSustain: [RecordedSustainEvent]?

    public init(id: UUID = UUID(),
                title: String,
                createdAt: Date = .now,
                instrumentProgram: UInt8,
                saPitchMidi: UInt8,
                ragaTagId: String? = nil,
                teacherNotes: String = "",
                notes: [RecordedNote],
                sustain: [RecordedSustainEvent]) { … }
}
```

```swift
// SurVibe/Play/ScratchpadState.swift
// @MainActor @Observable. In-memory only. Wiped on tab change, New Session,
// or Save. Open notes flushed at clear / hard-cap with offTimeSec = "now".

@MainActor @Observable
public final class ScratchpadState {
    public private(set) var notes: [RecordedNote] = []
    public private(set) var sustain: [RecordedSustainEvent] = []
    public private(set) var startedAt: Date?
    public private(set) var instrumentProgram: UInt8 = 0
    public private(set) var saPitchMidi: UInt8 = 60          // C4 default

    private var openNotes: [UInt8: PendingNote] = [:]        // midi → onTime + velocity (in flight)
    private var undoStack: [UndoEntry] = []                  // capped at 20

    public var noteCount: Int { notes.count }
    public var isAtSoftCap: Bool { notes.count >= 1500 }
    public var isAtHardCap: Bool { notes.count >= 5000 }
    public var hasContent: Bool { !notes.isEmpty || !openNotes.isEmpty }
    public var durationSec: TimeInterval { … }                // 0 if startedAt nil; running otherwise

    public func appendNoteOn(midi: UInt8, velocity: UInt8, velocity16: UInt16, channel: UInt8) { … }
    public func appendNoteOff(midi: UInt8, channel: UInt8) { … }
    public func appendSustain(down: Bool, channel: UInt8) { … }
    public func undoLastNote() -> Bool { … }                  // pops latest closed note + bumps undoStack
    public func clear() { … }                                 // resets startedAt; flushes open notes first
    public func freezeForSave() -> (notes: [RecordedNote], sustain: [RecordedSustainEvent]) { … }
}
```

### 5.3 State machine — recording lifecycle

```
                  ┌─────────┐  app launches / user taps Play tab
                  │ INACTIVE│ ─────────────────────┐
                  └─────────┘                      │
                       ▲                           ▼
                       │  user navigates    ┌─────────────┐
                       │  to other tab      │ READY       │  scratchpad empty,
                       │  (no content)      │ (idle)      │  startedAt = nil
                       │                    └─────────────┘
                       │                           │
                       │                first note │ played
                       │                           ▼
                       │                    ┌─────────────┐
            ┌──────────┴──────────┐ Save→   │ RECORDING   │
            │ tab change /        │ ◄────── │ (always-on, │
            │ New Session         │         │  scratchpad │
            │ + content           │  Save   │  filling)   │
            │ → guard prompt      │   │     └─────────────┘
            │   "Save / Discard / │   │            │
            │   Cancel"           │   │            │ noteCount ≥ 1500
            │ Cancel rolls back   │   │            ▼
            │ tab selection.      │   │      ┌─────────────┐
            └─────────────────────┘   │      │ SOFT_CAP    │ banner shown
                                      │      └─────────────┘ recording continues
                                      │            │
                                      │            │ noteCount ≥ 5000
                                      │            ▼
                                      │      ┌─────────────┐
                                      │      │ HARD_CAP    │ capture paused;
                                      │      └─────────────┘ touch audio still works
                                      │            │
                                      │            │ Save / Discard
                                      ▼            ▼
                                ┌─────────────┐
                                │ MATERIALIZE │ writes RecordedTake
                                │ TAKE        │ to SwiftData via app's modelContext
                                └─────────────┘
                                      │
                                      ▼ scratchpad cleared, startedAt=nil
                                  READY
```

Background transitions (decision 4.12): when `scenePhase` becomes `.background`, `ScratchpadState.startedAt` is preserved but new MIDI events are dropped at the input layer. On `.active`, capture resumes with no time-shift compensation (gap simply appears in the recording). Acceptable because the alternative — claiming the iOS audio background mode just for keystroke capture — is overkill.

### 5.4 UI structure

#### 5.4.1 Default layout (simplified per progressive-disclosure principle)

```
┌─────────────────────────────────────────────────────────────┐
│ [Sitar ▾]   ● 0:42   [↶ Undo]                  [⋯ More]      │  toolbar
├─────────────────────────────────────────────────────────────┤
│       (treble + bass live grand staff — UNCHANGED v1)        │
├─────────────────────────────────────────────────────────────┤
│   ●  0:42 · 87 notes · scratchpad   ──────●───── ⤢            │  NEW timeline strip
├─────────────────────────────────────────────────────────────┤
│       (LargePianoView 73 keys — UNCHANGED v1)                │
└─────────────────────────────────────────────────────────────┘
```

Toolbar additions:

- **● red dot + 0:42 duration counter**: visible only when `scratchpad.hasContent`. Subtle badge.
- **↶ Undo**: disabled when `scratchpad.notes.isEmpty`; up to 20 levels.
- **⋯ More menu**: opens overflow with: Save take, Takes…, New session, Sa pitch picker (existing), instrument picker entry (existing).

The 16-note `RecordingStripView` from v1 is **removed from the default layout** — replaced by the timeline strip. (The strip-cap decision in v1 was orthogonal to v2; the v2 timeline strip subsumes its role.) Existing `RecordingStripView` source file is deleted.

> **Non-regression note**: the v1 `clearStrip()` callback path is reused for `New Session`, so `PlayTabViewModelTests` that exercise clearing continue to pass with a renamed method (`clearScratchpad()`) and a backwards-compatible alias.

#### 5.4.2 Expanded Timeline Sheet

Reached by tapping `⤢` on the strip. Full-screen sheet with `.presentationDetents([.large])` (per Apple iOS 26 guidance — no manual `.glassEffect`; system applies Liquid Glass via detents).

Top: 3 segmented tabs:
- **Staff** — horizontal-scroll grand staff with playhead. Viewport-culled (only ±2 screens of notes layout-computed).
- **Waterfall** — vertical bars per key, oldest at top, newest at bottom. Same playhead.
- **Notes** *(takes only)* — title / raga / teacher-notes form.

Bottom transport bar (always visible in this sheet):
- **▶ Play / ⏸ Pause** + **Restart ↺**
- **0:00 ───●─── 0:42** scrub bar (tap to seek)
- **Speed**: 0.5× / 0.75× / 1× / 1.25× / 1.5× picker
- **Hands**: Both / Treble / Bass segmented control

Visual sync (decision 4.5) reuses `MIDINoteHighlightCoordinator` — `TakePlaybackEngine` calls `noteOn/noteOff` directly (both are `nonisolated` on `MIDINoteHighlightCoordinator`).

#### 5.4.3 Takes list

Reached via ⋯ More → Takes…. `.presentationDetents([.medium, .large])` so iOS 26 applies Liquid Glass automatically.

```
┌──────────────────────────────────────────┐
│ Takes                            [Done]  │
├──────────────────────────────────────────┤
│ ● Take 5 · 29 Apr 19:42                  │
│   Sitar · 1:23 · 142 notes  · Yaman      │
│   ──────────────────────────────────     │
│ ● Bhairav riyaz                          │
│   Bansuri · 3:14 · 387 notes             │
└──────────────────────────────────────────┘
       swipe left → Delete (3-second undo toast)
       long-press → Rename sheet
       tap → Expanded Timeline Sheet for that take
```

Empty state: "Save a recording to see your takes here."

#### 5.4.4 Save sheet

```
┌──────────────────────────────────────────┐
│ Save take                       [Save]   │
├──────────────────────────────────────────┤
│ Title:  Take 5 · 29 Apr 19:42  [pencil]  │
│                                          │
│ ▸ Edit details                           │  collapsed by default
│                                          │
│   1:23 · 142 notes · Sitar · Sa = C      │
└──────────────────────────────────────────┘
```

`Edit details` expands to: raga picker, teacher-notes text field.

#### 5.4.5 Export sheet & quantize sub-sheet

```
┌──────────────────────────────────────────┐
│ Export "Take 5"               [Continue] │
├──────────────────────────────────────────┤
│ ☑ MusicXML (.musicxml)                   │
│ ☑ MXL (.mxl)                             │
│ ☑ MIDI (.mid)                            │
└──────────────────────────────────────────┘
```

If MusicXML or MXL is checked, tapping Continue shows the Quantize sheet:

```
┌──────────────────────────────────────────┐
│ Quantize for notation         [Export]   │
├──────────────────────────────────────────┤
│ BPM:        [─ 80 +]    [Tap tempo]      │
│ Time sig:   4/4 · 3/4 · 6/8 · 7/8 · 16/16│
│ Grid:       1/8 · 1/16                   │
└──────────────────────────────────────────┘
```

Default BPM = 80, time-sig = 4/4, grid = 1/16. The "Tap tempo" affordance lets the user tap 4 times to set BPM.

Tap Export → background job runs Quantizer + serializers, writes files to a temp dir, presents iOS share sheet with all selected files attached.

### 5.5 Playback engine

```swift
// SVAudio/Sources/SVAudio/Playback/TakePlaybackEngine.swift

public protocol TakePlaybackProviding: Sendable {
    func schedule(snapshot: TakeSnapshot, speed: Double, handFilter: HandFilter, saMidi: UInt8) async
    func play()
    func pause()
    func seek(to sec: TimeInterval)
    func stop()
}

@MainActor
public final class TakePlaybackEngine: TakePlaybackProviding {
    private let multiChannel: MultiChannelEngineProtocol
    private weak var highlightCoordinator: MIDINoteHighlightCoordinator?
    private let playbackSlot: UInt32 = 2

    public init(multiChannel: MultiChannelEngineProtocol,
                highlightCoordinator: MIDINoteHighlightCoordinator?) { … }
    …
}

public struct TakeSnapshot: Sendable {
    public let notes: [RecordedNote]
    public let sustain: [RecordedSustainEvent]
    public let instrumentProgram: UInt8
    public let saPitchMidi: UInt8
}

public enum HandFilter: Sendable { case both, trebleOnly, bassOnly }
```

`schedule(...)` precomputes a sorted event list (note-on, note-off, sustain-down, sustain-up) with their *playback* times = `recordedTime / speed`. `play()` arms a CADisplayLink-driven scheduler that fires events as their time arrives, calling `multiChannel.playNoteOnSlot(2, midi:, velocity:, channel:)` (new API, decision 5.6) and `highlightCoordinator?.noteOn(_:)`/`.noteOff(_:)`. `seek(to:)` re-arms with the post-seek tail. Hand filter rejects notes outside the chosen MIDI range (≥60 for treble, <60 for bass — matches v1 split).

> **Non-regression note**: `TakePlaybackEngine` is constructed only when the Expanded Timeline Sheet is opened. Live touch and live MIDI input continue to drive slot 0 unchanged.

### 5.6 New `MultiChannelEngineProtocol` methods (additive only)

```swift
public protocol MultiChannelEngineProtocol: AnyObject {
    // existing API — unchanged
    func playTouchNote(_ midi: UInt8, velocity: UInt8)
    func stopTouchNote(_ midi: UInt8)
    func stopAllTouchNotes()
    func loadProgram(into slot: UInt32, program: UInt8, isPercussion: Bool) async throws

    // NEW v2 additions. Default implementations are provided so MockPlayTabAudioEngine
    // and other test doubles do not have to spell out boilerplate they don't exercise.
    // (Tests that *do* exercise multi-slot playback override these in the mock.)
    func playNoteOnSlot(_ slot: UInt32, midi: UInt8, velocity: UInt8, channel: UInt8)
    func stopNoteOnSlot(_ slot: UInt32, midi: UInt8, channel: UInt8)
    func allNotesOffOnSlot(_ slot: UInt32)
    func sendControlChangeOnSlot(_ slot: UInt32, controller: UInt8, value: UInt8, channel: UInt8)
}

extension MultiChannelEngineProtocol {
    // Default no-ops so PlayTab v1 tests keep passing without touching mocks.
    public func playNoteOnSlot(_ slot: UInt32, midi: UInt8, velocity: UInt8, channel: UInt8) {}
    public func stopNoteOnSlot(_ slot: UInt32, midi: UInt8, channel: UInt8) {}
    public func allNotesOffOnSlot(_ slot: UInt32) {}
    public func sendControlChangeOnSlot(_ slot: UInt32, controller: UInt8, value: UInt8, channel: UInt8) {}
}
```

`ProductionMultiChannelEngine` implements the new methods by calling `samplers[Int(slot)].startNote/stopNote/sendController(...)` directly (same internal pattern as `playTouchNote`).

> **Non-regression note**: `samplers` array is `public nonisolated(unsafe)` today (per AUD-033). The new methods follow the same memory-ordering invariant: read on main actor, but the underlying AudioToolbox call is itself thread-safe per Apple docs.

### 5.7 Export pipeline

```
RecordedTake
   │  decode notesData / sustainData
   ▼
TakeSnapshot (notes + sustain + instrumentProgram + saPitchMidi)
   │
   ├──→ MIDISerializer.serializeType0(snapshot)
   │       PPQ = 1000, Tempo meta FF 51 03 0F 42 40 (60 BPM = 1ms/tick)
   │       Note-On + Note-Off + CC64 events with delta-time = ms
   │       Program-change at t=0 with snapshot.instrumentProgram
   │       returns Data → write .mid file
   │
   ├──→ Quantizer.quantize(snapshot, bpm:, grid:, timeSig:) → QuantizedScore
   │       (input from QuantizeSheet)
   │       │
   │       ├──→ MusicXMLSerializer.serialize(score) → String
   │       │       <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
   │       │       <score-partwise version="4.0">  ← NO xmlns
   │       │       Two-staff piano part. Treble = staff 1, bass = staff 2.
   │       │       Voice: 1 (treble) and 2 (bass). Sargam labels in <lyric><text>.
   │       │       returns String → write .musicxml file
   │       │
   │       └──→ MXLPackager.package(musicXML: String) → Data
   │               ZIPFoundation. mimetype entry FIRST, stored uncompressed,
   │               US-ASCII, no BOM, no extra field. Then META-INF/container.xml,
   │               then score.musicxml. write .mxl file.
   │
   ▼
[.mid, .musicxml, .mxl] in temp dir
   │
   ▼
UIActivityViewController via SwiftUI ShareLink — all selected files attached
```

### 5.8 Tab-change / New Session guard

`UnsavedScratchpadGuard.swift` exposes:

```swift
@MainActor
public struct UnsavedScratchpadGuard {
    public static func confirm(
        on viewModel: PlayTabViewModel,
        action: GuardAction,
        completion: @escaping (Outcome) -> Void
    )
}

public enum GuardAction { case tabChange, newSession }
public enum Outcome { case save, discard, cancel }
```

It raises a `.confirmationDialog` from PlayTab. **For tab-change only**: if user picks Cancel, the guard rolls back the tab selection by re-assigning `selectedTab` (and `AppRouter.currentTab`) to `.play`. The dialog blocks the actual scratchpad clear until the user picks Save or Discard.

Hooked at two sites:
1. `ContentView.onChange(of: selectedTab)` — intercepts Tab-bar/sidebar driven changes.
2. `AppRouter.switchTab(to:)` — intercepts programmatic switches (Skill: deep links, etc.).

Both call into the same guard. Cancel reverts. Save runs the materialize-take flow then completes the navigation. Discard clears the scratchpad and completes the navigation.

> **iOS 26 caveat**: `TabView.tabViewStyle(.sidebarAdaptable)` makes "tab change" be a sidebar tap on iPad — the change happens before `.onChange` fires. The rollback approach (re-assigning state) handles this; the sidebar momentarily shows the new tab selected, then visibly snaps back if the user cancels. This is acceptable UX-wise (the alternative — preventing the change in the first place — is not supported by SwiftUI's TabView API).

### 5.9 Error handling

| Failure | Behavior | Implementation |
|---|---|---|
| MIDI keyboard unplugged mid-record | Toast: "MIDI disconnected — keep playing on the iPad piano." Recording continues. | Subscribe to `MIDIInputManager.connectionStateStream` in `PlayTabViewModel`. |
| Sampler fails to load instrument | Inline banner on toolbar: "Couldn't load Sitar — using Acoustic Piano." Falls back to GM 0. | `loadProgram` already returns `Result`; surface error via `@Observable` flag. |
| Soft cap (1500) | Subtle banner: "≈3 minutes recorded — save when you're ready." Auto-dismiss after 6s. | Triggered by `ScratchpadState.isAtSoftCap`. |
| Hard cap (5000) | Modal: "Maximum length reached. Save this take to keep recording." Save / Discard. Capture paused; touch audio still works. | `ScratchpadState.appendNoteOn` becomes a no-op when `isAtHardCap`. |
| Quantize → empty score | Sheet: "Couldn't quantize at this BPM — try a slower tempo or use Tap tempo." MIDI/MXL still optionally exportable. | `Quantizer.quantize` returns `Result<QuantizedScore, QuantizeError>`. |
| Tab-change with unsaved scratchpad | Confirmation dialog (5.8). | `UnsavedScratchpadGuard`. |
| Storage full while writing take | Error sheet; take not materialized; scratchpad untouched. | `try modelContext.save()` failure path. |
| Background while recording | Capture pauses silently; touch sounds may also pause per AVAudioSession; resume on foreground. | Observe `scenePhase`. |
| Take decode fails (corrupted blob) | Take row shows "Couldn't load — Delete?" instead of exploding. | `cachedNotes` decode errors caught at access. |

**Failure-mode invariant**: the live audio path (touch → slot 0 → speakers) must never break because of any v2 path. All v2 capture / save / export logic are observers — they fail loudly to the user but cannot disturb live playing.

## 6. Performance budget

| Operation | Target | Notes |
|---|---|---|
| MIDI input → highlight visible | ≤ 16 ms | Same as v1 |
| MIDI input → scratchpad append | ≤ 1 ms | Wall-clock-bounded; never on audio thread |
| 5,000-note staff render (Expanded sheet, Staff tab) | ≤ 200 ms first paint | Viewport culling — only ±2 screens' worth laid out |
| Quantize (5,000 notes, 1/16 grid) | ≤ 500 ms on iPad A12 | Pure-Swift single pass |
| MusicXML export (5,000 notes) | ≤ 1 s | XML string build dominated; no I/O on main |
| MXL package (5,000 notes) | ≤ 200 ms | ZIPFoundation, mostly memcpy |
| MIDI export (5,000 notes) | ≤ 200 ms | Direct binary write |
| Playback start-to-first-sound | ≤ 100 ms | 50 ms pre-roll buffer |
| Take save (write to SwiftData) | ≤ 500 ms for 5,000 notes | JSON-encode + externalStorage spill |

All export work runs on a background `Task`. UI shows a progress sheet for any export taking longer than 300 ms.

## 7. Testing strategy

| Layer | Framework | Coverage | Key tests |
|---|---|---|---|
| `RecordedNote` codable | Swift Testing | 100% | round-trip JSON for representative arrays (1, 100, 5000 notes); equality & hash semantics |
| `ScratchpadState` | Swift Testing | ≥95% | append/undo/clear; soft cap; hard cap; duration math; open-note flush on clear; sustain ordering |
| `Quantizer` | Swift Testing | ≥95% | golden inputs (Sa-Re-Ga-Ma at 80 BPM 1/16 4/4) → expected QuantizedScore; tuplet detection; rubato fallback |
| `MusicXMLSerializer` | Swift Testing | ≥90% | golden XML fixtures (validated against MuseScore 4); empty score; single note; chord; staff splits at MIDI 60; Sargam in `<lyric><text>` |
| `MIDISerializer` | Swift Testing | ≥95% | round-trip via in-test parser; CC64 ordering; PPQ=1000 + tempo meta; program-change at t=0 |
| `MXLPackager` | Swift Testing | 100% | ZIP integrity; mimetype FIRST entry stored uncompressed; container.xml present; opens in MuseScore (manual smoke) |
| `TakePlaybackEngine` | Swift Testing + mock multiChannel | ≥85% | scheduler ordering; speed scaling; hand filter; seek/pause/restart |
| `PlayTabViewModel` extended | Swift Testing + existing mocks | ≥85% | state transitions (idle → recording → save → idle); cap behaviors; tab-change guard |
| `UnsavedScratchpadGuard` | Swift Testing | ≥90% | save/discard/cancel outcomes; rollback path |
| Save/Export sheets | Xcode previews + manual | n/a | smoke test on iPad simulator |
| Takes list | Swift Testing on view-model + previews | ≥80% | newest-first ordering; delete + 3s undo; rename round-trip |

**Golden fixtures**: commit hand-crafted reference MusicXML/MIDI files into `SVCoreTests/Resources/Play/` (Sa-Re-Ga-Ma, simple Yaman phrase, James Bond opening fragment). Quantizer/Serializer tests assert byte-identical output. Regenerating fixtures is an explicit, reviewed change.

**Non-regression**: every existing test in `SurVibeTests/Play/` either (a) keeps passing unchanged, or (b) gets updated in the same commit that produced the change with rationale in the commit body. Tests that exist purely to cover the v1 16-note strip are deleted alongside the strip itself; their concerns are absorbed by `ScratchpadState` tests.

## 8. Build sequence (preview — full plan goes into writing-plans)

Approximately 16 TDD tasks, ordered so each step is independently testable:

1. **SVCore types**: rewrite `RecordedNote` (drop `timestamp: Date`; add velocity, velocity16Bit, onTimeSec, offTimeSec, channel) and update v1 call sites in the same commit. Add `RecordedSustainEvent`, `MusicalDuration`, `QuantizedNote`, `QuantizedScore`. Move `SargamLabeler` + `SargamLabel` from app target to SVCore (update imports).
2. **`RecordedTake` `@Model` in `SurVibe/Models/`** with `.externalStorage` blobs and `@Transient` caches; codable round-trip tests.
3. **`ScratchpadState`** with append/undo/clear/cap behavior + tests.
4. **Wire scratchpad to `MIDIInputManager` + touch path**; remove the v1 16-note strip; add toolbar recording dot + Undo button.
5. **Soft/hard cap UI** (banner + modal).
6. **`Quantizer`** + golden tests.
7. **`MusicXMLSerializer`** + `MXLPackager` (in SVAudio) + golden tests.
8. **`MIDISerializer`** + round-trip tests.
9. **`MultiChannelEngineProtocol` extension** with default no-op impls; `ProductionMultiChannelEngine.playNoteOnSlot` etc.
10. **`TakePlaybackEngine`** + scheduler tests against mock multi-channel.
11. **Expanded Timeline Sheet — Staff tab** + visual sync.
12. **Expanded Timeline Sheet — Waterfall tab.**
13. **Takes list** (CRUD + delete-undo + rename).
14. **Save sheet** + take materialization.
15. **Export sheet + Quantize sub-sheet** + share-sheet integration.
16. **`UnsavedScratchpadGuard`** + ContentView/AppRouter wiring.

Each task is failing-test-first per the project's TDD pattern. Each task ends with a green build, no SwiftLint errors, and Xcode-previews verified on iPad.

## 9. Open issues / decisions deferred to plan stage

These four items are low-risk but I want them resolved during the plan rather than during code:

1. **`SargamLabeler` move**: confirm no current consumers in app target depend on internal-access detail that breaks when it becomes public-in-SVCore.
2. **Tab-bar rollback UX**: prototype on iPad simulator with `.sidebarAdaptable` to confirm the snap-back is acceptable; if it visibly flashes, fall back to a "Saved? (Save / Discard)" toast with no veto.
3. **Sustain pedal ordering at hard cap**: when capture pauses, an open sustain pedal needs to be virtually closed at flush time. Decide exact behavior.
4. **`ScratchpadState` reset semantics**: confirm whether `clear()` should reset `instrumentProgram` and `saPitchMidi` to current toolbar values or to defaults.

## 10. Glossary (project-specific terms used above)

- **Riyaz** — daily Indian-classical practice / sadhana.
- **Sa** — tonic note (analogous to "Do" but relative to the performer's pitch).
- **Sargam** — Indian notation system: Sa, Re, Ga, Ma, Pa, Dha, Ni.
- **Raga** — melodic framework with prescribed ascending/descending notes.
- **Tanpura** — drone instrument providing tonic reference.
- **Scratchpad** — in-memory ephemeral recording buffer (this spec).
- **Take** — a saved performance, persisted in SwiftData (this spec).
- **Slot** — one of 16 `AVAudioUnitSampler` instances in `ProductionMultiChannelEngine`. Slot 0 = touch input. Slots 1–15 available for songs / takes.

---

*End of spec. Plan goes into `docs/superpowers/plans/2026-04-29-play-tab-v2.md` after user review.*
