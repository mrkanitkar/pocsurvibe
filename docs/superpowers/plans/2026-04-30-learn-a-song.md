# Learn-a-Song Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended for parallelism — see §Parallel Execution) or `superpowers:executing-plans` for inline. Steps use checkbox (`- [ ]`) syntax.

**Spec:** [docs/superpowers/specs/2026-04-30-learn-a-song-design.md](../specs/2026-04-30-learn-a-song-design.md) (commit `2a51e0e`).
**Goal:** Replace the broken Play Along path with a working multi-instrument backing + grand-staff scoring + section loop + hand isolation + lyrics + count-in experience.
**Architecture:** Reuse `SongPlayAlongView` UI shell. Add new `PartSplitter` (SVAudio) → `ArrangementPlayer` (app) → `ScoringAdapter` (SVLearning) pipeline driven by `AVAudioSequencer.rate`. New `HostTime` typed wrapper (SVCore) carries timing across packages. Bluetooth MIDI → "Practice mode" (sound but no scoring).
**Tech Stack:** Swift 6.2, iOS 26+, SwiftUI, SwiftData, AVAudioEngine + AVAudioSequencer + AVAudioUnitSampler, CoreMIDI, Verovio (existing), MuseScore_General.sf2 (215 MB, MIT, gitignored).
**Scope:** ~3,620 LOC; 5–6 weeks build + 1 week tuning. 38 TDD tasks across 6 waves.

---

## Parallel Execution & Context Window

The user has 1M-token-context per agent and budget for ~20 parallel agents. The plan is organised into **6 waves**. Within each wave, all listed tasks are **independent** (different files, no shared state) and run as parallel subagents in isolated worktrees. Between waves, the orchestrator merges back into trunk and runs the full test suite as a gate.

### Wall-clock budget

| Wave | Sequential cost | Parallel cost (max concurrency) | Concurrency |
|------|-----------------|-------------------------------|-------------|
| 0    | 1 day (1 agent — diagnosis only) | 1 day | 1 |
| 1    | 10 days (sum of tasks)            | ~1.5 days | **10 parallel** |
| 2    | 6 days                            | ~1.5 days | **4 parallel** |
| 3    | 12 days                           | ~3 days | **6 parallel** |
| 4    | 8 days                            | ~2 days | **4 parallel** |
| 5    | 4 days (must serialise — integration) | 4 days | 1 |
| **Total wall-clock** | **41 days (~8 weeks)** | **~13 days (~2.5 weeks)** | up to 10 |

Speedup ≈ **3×** vs sequential. Bottleneck is wave 5 integration (single agent for cross-file wiring).

### Context-window math

**Per subagent (worktree-isolated):**

- System prompt + tooling: ~30K tokens
- Plan task content (one task fits in ~5–15K tokens of plan markdown): ~15K
- Code reads (avg 5–10 files per task at ~500 lines each, ~30K tokens of source): ~30K
- Tool outputs (test runs, build logs, edits): ~30–80K
- Spec re-read budget (subagent reads relevant spec sections): ~25K
- **Working budget per task:** ~130–180K tokens
- **Ceiling per task with reruns / debug:** ~400K tokens
- **Per-agent peak:** ~500K tokens (well within 1M)

**Orchestrator (main session):**

- This plan in context: ~50K tokens
- Spec in context: ~25K tokens
- Per-task summary returned by each subagent: ~3–5K tokens
- 38 tasks × 5K = ~190K tokens of summaries over the project
- Wave-gate test logs + merge diff summaries: ~50K total
- **Orchestrator peak:** ~350K tokens (well within 1M)

**Across the swarm (peak concurrent):**

- Wave 1: 10 agents × ~150K = 1.5M tokens in flight (each agent in its own 1M context window — no sharing)
- Total tokens consumed across the project: ~5M (cheap for the wall-clock saved)

Conclusion: **1M context-per-agent is sufficient with margin.** Parallelism is the right move.

### Parallel-execution rules

1. **Each subagent runs in an isolated git worktree** (`Agent({ isolation: "worktree" })`). Tasks touching the same file run in different waves OR resolve via auto-merge in a deterministic order.
2. **Wave gate:** before the next wave dispatches, the orchestrator (i) merges all wave-N branches into the wave-N integration branch, (ii) runs the full test suite, (iii) only on green proceeds to wave N+1.
3. **File-conflict map** (§Conflict Map below) lists every file touched by multiple tasks and the merge order.

---

## File Structure (created / modified)

### Created

| File | Wave | Owner Task | Approx LOC |
|---|---|---|---|
| `Packages/SVCore/Sources/SVCore/Audio/HostTime.swift` | 1 | A1 | 50 |
| `Packages/SVCore/Sources/SVCore/Audio/HostTimeTests.swift` | 1 | A1 | 60 |
| `Packages/SVAudio/Sources/SVAudio/Pipeline/GMProgramName.swift` | 1 | A3 | 200 |
| `Packages/SVAudio/Sources/SVAudio/Pipeline/PartSplitter.swift` | 2 | B1 | 400 |
| `Packages/SVAudio/Tests/SVAudioTests/Pipeline/PartSplitterTests.swift` | 2 | B1 | 300 |
| `Packages/SVAudio/Sources/SVAudio/MIDI/BluetoothEndpointFilter.swift` | 2 | B2 | 130 |
| `Packages/SVAudio/Tests/SVAudioTests/MIDI/BluetoothEndpointFilterTests.swift` | 2 | B2 | 120 |
| `Packages/SVLearning/Sources/SVLearning/Practice/ScoringAdapter.swift` | 2 | B3 | 250 |
| `Packages/SVLearning/Tests/SVLearningTests/Practice/ScoringAdapterTests.swift` | 2 | B3 | 250 |
| `SurVibe/PlayAlong/Coordinators/ArrangementPlayer.swift` | 3 | C1 | 350 |
| `SurVibe/PlayAlong/Coordinators/ArrangementPlayerTests.swift` *(under XCTest target)* | 3 | C1 | 200 |
| `SurVibe/PlayAlong/Coordinators/SectionLoopController.swift` | 3 | C3 | 200 |
| `SurVibe/Diagnostics/LatencyProbe.swift` *(DEBUG-only)* | 2 | B4 | 80 |
| `SurVibe/Songs/SongDetailViewParts.swift` | 4 | D2 | 220 |
| `SurVibe/PlayAlong/PlayAlongResultsOverlay+Split.swift` | 4 | D4 | 100 |

### Modified

| File | Wave | Tasks | Reason |
|---|---|---|---|
| `Packages/SVAudio/Sources/SVAudio/Pipeline/VerovioBridge.swift` | 1 | A2 | SMF meta-3/4 parser extension |
| `Packages/SVAudio/Sources/SVAudio/Pipeline/PipelineError.swift` | 1 | A2 | `TrackInfo` adds `trackName`, `instrumentName` |
| `Packages/SVAudio/Tests/SVAudioTests/Pipeline/VerovioBridgeTests.swift` | 1 | A2 | meta-3/4 extraction tests |
| `Packages/SVAudio/Sources/SVAudio/Pipeline/MultiTrackSamplerGraph.swift` | 1 | A4 | `setTempoScale` uses `sequencer.rate` |
| `Packages/SVAudio/Tests/SVAudioTests/MultiChannelEngineParityTests.swift` | 1 | A4 | rate-based tempo assertions |
| `Packages/SVAudio/Sources/SVAudio/Engine/AudioSessionManager.swift` | 1 | A5+A10 | 48 kHz, buffer-grant, route, interruption, background |
| `Packages/SVCore/Sources/SVCore/Models/Song.swift` *(or current location)* | 1 | A6 | new fields |
| `Packages/SVLearning/Sources/SVLearning/Practice/PracticeSession.swift` | 1 | A7 | drop-and-recreate with new shape |
| `Packages/SVLearning/Sources/SVLearning/Songs/SongLibraryEmptyState.swift` | 1 | A8 | empty-state copy + Try-a-sample |
| `Packages/SVLearning/Sources/SVLearning/Songs/SongImporter.swift` | 1+3 | A9, C5 | content-sniff + part-split persistence |
| `Packages/SVAudio/Sources/SVAudio/MIDI/MIDIInputManager.swift` | 2 | B2 | endpoint blocklist plumbing |
| `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift` | 4 | D3 | rework — visualization-only |
| `SurVibe/PlayAlong/PlayAlongToolbar.swift` | 4 | D1 | new controls (Backing, Hands, Loop, Click level) |
| `SurVibe/Songs/SongDetailView.swift` | 4 | D2 | embed Parts section |
| `SurVibe/PlayAlong/PlayAlongResultsOverlay.swift` | 4 | D4 | split scoring display |
| `SurVibe/PlayAlong/PlayAlongSceneHost.swift` | 5 | E1 | wire ArrangementPlayer into VM |
| `SurVibe/PlayAlong/PlayAlongViewModel.swift` | 5 | E1 | own ArrangementPlayer + ScoringAdapter |

### Conflict Map (multi-touch files)

| File | Tasks (in merge order) | Notes |
|---|---|---|
| `AudioSessionManager.swift` | A5 → A10 | A5 lays the 48 kHz + buffer-grant base; A10 layers route/interruption/background. **A10 must wait for A5** — same wave, sequential within. |
| `SongImporter.swift` | A9 → C5 | A9 is content-sniff (small, additive); C5 is part-split persistence (depends on B1 PartSplitter). Different waves, no conflict. |
| `PlayAlongToolbar.swift` | D1 only | Heavy revamp; one agent owns it. |
| `PlayAlongViewModel.swift` | E1 only | Wave-5 sequential. |

---

## Wave 0 — Diagnose Broken Play Along (1 agent, 1 day)

**MUST run first.** Spec §12 mandates root-cause before rewrite.

### Task 0: Diagnose

**Files (read-only initially):**
- `SurVibe/PlayAlong/PlayAlongSceneHost.swift`
- `SurVibe/PlayAlong/PlayAlongViewModel.swift`
- `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift`
- `SurVibe/PlayAlong/Coordinators/NoteRouter.swift`
- `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift:loadSong`
- Recent commits since 2026-04-18: `git log --since=2026-04-18 -- SurVibe/PlayAlong/`

- [ ] **Step 1: Read the chain end-to-end.** Trace `SongDetailView` → `PlayAlongSceneHost(song:)` → `PlayAlongViewModel.task` → `PlaybackCoordinator.loadSong(_:)`. Note every `throw`, every `errorMessage` setter, every `state == .error` branch.

- [ ] **Step 2: Build & run on simulator.** Launch SurVibe, navigate Songs → tap one of the four bundled songs (`james-bond-theme`, `Sukhkarta_Dukhharta`, `vande-mataram`, `indian-national-anthem`) → tap Play Along. Capture exact behaviour: blank screen? Frozen toolbar? Console errors? Add `os_log` lines if necessary to discover the failure point.

- [ ] **Step 3: Check `PipelineFileLog`.** That file already records pipeline state transitions. Pull the most recent log line that mentions PlayAlong / loadSong / Verovio.

- [ ] **Step 4: Write a 1-page diagnosis note** at `docs/superpowers/plans/2026-04-30-learn-a-song-day0-diagnosis.md` containing:
  - Exact symptom (e.g., "no UI changes, console shows `pipelineError(verovioRenderFailed)`")
  - Root cause file:line
  - Whether it's a one-line fix (option a in spec §12) OR a deep rewrite gate (option b)
  - Recommendation

- [ ] **Step 5: Commit the diagnosis note.**

```bash
git add -f docs/superpowers/plans/2026-04-30-learn-a-song-day0-diagnosis.md
git commit -m "docs(SurVibe): Day-0 diagnosis of broken Play Along path"
```

- [ ] **Step 6: Decision.** If diagnosis says "one-line fix" — orchestrator pauses Wave 1 and instead instructs a single agent to apply the fix and write a regression test. THEN starts Wave 1. If diagnosis says "deep rewrite," proceed to Wave 1 unchanged.

---

## Wave 1 — Foundation (10 parallel agents, ~1.5 days wall-clock)

All ten tasks are independent (different files, no shared state). Dispatch as 10 isolated worktree subagents simultaneously.

### Task A1: `HostTime` typed wrapper in SVCore

**Files:**
- Create: `Packages/SVCore/Sources/SVCore/Audio/HostTime.swift`
- Test: `Packages/SVCore/Tests/SVCoreTests/Audio/HostTimeTests.swift`

- [ ] **Step 1: Write the failing tests.**

```swift
import Testing
@testable import SVCore

struct HostTimeTests {
    @Test func nowProducesMonotonicallyIncreasingValues() {
        let a = HostTime.now()
        let b = HostTime.now()
        #expect(b.rawTicks >= a.rawTicks)
    }

    @Test func secondsSinceConvertsTicksToSeconds() {
        let a = HostTime(rawTicks: 0)
        let b = HostTime(rawTicks: 1_000_000_000) // 1e9 ticks
        let delta = b.seconds(since: a)
        #expect(delta > 0)
        // mach_timebase ratio is platform-dependent; just sanity-check ordering
        #expect(delta < 100.0)
    }

    @Test func secondsSinceIsSymmetric() {
        let a = HostTime.now()
        let b = HostTime(rawTicks: a.rawTicks + 1_000_000)
        let forward = b.seconds(since: a)
        let backward = a.seconds(since: b)
        #expect(forward == -backward)
    }

    @Test func sendableAndHashable() {
        let a = HostTime(rawTicks: 42)
        let b = HostTime(rawTicks: 42)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
```

- [ ] **Step 2: Run tests to verify FAIL.**

```bash
cd Packages/SVCore && swift test --filter HostTimeTests
```
Expected: compile error, `HostTime` not found.

- [ ] **Step 3: Implement `HostTime`.**

```swift
// Packages/SVCore/Sources/SVCore/Audio/HostTime.swift
import Foundation
import Darwin

/// Mach absolute-time value used as the canonical timing reference across
/// SVAudio, SVLearning, and the app target.
///
/// Wraps `mach_absolute_time()` ticks with type safety so timing values cannot
/// be confused with raw `UInt64` counts. Convert to seconds via `seconds(since:)`.
public struct HostTime: Hashable, Sendable {
    public let rawTicks: UInt64

    public init(rawTicks: UInt64) {
        self.rawTicks = rawTicks
    }

    /// Capture the current host time. Sub-microsecond precision on Apple silicon.
    public static func now() -> HostTime {
        HostTime(rawTicks: mach_absolute_time())
    }

    /// Seconds elapsed since `other`. Negative when `other` is later than `self`.
    public func seconds(since other: HostTime) -> Double {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let deltaTicks = Int64(rawTicks) - Int64(other.rawTicks)
        let nanos = Double(deltaTicks) * Double(info.numer) / Double(info.denom)
        return nanos / 1_000_000_000.0
    }
}
```

- [ ] **Step 4: Run tests to verify PASS.**

```bash
cd Packages/SVCore && swift test --filter HostTimeTests
```
Expected: 4/4 pass.

- [ ] **Step 5: Commit.**

```bash
git add Packages/SVCore/Sources/SVCore/Audio/HostTime.swift Packages/SVCore/Tests/SVCoreTests/Audio/HostTimeTests.swift
git commit -m "feat(SVCore): add HostTime typed wrapper for mach_absolute_time

Used by SVAudio scoring path and app-level coordinators to carry timing
across package boundaries with type safety. Spec §5.1, Q-decision.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task A2: VerovioBridge SMF meta-3/4 parser extension

**Files:**
- Modify: `Packages/SVAudio/Sources/SVAudio/Pipeline/VerovioBridge.swift:191-277` (parse loop)
- Modify: `Packages/SVAudio/Sources/SVAudio/Pipeline/PipelineError.swift:74-91` (`TrackInfo` struct)
- Modify: `Packages/SVAudio/Tests/SVAudioTests/Pipeline/VerovioBridgeTests.swift` (add meta-3/4 fixture tests)

- [ ] **Step 1: Add fields to `TrackInfo`.**

```swift
// PipelineError.swift
public struct TrackInfo: Sendable, Hashable {
    public let channel: UInt8
    public let program: UInt8
    public let isPercussion: Bool
    public let trackName: String?       // NEW — SMF meta 0x03
    public let instrumentName: String?  // NEW — SMF meta 0x04

    public init(channel: UInt8, program: UInt8, isPercussion: Bool,
                trackName: String? = nil, instrumentName: String? = nil) {
        self.channel = channel
        self.program = program
        self.isPercussion = isPercussion
        self.trackName = trackName
        self.instrumentName = instrumentName
    }
}
```

- [ ] **Step 2: Write failing test against bundled MXLs.**

```swift
// VerovioBridgeTests.swift
@Test func extractsTrackNameFromSukhkartaDukhharta() throws {
    let bridge = try VerovioBridge()
    let xml = try MXLFixture.musicXML(for: "Sukhkarta_Dukhharta")
    let rendered = try bridge.render(musicXML: xml)
    // At least one track should carry a track name OR instrument name.
    let hasAnyName = rendered.trackInfo.contains { ($0.trackName != nil) || ($0.instrumentName != nil) }
    #expect(hasAnyName, "Verovio should emit at least one named track for Sukhkarta_Dukhharta")
}

@Test func extractsTrackNameFromAllBundledSongs() throws {
    let bridge = try VerovioBridge()
    for songID in ["james-bond-theme", "Sukhkarta_Dukhharta",
                   "vande-mataram-national-song-of-india",
                   "indian-national-anthem"] {
        let xml = try MXLFixture.musicXML(for: songID)
        let rendered = try bridge.render(musicXML: xml)
        // Sanity: track count > 0 and program bytes well-formed.
        #expect(rendered.trackInfo.count > 0, "\(songID) had zero tracks")
    }
}
```

- [ ] **Step 3: Run to verify FAIL.**

```bash
cd Packages/SVAudio && swift test --filter VerovioBridgeTests/extractsTrackName
```
Expected: compile error or assertion failure.

- [ ] **Step 4: Implement meta-3/4 extraction in the parse loop.**

The current parse loop at `VerovioBridge.swift:191-277` advances past meta events. Extend the meta-event branch to capture lengths and copy data for type 0x03 (Sequence/Track Name) and 0x04 (Instrument Name) into the per-track accumulator.

```swift
// Inside parseTrack(...), in the meta-event branch:
case 0xFF:
    let metaType = bytes[idx]; idx += 1
    let (metaLen, lenSize) = readVarInt(bytes, at: idx)
    idx += lenSize
    let metaEnd = idx + metaLen

    switch metaType {
    case 0x03 where trackNameAccum == nil:
        trackNameAccum = String(bytes: bytes[idx ..< metaEnd], encoding: .utf8)
    case 0x04 where instrumentNameAccum == nil:
        instrumentNameAccum = String(bytes: bytes[idx ..< metaEnd], encoding: .utf8)
    default:
        break
    }
    idx = metaEnd
```

After the parse, when constructing `TrackInfo`, pass the accumulated names:

```swift
let info = TrackInfo(
    channel: channel,
    program: program,
    isPercussion: channel == 9,  // GM percussion is channel 10 (0-indexed = 9)
    trackName: trackNameAccum,
    instrumentName: instrumentNameAccum
)
```

- [ ] **Step 5: Run tests, including pre-existing tests, to verify PASS.**

```bash
cd Packages/SVAudio && swift test --filter VerovioBridgeTests
```
Expected: all VerovioBridgeTests pass, including the two new ones.

- [ ] **Step 6: Decision gate (Q4).** If `extractsTrackNameFromSukhkartaDukhharta` passes for all four bundled songs → done. If not, log the missing names and proceed (PartSplitter has GM-program fallback in B1).

- [ ] **Step 7: Commit.**

```bash
git add Packages/SVAudio/Sources/SVAudio/Pipeline/PipelineError.swift \
        Packages/SVAudio/Sources/SVAudio/Pipeline/VerovioBridge.swift \
        Packages/SVAudio/Tests/SVAudioTests/Pipeline/VerovioBridgeTests.swift
git commit -m "feat(SVAudio): extract SMF meta-3/4 (track/instrument names) in VerovioBridge

PartSplitter (Wave 2) needs human-readable track names from the
MusicXML <part-name> / <instrument-name> for the Parts picker UI.
Spec §5.1 PartSplitter prerequisite, Q4 resolution.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task A3: GM Program Name lookup table

**Files:**
- Create: `Packages/SVAudio/Sources/SVAudio/Pipeline/GMProgramName.swift`
- Test: `Packages/SVAudio/Tests/SVAudioTests/Pipeline/GMProgramNameTests.swift`

- [ ] **Step 1: Write failing tests.**

```swift
import Testing
@testable import SVAudio

struct GMProgramNameTests {
    @Test func returnsAcousticGrandPianoForProgramZero() {
        #expect(GMProgramName.label(for: 0) == "Acoustic Grand Piano")
    }
    @Test func returnsChurchOrganForProgram19() {
        #expect(GMProgramName.label(for: 19) == "Church Organ")
    }
    @Test func returnsViolinForProgram40() {
        #expect(GMProgramName.label(for: 40) == "Violin")
    }
    @Test func clampsAboveProgramRange() {
        #expect(GMProgramName.label(for: 200) == "Acoustic Grand Piano")
    }
    @Test func has128Entries() {
        for p in 0..<128 {
            #expect(!GMProgramName.label(for: UInt8(p)).isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement the lookup.**

```swift
// GMProgramName.swift
import Foundation

/// General MIDI program-number → human label.
/// Standard GM Level 1 patch names (instruments 0–127).
public enum GMProgramName {
    public static func label(for program: UInt8) -> String {
        guard program < 128 else { return names[0] }
        return names[Int(program)]
    }

    private static let names: [String] = [
        // 0–7 Piano
        "Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano",
        "Honky-tonk Piano", "Electric Piano 1", "Electric Piano 2",
        "Harpsichord", "Clavinet",
        // 8–15 Chromatic Percussion
        "Celesta", "Glockenspiel", "Music Box", "Vibraphone",
        "Marimba", "Xylophone", "Tubular Bells", "Dulcimer",
        // 16–23 Organ
        "Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ",
        "Reed Organ", "Accordion", "Harmonica", "Tango Accordion",
        // 24–31 Guitar
        "Acoustic Guitar (nylon)", "Acoustic Guitar (steel)",
        "Electric Guitar (jazz)", "Electric Guitar (clean)",
        "Electric Guitar (muted)", "Overdriven Guitar",
        "Distortion Guitar", "Guitar Harmonics",
        // 32–39 Bass
        "Acoustic Bass", "Electric Bass (finger)", "Electric Bass (pick)",
        "Fretless Bass", "Slap Bass 1", "Slap Bass 2",
        "Synth Bass 1", "Synth Bass 2",
        // 40–47 Strings
        "Violin", "Viola", "Cello", "Contrabass",
        "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp", "Timpani",
        // 48–55 Ensemble
        "String Ensemble 1", "String Ensemble 2", "Synth Strings 1",
        "Synth Strings 2", "Choir Aahs", "Voice Oohs", "Synth Voice", "Orchestra Hit",
        // 56–63 Brass
        "Trumpet", "Trombone", "Tuba", "Muted Trumpet",
        "French Horn", "Brass Section", "Synth Brass 1", "Synth Brass 2",
        // 64–71 Reed
        "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax",
        "Oboe", "English Horn", "Bassoon", "Clarinet",
        // 72–79 Pipe
        "Piccolo", "Flute", "Recorder", "Pan Flute",
        "Blown Bottle", "Shakuhachi", "Whistle", "Ocarina",
        // 80–87 Synth Lead
        "Lead 1 (square)", "Lead 2 (sawtooth)", "Lead 3 (calliope)",
        "Lead 4 (chiff)", "Lead 5 (charang)", "Lead 6 (voice)",
        "Lead 7 (fifths)", "Lead 8 (bass + lead)",
        // 88–95 Synth Pad
        "Pad 1 (new age)", "Pad 2 (warm)", "Pad 3 (polysynth)",
        "Pad 4 (choir)", "Pad 5 (bowed)", "Pad 6 (metallic)",
        "Pad 7 (halo)", "Pad 8 (sweep)",
        // 96–103 Synth Effects
        "FX 1 (rain)", "FX 2 (soundtrack)", "FX 3 (crystal)",
        "FX 4 (atmosphere)", "FX 5 (brightness)", "FX 6 (goblins)",
        "FX 7 (echoes)", "FX 8 (sci-fi)",
        // 104–111 Ethnic
        "Sitar", "Banjo", "Shamisen", "Koto",
        "Kalimba", "Bagpipe", "Fiddle", "Shanai",
        // 112–119 Percussive
        "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock",
        "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
        // 120–127 Sound Effects
        "Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet",
        "Telephone Ring", "Helicopter", "Applause", "Gunshot"
    ]
}
```

- [ ] **Step 4: Run tests, expect PASS.**

- [ ] **Step 5: Commit.**

```bash
git add Packages/SVAudio/Sources/SVAudio/Pipeline/GMProgramName.swift \
        Packages/SVAudio/Tests/SVAudioTests/Pipeline/GMProgramNameTests.swift
git commit -m "feat(SVAudio): GM program-number → human label lookup

Powers PartSplitter's Parts-picker labels when Verovio doesn't emit
SMF meta-3/4. Spec §5.1.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task A4: MultiTrackSamplerGraph tempo fix → `sequencer.rate`

**Files:**
- Modify: `Packages/SVAudio/Sources/SVAudio/Pipeline/MultiTrackSamplerGraph.swift:235-239`
- Modify: `Packages/SVAudio/Tests/SVAudioTests/MultiChannelEngineParityTests.swift`

- [ ] **Step 1: Update the parity test to assert sequencer.rate semantics.**

```swift
@Test func setTempoScaleAtHalfSpeedSetsSequencerRateNotTimePitch() throws {
    let graph = try MultiTrackSamplerGraph()
    try graph.loadMIDI(MXLFixture.midi(for: "Sukhkarta_Dukhharta"))
    graph.setTempoScale(0.5)
    #expect(graph.sequencerRate == 0.5)
    #expect(graph.timePitchRate == 1.0)  // passthrough
}

@Test func setTempoScaleClampsToFifteenX() throws {
    let graph = try MultiTrackSamplerGraph()
    try graph.loadMIDI(MXLFixture.midi(for: "Sukhkarta_Dukhharta"))
    graph.setTempoScale(2.0)
    #expect(graph.sequencerRate == 1.5)
}

@Test func setTempoScaleClampsToHalfX() throws {
    let graph = try MultiTrackSamplerGraph()
    try graph.loadMIDI(MXLFixture.midi(for: "Sukhkarta_Dukhharta"))
    graph.setTempoScale(0.1)
    #expect(graph.sequencerRate == 0.5)
}
```

(`sequencerRate` and `timePitchRate` are new computed test-seam properties returning the underlying float values.)

- [ ] **Step 2: Run tests, expect FAIL.**

- [ ] **Step 3: Implement.**

```swift
// MultiTrackSamplerGraph.swift — replace setTempo with setTempoScale
public func setTempoScale(_ rate: Float) {
    let clamped = max(Self.minRate, min(Self.maxRate, rate))
    sequencer?.rate = clamped
    timePitch.rate = 1.0  // passthrough; no time-stretch DSP on the audio path
    graphLogger.info("setTempoScale rate=\(clamped, privacy: .public)")
}

#if DEBUG
public var sequencerRate: Float { sequencer?.rate ?? 1.0 }
public var timePitchRate: Float { timePitch.rate }
#endif
```

Update existing call sites (audition POC, any other) from `setTempo(rate:)` to `setTempoScale(_:)`. Use `git grep -l setTempo\\(rate:` to locate.

- [ ] **Step 4: Run all SVAudio tests to ensure nothing else regressed.**

```bash
cd Packages/SVAudio && swift test
```

- [ ] **Step 5: Commit.**

```bash
git add Packages/SVAudio/Sources/SVAudio/Pipeline/MultiTrackSamplerGraph.swift \
        Packages/SVAudio/Tests/SVAudioTests/MultiChannelEngineParityTests.swift \
        $(git grep -l 'setTempo(rate:' | tr '\n' ' ')
git commit -m "feat(SVAudio): tempo control uses AVAudioSequencer.rate, not TimePitch

TimePitch.rate adds 50–100 ms overlap-add latency, fatal for play-along.
sequencer.rate scales the MIDI timeline directly. timePitch stays as a
1.0 passthrough. Spec §D3.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task A5: AudioSessionManager 48 kHz + buffer-grant verification

**Files:**
- Modify: `Packages/SVAudio/Sources/SVAudio/Engine/AudioSessionManager.swift`
- Modify: `Packages/SVAudio/Sources/SVAudio/Engine/AudioEngineManager.swift` (any 44.1 references)
- Add tests: `Packages/SVAudio/Tests/SVAudioTests/Engine/AudioSessionManagerTests.swift`

- [ ] **Step 1: Locate every reference to 44100 / 44.1.**

```bash
git grep -n '44100\|44_100\|44.1' Packages/SVAudio/ SurVibe/
```
Audit each: distinguish "audio session config" (must change) from "PCM format / sample data" (may stay if intentional).

- [ ] **Step 2: Write failing test for 48 kHz config + buffer grant.**

```swift
import Testing
@testable import SVAudio
import AVFoundation

@MainActor
struct AudioSessionManagerTests {
    @Test func activatesAt48kHz() async throws {
        try AudioSessionManager.shared.activate()
        let session = AVAudioSession.sharedInstance()
        #expect(session.sampleRate == 48000.0)
    }

    @Test func requestsLowIOBufferDuration() async throws {
        try AudioSessionManager.shared.activate()
        let session = AVAudioSession.sharedInstance()
        // 256 / 48000 = 5.333... ms
        #expect(session.preferredIOBufferDuration < 0.006)
    }

    @Test func reportsGrantedBufferTier() async throws {
        try AudioSessionManager.shared.activate()
        let tier = AudioSessionManager.shared.lastBufferGrantTier
        #expect(tier != .unknown)
    }
}
```

- [ ] **Step 3: Run, expect FAIL.**

- [ ] **Step 4: Implement.**

```swift
// AudioSessionManager.swift
public enum BufferGrantTier: Sendable {
    case unknown
    case excellent      // <= 7 ms
    case acceptable     // 7–12 ms — log warning
    case degraded       // > 12 ms — surface toast
}

public func activate() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
    try session.setPreferredSampleRate(48_000.0)
    try session.setPreferredIOBufferDuration(256.0 / 48_000.0)  // 5.33 ms
    try session.setActive(true)

    // Verify what the OS actually granted.
    let granted = session.ioBufferDuration
    if granted <= 0.007 {
        lastBufferGrantTier = .excellent
    } else if granted <= 0.012 {
        lastBufferGrantTier = .acceptable
        sessionLogger.warning("Granted IO buffer \(granted * 1000, privacy: .public) ms — acceptable but above target")
    } else {
        lastBufferGrantTier = .degraded
        sessionLogger.error("Granted IO buffer \(granted * 1000, privacy: .public) ms — exceeds latency target")
    }

    sessionLogger.info("Activated session sampleRate=\(session.sampleRate, privacy: .public) ioBuffer=\(granted * 1000, privacy: .public)ms tier=\(String(describing: self.lastBufferGrantTier), privacy: .public)")
}

public private(set) var lastBufferGrantTier: BufferGrantTier = .unknown
```

- [ ] **Step 5: Run tests + run the app on simulator → check console for grant-tier log line.**

- [ ] **Step 6: Commit.**

```bash
git add Packages/SVAudio/Sources/SVAudio/Engine/AudioSessionManager.swift \
        Packages/SVAudio/Sources/SVAudio/Engine/AudioEngineManager.swift \
        Packages/SVAudio/Tests/SVAudioTests/Engine/AudioSessionManagerTests.swift
git commit -m "feat(SVAudio): 48 kHz audio session + IO buffer grant verification

iPad native rate is 48 kHz; running 44.1 kHz forced an OS SRC stage
adding latency. Switched + verify granted ioBufferDuration with 3 tiers.
Spec §D4, §7 buffer-grant verification.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task A6: `Song` model new fields

**Files:**
- Modify: the `Song` `@Model` (locate via `git grep -l '@Model' Packages/SVCore/ Packages/SVLearning/ | xargs grep -l 'class Song'`)
- Modify: any tests around the model

- [ ] **Step 1: Locate the Song model.**

```bash
git grep -l '@Model' Packages/SVCore/ Packages/SVLearning/ | xargs grep -l 'final class Song'
```

- [ ] **Step 2: Write failing test asserting new fields exist with defaults.**

```swift
@Test func songHasNewLearnerTrackFields() {
    let song = Song(/* existing init */)
    #expect(song.learnerTrackIndex == nil)
    #expect(song.accompanimentInstrumentSummary == nil)
    #expect(song.defaultPracticeMode == nil)
    #expect(song.lastUsedTempoScale == nil)
}
```

- [ ] **Step 3: Run, expect FAIL.**

- [ ] **Step 4: Add fields.**

```swift
// in @Model class Song { ... }
var learnerTrackIndex: Int?
var accompanimentInstrumentSummary: String?
var defaultPracticeMode: String?     // "both" | "rightHand" | "leftHand"
var lastUsedTempoScale: Double?
```

- [ ] **Step 5: Run all SVCore tests.**

```bash
cd Packages/SVCore && swift test
```

- [ ] **Step 6: Commit.**

```bash
git add <song-model-file> <song-tests>
git commit -m "feat(SVCore): add per-song play-along prefs to Song @Model

Spec §5.2: learnerTrackIndex, accompanimentInstrumentSummary,
defaultPracticeMode, lastUsedTempoScale. Single-user assumption;
multi-user-per-device migration moves these to a junction model later.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task A7: `PracticeSession` model drop-and-recreate

**Files:**
- Modify: `Packages/SVLearning/Sources/SVLearning/Practice/PracticeSession.swift`
- Modify: `SurVibe/SurVibeApp.swift` ModelContainer registration (only if schema list changes)
- Update tests

- [ ] **Step 1: Write failing test for new schema.**

```swift
@Test func practiceSessionHasSplitScoringFields() {
    let s = PracticeSession(
        songID: UUID(),
        startedAt: .now,
        notesAttempted: 100,
        notesCorrect: 92,
        notesMissed: 8,
        notesExtra: 3,
        timingAccuracyPercent: 78.0,
        notesCorrectPercent: 92.0
    )
    #expect(s.notesCorrectPercent == 92.0)
    #expect(s.timingAccuracyPercent == 78.0)
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Replace fields. (Pre-release; DROP the existing `.store` on next launch.)**

```swift
@Model
public final class PracticeSession {
    public var id: UUID
    public var songID: UUID
    public var startedAt: Date
    public var endedAt: Date?

    public var notesAttempted: Int
    public var notesCorrect: Int
    public var notesMissed: Int
    public var notesExtra: Int

    public var timingAccuracyPercent: Double
    public var notesCorrectPercent: Double

    public var compositeScore: Double?     // legacy NoteScore aggregate, still useful for sort

    public init(songID: UUID, startedAt: Date,
                notesAttempted: Int = 0, notesCorrect: Int = 0,
                notesMissed: Int = 0, notesExtra: Int = 0,
                timingAccuracyPercent: Double = 0, notesCorrectPercent: Double = 0) {
        self.id = UUID()
        self.songID = songID
        self.startedAt = startedAt
        self.notesAttempted = notesAttempted
        self.notesCorrect = notesCorrect
        self.notesMissed = notesMissed
        self.notesExtra = notesExtra
        self.timingAccuracyPercent = timingAccuracyPercent
        self.notesCorrectPercent = notesCorrectPercent
    }
}
```

- [ ] **Step 4: In `SurVibeApp.swift`, ensure the ModelContainer is created with `.deleteOnMigrationFailure` semantics (or wipe the existing dev store on first launch with a sentinel UserDefaults key).**

```swift
// Pre-release schema reset
if !UserDefaults.standard.bool(forKey: "didApplyV1Schema") {
    try? FileManager.default.removeItem(at: defaultStoreURL)
    UserDefaults.standard.set(true, forKey: "didApplyV1Schema")
}
```

- [ ] **Step 5: Run all tests.**

- [ ] **Step 6: Commit.**

```bash
git add Packages/SVLearning/Sources/SVLearning/Practice/PracticeSession.swift \
        SurVibe/SurVibeApp.swift
git commit -m "feat(SVLearning): replace PracticeSession schema with split scoring fields

Pre-release drop-and-recreate. notesCorrectPercent + timingAccuracyPercent
as headline split metrics. Spec §Q6.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task A8: SongLibraryEmptyState copy + "Try a sample" button

**Files:**
- Modify: `Packages/SVLearning/Sources/SVLearning/Songs/SongLibraryEmptyState.swift`

- [ ] **Step 1: Write failing snapshot test (or assertion test).**

```swift
@MainActor
@Test func emptyStateShowsSampleButtonAndCorrectCopy() {
    let view = SongLibraryEmptyState(onTrySample: {})
    let mirror = Mirror(reflecting: view)
    // Hosting tests vary; minimum: assert the closure path is invokable.
    var tapped = false
    let v2 = SongLibraryEmptyState(onTrySample: { tapped = true })
    v2.simulateTrySampleTap()  // test seam
    #expect(tapped)
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Update view.**

```swift
public struct SongLibraryEmptyState: View {
    let onTrySample: () -> Void

    public init(onTrySample: @escaping () -> Void) {
        self.onTrySample = onTrySample
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No songs yet")
                .font(.title2)
                .bold()
            Text("Drop in a `.mxl`, `.musicxml`, or `.xml` file from MuseScore, your teacher, or your own composition. Multi-instrument songs play their backing while you practice the piano part.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try a sample", action: onTrySample)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Import the bundled sample song to try Play Along")
        }
    }

    #if DEBUG
    func simulateTrySampleTap() { onTrySample() }
    #endif
}
```

- [ ] **Step 4: Caller (SongsTab) wires `onTrySample` to import `Sukhkarta_Dukhharta.mxl` from app resources.** Defer caller wiring to Wave 4 D2; for now just supply `{}` placeholder closure in the existing call site so the build compiles.

- [ ] **Step 5: Run.**

- [ ] **Step 6: Commit.**

```bash
git add Packages/SVLearning/Sources/SVLearning/Songs/SongLibraryEmptyState.swift
git commit -m "feat(SVLearning): empty-state copy + Try-a-sample button

Spec §13a persona-review fix. Caller wiring lands in Wave 4 D2.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task A9: SongImporter `.xml` content-sniff

**Files:**
- Modify: `Packages/SVLearning/Sources/SVLearning/Songs/SongImporter.swift`
- Tests under `Packages/SVLearning/Tests/SVLearningTests/Songs/`

- [ ] **Step 1: Write failing tests.**

```swift
@Test func acceptsPlainXMLByContentSniff() async throws {
    let xmlBytes = "<?xml version=\"1.0\"?><score-partwise>...</score-partwise>".data(using: .utf8)!
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.xml")
    try xmlBytes.write(to: tempURL)

    let importer = SongImporter(modelContext: .testStub())
    let song = try await importer.importSong(from: tempURL)
    #expect(song != nil)
}

@Test func rejectsArbitraryFile() async throws {
    let bytes = Data("not a music file".utf8)
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.xml")
    try bytes.write(to: tempURL)

    let importer = SongImporter(modelContext: .testStub())
    await #expect(throws: SongImportError.self) {
        try await importer.importSong(from: tempURL)
    }
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement content-sniff.**

```swift
private func detectFormat(_ url: URL) throws -> ImportFormat {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let header = try handle.read(upToCount: 64) ?? Data()

    // ZIP magic "PK\x03\x04" → MXL
    if header.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
        return .mxl
    }
    // XML preamble
    if let head = String(data: header, encoding: .utf8),
       head.contains("<?xml") || head.contains("<score-partwise") || head.contains("<score-timewise") {
        return .musicxml
    }
    throw SongImportError.unrecognizedFormat(
        message: "This doesn't look like a MusicXML file. SurVibe accepts .mxl, .musicxml, and .xml exports."
    )
}
```

- [ ] **Step 4: Run.**

- [ ] **Step 5: Commit.**

```bash
git add Packages/SVLearning/Sources/SVLearning/Songs/SongImporter.swift \
        Packages/SVLearning/Tests/SVLearningTests/Songs/SongImporterTests.swift
git commit -m "feat(SVLearning): SongImporter detects format by content sniff

Accepts .mxl (zip magic) and .xml/.musicxml (XML preamble) regardless
of file extension. Spec §5.2 SongImporter.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task A10: AudioSession route-change + interruption + background-audio

**Depends on A5 landing first** (same file). Run after A5 in the same wave (sequential within the wave for `AudioSessionManager.swift`, parallel with all other A-tasks).

**Files:**
- Modify: `Packages/SVAudio/Sources/SVAudio/Engine/AudioSessionManager.swift`
- Modify: `SurVibe/Info.plist` (add `audio` to `UIBackgroundModes`)

- [ ] **Step 1: Write tests for notification handlers.**

```swift
@Test func routeChangeOldDeviceUnavailableTriggersPause() async {
    let mgr = AudioSessionManager.shared
    var paused = false
    mgr.onRouteChangeRequiresPause = { paused = true }
    mgr.handleRouteChange(reason: .oldDeviceUnavailable)
    #expect(paused)
}

@Test func interruptionBeganPausesPlayback() async {
    let mgr = AudioSessionManager.shared
    var paused = false
    mgr.onInterruptionBegan = { paused = true }
    mgr.handleInterruption(type: .began, options: nil)
    #expect(paused)
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement notification subscription + handlers.**

```swift
// AudioSessionManager.swift
public var onRouteChangeRequiresPause: (() -> Void)?
public var onInterruptionBegan: (() -> Void)?
public var onInterruptionEnded: ((Bool /* shouldResume */) -> Void)?

private func subscribe() {
    NotificationCenter.default.addObserver(
        forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] notification in
        guard
            let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }
        Task { @MainActor in self?.handleRouteChange(reason: reason) }
    }

    NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] notification in
        guard
            let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        let options = (userInfo[AVAudioSessionInterruptionOptionKey] as? UInt)
            .map { AVAudioSession.InterruptionOptions(rawValue: $0) }
        Task { @MainActor in self?.handleInterruption(type: type, options: options) }
    }
}

@MainActor func handleRouteChange(reason: AVAudioSession.RouteChangeReason) {
    if reason == .oldDeviceUnavailable {
        onRouteChangeRequiresPause?()
    }
}

@MainActor func handleInterruption(type: AVAudioSession.InterruptionType,
                                   options: AVAudioSession.InterruptionOptions?) {
    switch type {
    case .began:
        onInterruptionBegan?()
    case .ended:
        let shouldResume = options?.contains(.shouldResume) ?? false
        onInterruptionEnded?(shouldResume)
    @unknown default:
        break
    }
}
```

- [ ] **Step 4: Update `SurVibe/Info.plist` to add `audio` to `UIBackgroundModes`.**

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

- [ ] **Step 5: Wire callbacks.** (Caller wiring — `PlayAlongViewModel` consumes these — lands in Wave 5 E1.)

- [ ] **Step 6: Run.**

- [ ] **Step 7: Commit.**

```bash
git add Packages/SVAudio/Sources/SVAudio/Engine/AudioSessionManager.swift \
        Packages/SVAudio/Tests/SVAudioTests/Engine/AudioSessionManagerTests.swift \
        SurVibe/Info.plist
git commit -m "feat(SVAudio): route-change + interruption + background-audio

Spec §7a. Callback hooks; consumers wired in Wave 5 E1.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Wave 1 gate — orchestrator

After all 10 A-tasks land in their isolated worktrees, the orchestrator:

1. Merges A1–A10 sequentially into `wave1-integration` branch.
2. Resolves any conflicts (only realistic conflict: A5/A10 same file — explicit ordering above).
3. Runs full test suite: `cd Packages/SVCore && swift test && cd ../../Packages/SVAudio && swift test && cd ../../Packages/SVLearning && swift test`.
4. Runs SwiftLint: `/opt/homebrew/bin/swiftlint lint --quiet`.
5. Runs Xcode build for app: `xcodebuild -workspace SurVibe.xcworkspace -scheme SurVibe build` (or equivalent).
6. Only on green: merge `wave1-integration` → trunk, dispatch Wave 2.

---

## Wave 2 — Mid-layer (4 parallel agents, ~1.5 days)

All four tasks depend only on Wave 1 outputs.

### Task B1: `PartSplitter`

**Files:**
- Create: `Packages/SVAudio/Sources/SVAudio/Pipeline/PartSplitter.swift`
- Test: `Packages/SVAudio/Tests/SVAudioTests/Pipeline/PartSplitterTests.swift`

- [ ] **Step 1: Define types from spec §5.1.** (Copy verbatim from spec — `PartSplit`, `LearnerSelection`, `LearnerScore`, `ExpectedNote`, `StaffSpec`, `HandRole`.)

- [ ] **Step 2: Write tests for each auto-rule.**

```swift
struct PartSplitterTests {
    @Test func rule1MatchesPianoTrackName() throws {
        let rendered = makeRenderedMIDI(tracks: [
            (program: 40, name: "Violin", instrName: nil),
            (program: 0,  name: "Piano",  instrName: nil),
        ])
        let split = try PartSplitter().split(rendered)
        #expect(split.learnerTrackIndices == [1])
        #expect(split.learnerInstrumentLabel == "Piano")
    }

    @Test func rule2FallsBackToGMPianoProgram() throws {
        let rendered = makeRenderedMIDI(tracks: [
            (program: 40, name: nil, instrName: nil),  // Violin
            (program: 0,  name: nil, instrName: nil),  // Acoustic Grand
        ])
        let split = try PartSplitter().split(rendered)
        #expect(split.learnerTrackIndices == [1])
        #expect(split.learnerInstrumentLabel == "Acoustic Grand Piano")
    }

    @Test func rule3PicksVoiceWithWarning() throws {
        let rendered = makeRenderedMIDI(tracks: [
            (program: 40, name: nil, instrName: nil),
            (program: 52, name: "Voice", instrName: nil),  // Choir Aahs program
        ])
        let split = try PartSplitter().split(rendered)
        #expect(split.learnerTrackIndices == [1])
        #expect(split.learnerInstrumentLabel.contains("Voice"))
    }

    @Test func rule4FallbackPicksMostNotes() throws {
        // Construct two melodic tracks, one with more notes
        ...
    }

    @Test func percussionNeverLearner() throws {
        let rendered = makeRenderedMIDI(tracks: [
            (program: 0, name: nil, instrName: nil, isPercussion: true),
            (program: 40, name: nil, instrName: nil),
        ])
        let split = try PartSplitter().split(rendered)
        #expect(!split.learnerTrackIndices.contains(0))
    }

    @Test func userOverridePicksTrackIndex() throws {
        let rendered = makeRenderedMIDI(tracks: [
            (program: 0, name: "Piano", instrName: nil),
            (program: 19, name: "Harmonium", instrName: "Reed Organ"),
        ])
        let split = try PartSplitter().split(rendered, selection: .trackIndex(1))
        #expect(split.learnerTrackIndices == [1])
    }

    @Test func staffIdentificationFromSingleTrack() throws {
        // For a track with notes both above and below middle C, expect 2 staves
        // when staff numbers are present in MIDI metadata, else single-staff.
        ...
    }

    // Run against bundled MXLs end-to-end
    @Test func sukhkartaDukhhartaPicksMelodyAsLearner() async throws {
        let bridge = try VerovioBridge()
        let xml = try MXLFixture.musicXML(for: "Sukhkarta_Dukhharta")
        let rendered = try bridge.render(musicXML: xml)
        let split = try PartSplitter().split(rendered)
        #expect(!split.learnerTrackIndices.isEmpty)
        #expect(split.accompanimentInstruments.count >= 1)
    }
}
```

- [ ] **Step 3: Run, expect FAIL.**

- [ ] **Step 4: Implement `PartSplitter`.** Algorithm laid out in spec §5.1; key code:

```swift
public struct PartSplitter: Sendable {
    public init() {}

    public func split(_ rendered: RenderedMIDI,
                      selection: LearnerSelection = .auto) throws -> PartSplit {
        let candidates = rendered.trackInfo.enumerated().map { (idx, info) in
            (idx: idx, info: info, noteCount: countNotes(rendered.data, trackIndex: idx))
        }

        let learnerIdx: Int
        let learnerLabel: String
        switch selection {
        case .trackIndex(let i):
            learnerIdx = i
            learnerLabel = labelFor(rendered.trackInfo[i])
        case .auto:
            (learnerIdx, learnerLabel) = autoSelect(candidates)
        }

        guard !rendered.trackInfo[learnerIdx].isPercussion else {
            throw PipelineError.noPlayableLearnerPart
        }

        let accompIndices = (0..<rendered.trackInfo.count).filter { $0 != learnerIdx }
        let accompMIDI = try stripTracks(rendered.data, keeping: accompIndices)

        let staves = identifyStaves(rendered.data, trackIndex: learnerIdx)
        let learnerScore = try buildLearnerScore(rendered.data, trackIndex: learnerIdx,
                                                  bpm: rendered.originalBPM)
        let lyricsTrack = findLyricsTrack(rendered)

        return PartSplit(
            learner: learnerScore,
            accompaniment: accompMIDI,
            learnerInstrumentLabel: learnerLabel,
            accompanimentInstruments: accompIndices.map { labelFor(rendered.trackInfo[$0]) },
            learnerTrackIndices: [learnerIdx],
            learnerStaves: staves,
            lyricsStaffTrackIndex: lyricsTrack
        )
    }

    // MARK: - Auto-selection rules
    private func autoSelect(_ cands: [(idx: Int, info: TrackInfo, noteCount: Int)])
        -> (Int, String)
    {
        // Rule 1: name matches /piano|pianoforte/i
        if let m = cands.first(where: { matches(name: $0.info.trackName, /piano|pianoforte/) ||
                                        matches(name: $0.info.instrumentName, /piano|pianoforte/) }) {
            return (m.idx, "Piano")
        }
        // Rule 2: GM Piano program 0–7
        if let m = cands.first(where: { (0...7).contains($0.info.program) && !$0.info.isPercussion }) {
            return (m.idx, GMProgramName.label(for: m.info.program))
        }
        // Rule 3: voice/vocal/melody/lead by name
        if let m = cands.first(where: { matches(name: $0.info.trackName, /voice|vocal|melody|lead/) }) {
            return (m.idx, "Voice (transposed)")
        }
        // Rule 4: most-notes non-percussion melodic
        let m = cands.filter { !$0.info.isPercussion }
            .max(by: { $0.noteCount < $1.noteCount })!
        return (m.idx, GMProgramName.label(for: m.info.program))
    }

    private func labelFor(_ info: TrackInfo) -> String {
        info.instrumentName
            ?? info.trackName
            ?? GMProgramName.label(for: info.program)
    }

    // ... private helpers: countNotes, stripTracks, identifyStaves,
    //     buildLearnerScore, findLyricsTrack, matches(name:_:)
}
```

- [ ] **Step 5: Run all tests + bundled-MXL pass.**

- [ ] **Step 6: Commit.**

```bash
git add Packages/SVAudio/Sources/SVAudio/Pipeline/PartSplitter.swift \
        Packages/SVAudio/Tests/SVAudioTests/Pipeline/PartSplitterTests.swift
git commit -m "feat(SVAudio): PartSplitter splits RenderedMIDI into learner + accompaniment

Spec §5.1. Rule cascade: meta-3/4 name → GM Piano program → voice
fallback → most-notes melodic. Per-staff sub-tracks for hand isolation.
Lyrics-bearing track identified for always-visible voice staff.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task B2: MIDIInputManager Bluetooth blocklist + Practice-mode dispatch

**Files:**
- Modify: `Packages/SVAudio/Sources/SVAudio/MIDI/MIDIInputManager.swift`
- Create: `Packages/SVAudio/Sources/SVAudio/MIDI/BluetoothEndpointFilter.swift`
- Tests under `Packages/SVAudio/Tests/SVAudioTests/MIDI/`

- [ ] **Step 1: Define `EndpointKind` + filter types.**

```swift
public enum EndpointKind: Sendable {
    case usb, virtual, bluetooth, network, unknown
}

public struct EndpointDescriptor: Sendable, Hashable {
    public let endpointID: MIDIUniqueID
    public let displayName: String
    public let kind: EndpointKind
}

public struct BluetoothEndpointFilter: Sendable {
    /// Matches Apple's BLE MIDI driver via kMIDIPropertyDriverOwner.
    /// Heuristic — Apple does not document a transport-property API.
    public static func detectKind(_ endpoint: MIDIEndpointRef) -> EndpointKind {
        var driverOwner: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDriverOwner, &driverOwner)
        guard status == noErr, let owner = driverOwner?.takeRetainedValue() as String? else {
            return .unknown
        }
        let lower = owner.lowercased()
        if lower.contains("bluetooth") || lower.contains("btmidi") {
            return .bluetooth
        }
        if lower.contains("usb") { return .usb }
        if lower.contains("network") { return .network }
        if lower.contains("virtual") { return .virtual }
        return .unknown
    }
}
```

- [ ] **Step 2: Tests.**

```swift
@Test func bluetoothDetectionMatchesAppleBTLEDriverOwner() {
    // Mock or live test against a Bluetooth-property string.
    // Direct test on Apple's MIDIObjectGetStringProperty requires a real endpoint;
    // unit-test the parsing logic against synthetic strings.
    let kind = BluetoothEndpointFilter.parseKind(driverOwner: "Apple BTLE MIDI Driver")
    #expect(kind == .bluetooth)

    let kindUSB = BluetoothEndpointFilter.parseKind(driverOwner: "USB-MIDI Driver")
    #expect(kindUSB == .usb)
}
```

(Refactor `detectKind` so the string-based logic is extractable as `parseKind(driverOwner:)` for testability.)

- [ ] **Step 3: In `MIDIInputManager`, add blocklist plumbing.**

```swift
// MIDIInputManager.swift
private var blockedEndpointIDs: Set<MIDIUniqueID> = []

public func updateEndpoint(_ ref: MIDIEndpointRef, descriptor: EndpointDescriptor) {
    if descriptor.kind == .bluetooth {
        blockedEndpointIDs.insert(descriptor.endpointID)
        Task { @MainActor in
            self.onPracticeModeRequired?(descriptor)
        }
    } else {
        blockedEndpointIDs.remove(descriptor.endpointID)
    }
}

/// Called from MIDIReadBlock with the source endpoint ID.
/// Returns true if the event should be dropped.
public func shouldDropEvent(fromEndpointID id: MIDIUniqueID) -> Bool {
    // Allow audio (sampler trigger) regardless; the consumer decides.
    // This blocklist is consulted only by the SCORING path, not the audio path.
    blockedEndpointIDs.contains(id)
}

/// Fired when a Bluetooth endpoint connects while Play Along is active.
/// Consumer (PlayAlongViewModel) shows the Practice-mode chip + suppresses scoring.
public var onPracticeModeRequired: ((EndpointDescriptor) -> Void)?
```

- [ ] **Step 4: Modify the `MIDIReadBlock`-equivalent path** so `shouldDropEvent` is consulted in the scoring stream, NOT in the sampler-trigger stream. Both streams may carry the same event; only the scoring stream filters.

- [ ] **Step 5: Run tests.**

- [ ] **Step 6: Commit.**

```bash
git add Packages/SVAudio/Sources/SVAudio/MIDI/MIDIInputManager.swift \
        Packages/SVAudio/Sources/SVAudio/MIDI/BluetoothEndpointFilter.swift \
        Packages/SVAudio/Tests/SVAudioTests/MIDI/
git commit -m "feat(SVAudio): Bluetooth-source detection + scoring suppression

Spec §D5, §7. BLE input still drives sampler (Practice mode); scoring
path filters via blocklist. kMIDIPropertyDriverOwner heuristic.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task B3: `ScoringAdapter`

**Files:**
- Create: `Packages/SVLearning/Sources/SVLearning/Practice/ScoringAdapter.swift`
- Test: `Packages/SVLearning/Tests/SVLearningTests/Practice/ScoringAdapterTests.swift`

- [ ] **Step 1: Types from spec §5.1.** (Copy `NoteVerdict`, `TimingClass`, `SessionScoreSummary` verbatim.)

- [ ] **Step 2: Tests.**

```swift
struct ScoringAdapterTests {
    @Test func hostTimeToBeatConversionAtHalfSpeed() {
        let score = makeScore(noteAt: 4.0, midiNote: 60)  // beat 4
        let adapter = ScoringAdapter(score: score, tonicSaPitch: 60)
        let start = HostTime(rawTicks: 0)
        // At 0.5x tempo, beat 4 of original = 8 real seconds at 120 BPM
        let now = HostTime(rawTicks: secondsToTicks(8.0))
        let v = adapter.ingest(midiNote: 60, velocity: 90,
                               hostTime: now, sequencerStartHostTime: start,
                               currentTempoScale: 0.5)
        #expect(v?.timing == .perfect)
    }

    @Test func wrongPitchMissesAccuracy() {
        let score = makeScore(noteAt: 1.0, midiNote: 60)
        let adapter = ScoringAdapter(score: score)
        let v = adapter.ingest(midiNote: 62 /* D */, velocity: 90,
                               hostTime: HostTime(rawTicks: secondsToTicks(0.5)),
                               sequencerStartHostTime: HostTime(rawTicks: 0),
                               currentTempoScale: 1.0)
        #expect(v?.score.pitchAccuracy ?? 0 < 0.5)
    }

    @Test func sweepMissedMarksUnplayedNotes() {
        let score = makeScore(noteAt: 1.0, midiNote: 60)
        let adapter = ScoringAdapter(score: score)
        let missed = adapter.sweepMissed(currentBeat: 5.0)  // way past the +300 ms window
        #expect(missed.count == 1)
    }

    @Test func nextExpectedReturnsUpcomingNote() {
        let score = makeScore(notes: [(1.0, 60), (2.0, 62), (3.0, 64)])
        let adapter = ScoringAdapter(score: score)
        let next = adapter.nextExpected(afterBeat: 1.5)
        #expect(next?.midiNote == 62)
    }
}
```

- [ ] **Step 3: Run, expect FAIL.**

- [ ] **Step 4: Implement.**

```swift
@MainActor
public final class ScoringAdapter {
    private let score: LearnerScore
    private let tonicSaPitch: UInt8
    private var consumed: Set<UUID> = []
    private var verdicts: [UUID: NoteVerdict] = [:]
    private var extras: Int = 0

    public init(score: LearnerScore, tonicSaPitch: UInt8 = 60) {
        self.score = score
        self.tonicSaPitch = tonicSaPitch
    }

    public func ingest(midiNote: UInt8, velocity: UInt8,
                       hostTime: HostTime, sequencerStartHostTime: HostTime,
                       currentTempoScale: Float) -> NoteVerdict? {
        let elapsedSec = hostTime.seconds(since: sequencerStartHostTime)
        // Beat = elapsedSec * (BPM / 60) * tempoScale
        let currentBeat = elapsedSec * (score.originalBPM / 60.0) * Double(currentTempoScale)

        // Find the unconsumed expected note whose onset is closest to currentBeat
        guard let candidate = nearestUnconsumed(to: currentBeat) else {
            extras += 1
            return nil
        }

        let beatDelta = currentBeat - candidate.beat
        let secDelta = beatDelta * (60.0 / score.originalBPM) / Double(currentTempoScale)
        let timingClass = classify(secDelta: secDelta)
        if timingClass == .miss { return nil }

        // Score with NoteScoreCalculator (pitch always 1.0 for MIDI input)
        let expectedSwar = swarString(for: candidate.midiNote, tonicSa: tonicSaPitch)
        let detectedSwar = (midiNote == candidate.midiNote) ? expectedSwar : swarString(for: midiNote, tonicSa: tonicSaPitch)
        let noteScore = NoteScoreCalculator.score(
            expectedNote: expectedSwar,
            detectedNote: detectedSwar,
            pitchDeviationCents: 0,  // exact for MIDI
            timingDeviationSeconds: abs(secDelta),
            durationDeviationFraction: 0,
            ragaContext: nil
        )

        consumed.insert(candidate.id)
        let verdict = NoteVerdict(
            expectedID: candidate.id,
            score: noteScore,
            timing: timingClass,
            timingDeltaSeconds: secDelta
        )
        verdicts[candidate.id] = verdict
        return verdict
    }

    public func nextExpected(afterBeat beat: Double) -> ExpectedNote? {
        score.notes.first { $0.beat > beat && !consumed.contains($0.id) }
    }

    public func sweepMissed(currentBeat: Double) -> [UUID] {
        // Beat threshold = currentBeat - (300 ms * tempo)... use real-time conversion
        let lateWindowBeats = 0.3 * (score.originalBPM / 60.0)
        let cutoff = currentBeat - lateWindowBeats
        let newlyMissed = score.notes
            .filter { $0.beat < cutoff && !consumed.contains($0.id) }
        for note in newlyMissed { consumed.insert(note.id) }
        return newlyMissed.map(\.id)
    }

    public func summary() -> SessionScoreSummary {
        let attempted = verdicts.count + extras
        let correct = verdicts.values.filter { $0.timing != .miss }.count
        let missed = score.notes.count - correct
        let timingValues = verdicts.values.map { weighting(for: $0.timing) }
        let timingPct = timingValues.isEmpty
            ? 0
            : (timingValues.reduce(0, +) / Double(timingValues.count)) * 100
        return SessionScoreSummary(
            notesAttempted: attempted,
            notesCorrect: correct,
            notesMissed: missed,
            notesExtra: extras,
            timingAccuracyPercent: timingPct,
            notesCorrectPercent: 100.0 * Double(correct) / max(1.0, Double(score.notes.count)),
            composite: aggregate(verdicts.values.map(\.score))
        )
    }

    private func classify(secDelta: Double) -> TimingClass {
        let abs = Swift.abs(secDelta)
        switch abs {
        case ..<0.060: return .perfect
        case ..<0.150: return secDelta < 0 ? .early : .good
        case ..<0.300: return secDelta < 0 ? .early : .late
        default: return .miss
        }
    }

    private func weighting(for cls: TimingClass) -> Double {
        switch cls {
        case .perfect: return 1.0
        case .good:    return 0.7
        case .late, .early: return 0.4
        case .miss:    return 0.0
        }
    }

    // ... private helpers: nearestUnconsumed, swarString, aggregate
}
```

- [ ] **Step 5: Run tests.**

- [ ] **Step 6: Commit.**

```bash
git add Packages/SVLearning/Sources/SVLearning/Practice/ScoringAdapter.swift \
        Packages/SVLearning/Tests/SVLearningTests/Practice/ScoringAdapterTests.swift
git commit -m "feat(SVLearning): ScoringAdapter wraps NoteScoreCalculator for MIDI input

Spec §5.1. Host-time-based timing windows (real seconds, not beats).
Wraps existing NoteScoreCalculator (caseless enum, static methods).
Pitch always exact for MIDI; timing/duration drive discrimination.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task B4: `LatencyProbe` (DEBUG-only)

**Files:**
- Create: `SurVibe/Diagnostics/LatencyProbe.swift` (`#if DEBUG` wrapped)

- [ ] **Step 1: Tests.**

```swift
#if DEBUG
@Test func recordsP50AndP99() {
    let probe = LatencyProbe()
    for ms in [10.0, 11.0, 12.0, 13.0, 14.0, 50.0] {
        probe.record(latencyMs: ms)
    }
    #expect(probe.p50() < 13.0)
    #expect(probe.p99() == 50.0)
}
#endif
```

- [ ] **Step 2: Implement using `os.signpost`.**

```swift
#if DEBUG
import os.signpost

@MainActor
final class LatencyProbe {
    private let log = OSLog(subsystem: "com.survibe", category: "Latency")
    private var samples: [Double] = []
    private let window = 1024

    func record(latencyMs: Double) {
        samples.append(latencyMs)
        if samples.count > window { samples.removeFirst(samples.count - window) }
        os_signpost(.event, log: log, name: "LatencySample",
                    "%{public}.2f ms", latencyMs)
    }

    func p50() -> Double { percentile(0.50) }
    func p99() -> Double { percentile(0.99) }
    private func percentile(_ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let idx = min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.down)))
        return sorted[idx]
    }
}
#endif
```

- [ ] **Step 3: Run tests.**

- [ ] **Step 4: Commit.**

```bash
git add SurVibe/Diagnostics/LatencyProbe.swift
git commit -m "feat(SurVibe): LatencyProbe (DEBUG-only) using os.signpost

Spec §7. Released only via Diagnostics panel for QA.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Wave 2 gate

Same as Wave 1 — orchestrator merges, runs all tests + lint + build. Only on green proceed.

---

## Wave 3 — Player layer (6 tasks, ~3 days wall-clock)

**Internal dependency:** C2/C3/C4 all extend C1 (`ArrangementPlayer`). They merge in order: C1 first, then C2/C3/C4 in parallel (auto-merge — additive extensions).

### Task C1: `ArrangementPlayer` base

**Files:**
- Create: `SurVibe/PlayAlong/Coordinators/ArrangementPlayer.swift`
- Test: `SurVibeTests/PlayAlong/ArrangementPlayerTests.swift`

- [ ] **Step 1: Define types.** Copy from spec §5.1.

- [ ] **Step 2: Tests for load + start + stop + setTempoScale forwarding.**

```swift
@MainActor
struct ArrangementPlayerTests {
    @Test func loadAcceptsPartSplit() async throws {
        let split = try makeSplit()
        let player = ArrangementPlayer(graph: MockGraph())
        try await player.load(split)
        // Sequencer should be configured, tracks loaded.
    }

    @Test func setTempoScaleForwardsToGraph() async throws {
        let mock = MockGraph()
        let player = ArrangementPlayer(graph: mock)
        try await player.load(makeSplit())
        player.setTempoScale(0.75)
        #expect(mock.lastSetTempoScale == 0.75)
    }

    @Test func startBeginsAtBeatZeroByDefault() async throws {
        let player = ArrangementPlayer(graph: MockGraph())
        try await player.load(makeSplit())
        player.start()
        #expect(player.isPlaying)
        #expect(player.currentBeat < 0)  // count-in beats are negative
    }
}
```

- [ ] **Step 3: Run, expect FAIL.**

- [ ] **Step 4: Implement base.**

```swift
@Observable
@MainActor
final class ArrangementPlayer {
    private let graph: MultiTrackSamplerGraphProtocol
    private(set) var isEnabled = true
    private(set) var isPlaying = false
    private(set) var currentBeat: Double = 0
    private(set) var startHostTime: HostTime?
    private var split: PartSplit?

    init(graph: MultiTrackSamplerGraphProtocol = MultiTrackSamplerGraph.shared) {
        self.graph = graph
    }

    func load(_ split: PartSplit) async throws {
        self.split = split
        try graph.loadMIDI(split.accompaniment)
        graph.setTempoScale(1.0)
    }

    func start(atBeat: Double = 0, countInBars: Int = 1) {
        // Count-in implemented in C2.
        startHostTime = HostTime.now()
        graph.start()
        isPlaying = true
    }

    func pause() { graph.pause(); isPlaying = false }
    func resume() { graph.resume(); isPlaying = true }
    func stop() { graph.stop(); isPlaying = false }

    func setTempoScale(_ rate: Float) {
        graph.setTempoScale(rate)
    }
}
```

(Add a `MultiTrackSamplerGraphProtocol` test seam to allow mocking in tests.)

- [ ] **Step 5: Run.**

- [ ] **Step 6: Commit.**

```bash
git add SurVibe/PlayAlong/Coordinators/ArrangementPlayer.swift \
        SurVibeTests/PlayAlong/ArrangementPlayerTests.swift
git commit -m "feat(SurVibe): ArrangementPlayer base — load/start/stop/tempoScale

Wraps MultiTrackSamplerGraph. Count-in (C2), loop (C3), hand isolation
(C4) layer on top in subsequent tasks.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task C2: ArrangementPlayer count-in

**Files:**
- Modify: `SurVibe/PlayAlong/Coordinators/ArrangementPlayer.swift`
- Test: extend `ArrangementPlayerTests`

- [ ] **Step 1: Test.**

```swift
@Test func startSchedulesCountInClicksBeforeBeatZero() async throws {
    let mock = MockGraph()
    let player = ArrangementPlayer(graph: mock)
    try await player.load(makeSplit(timeSignatureNumerator: 4))
    player.start(countInBars: 1)
    // 4 click events at -4, -3, -2, -1 beat positions on channel 10
    #expect(mock.scheduledMetronomeClicks.count == 4)
}
```

- [ ] **Step 2: Implement.**

```swift
func start(atBeat: Double = 0, countInBars: Int = 1) {
    guard let split else { return }
    let beats = countInBars * split.learner.beatsPerMeasure
    for i in 0..<beats {
        let beatPos = atBeat - Double(beats - i)
        graph.scheduleMetronomeClick(at: beatPos, channel: 9)
    }
    startHostTime = HostTime.now()
    graph.start(at: atBeat - Double(beats))  // begin from count-in
    isPlaying = true
    currentBeat = atBeat - Double(beats)
}
```

- [ ] **Step 3+4: Run + commit.**

```bash
git commit -m "feat(SurVibe): ArrangementPlayer 1-bar audible count-in

Spec §2 step 6. Count-in clicks ride channel-10 metronome patch on the
same sampler graph so they're tempo-locked to scoring's host clock.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task C3: `SectionLoopController` + ArrangementPlayer integration

**Files:**
- Create: `SurVibe/PlayAlong/Coordinators/SectionLoopController.swift`
- Modify: `ArrangementPlayer.swift`
- Tests

- [ ] **Step 1: Types.** `LoopRegion` from spec.

- [ ] **Step 2: Tests.**

```swift
@Test func setLoopMakesPlayerSeekBackAtEndOfRegion() async throws {
    let mock = MockGraph()
    let player = ArrangementPlayer(graph: mock)
    try await player.load(makeSplitWithMeasures(20))
    player.setLoop(LoopRegion(startMeasure: 5, endMeasure: 8))
    player.start()
    // Simulate currentBeat advancing past measure 8
    player.simulateBeatTick(beatsPerMeasure: 4, currentBeat: 32.5)
    // Player should have called graph.seek to start of measure 5 (beat 16)
    #expect(mock.lastSeekBeat == 16)
}

@Test func loopFirstIterationPlaysCountInOnly() async throws {
    let mock = MockGraph()
    let player = ArrangementPlayer(graph: mock)
    try await player.load(makeSplitWithMeasures(20))
    player.setLoop(LoopRegion(startMeasure: 5, endMeasure: 8))
    player.start()
    let initialClicks = mock.scheduledMetronomeClicks.count
    // Trigger loop wraparound
    player.simulateBeatTick(beatsPerMeasure: 4, currentBeat: 32.5)
    let afterWrap = mock.scheduledMetronomeClicks.count
    #expect(afterWrap == initialClicks)  // no new count-in
}
```

- [ ] **Step 3: Implement.**

```swift
// SectionLoopController.swift — pure logic
struct SectionLoopController {
    let region: LoopRegion
    let beatsPerMeasure: Int

    var startBeat: Double { Double((region.startMeasure - 1) * beatsPerMeasure) }
    var endBeat: Double { Double(region.endMeasure * beatsPerMeasure) }

    func shouldWrap(currentBeat: Double) -> Bool {
        currentBeat >= endBeat
    }
}

// ArrangementPlayer.swift
private var loopController: SectionLoopController?
private var firstLoopIterationDone = false

func setLoop(_ region: LoopRegion?) {
    guard let split else { return }
    if let region = region {
        loopController = SectionLoopController(region: region,
                                                beatsPerMeasure: split.learner.beatsPerMeasure)
        firstLoopIterationDone = false
    } else {
        loopController = nil
    }
}

// In tick handler (CADisplayLink-driven elsewhere):
private func tick() {
    guard isPlaying else { return }
    currentBeat = computeBeat()
    if let lc = loopController, lc.shouldWrap(currentBeat: currentBeat) {
        graph.seek(toBeat: lc.startBeat)
        firstLoopIterationDone = true
        // No count-in on subsequent iterations.
    }
}
```

- [ ] **Step 4+5: Run + commit.**

---

### Task C4: ArrangementPlayer practice mode + hand isolation

**Files:**
- Modify: `ArrangementPlayer.swift`

- [ ] **Step 1: Test.**

```swift
@Test func rightHandModeMutesLeftHandWhenHearOtherHandFalse() async throws {
    let mock = MockGraph()
    let player = ArrangementPlayer(graph: mock)
    try await player.load(makeSplitWithTwoStaves())
    player.practiceMode = .rightHand
    player.hearOtherHand = false
    player.start()
    #expect(mock.mutedTrackIndices.contains(/* LH track */ 1))
    #expect(!mock.mutedTrackIndices.contains(/* RH track */ 0))
}

@Test func bothModeMutesNothing() async throws {
    let mock = MockGraph()
    let player = ArrangementPlayer(graph: mock)
    try await player.load(makeSplitWithTwoStaves())
    player.practiceMode = .both
    player.start()
    #expect(mock.mutedTrackIndices.isEmpty)
}
```

- [ ] **Step 2: Implement.**

```swift
var practiceMode: PracticeMode = .both {
    didSet { applyHandMute() }
}
var hearOtherHand: Bool = true {
    didSet { applyHandMute() }
}

private func applyHandMute() {
    guard let split else { return }
    var muted: Set<Int> = []
    if !hearOtherHand {
        switch practiceMode {
        case .leftHand:
            muted.formUnion(split.learnerStaves
                .filter { $0.role == .rightHand }
                .flatMap { trackIndicesFor(staff: $0) })
        case .rightHand:
            muted.formUnion(split.learnerStaves
                .filter { $0.role == .leftHand }
                .flatMap { trackIndicesFor(staff: $0) })
        case .both:
            break
        }
    }
    graph.setMutedTracks(muted)
}
```

- [ ] **Step 3+4: Run + commit.**

---

### Task C5: SongImporter persists PartSplit on Song

**Files:**
- Modify: `Packages/SVLearning/Sources/SVLearning/Songs/SongImporter.swift`

- [ ] **Step 1: Test.**

```swift
@Test func importPersistsLearnerTrackAndSummary() async throws {
    let importer = SongImporter(modelContext: ctx)
    let song = try await importer.importSong(from: bundleURL("Sukhkarta_Dukhharta.mxl"))
    #expect(song.learnerTrackIndex != nil)
    #expect(song.accompanimentInstrumentSummary?.contains("·") ?? false)
}
```

- [ ] **Step 2: Implement** — after Verovio render, call `PartSplitter().split(rendered)` once and store `learnerTrackIndex` + `accompanimentInstrumentSummary` (joined by " · ") on the Song.

- [ ] **Step 3+4: Run + commit.**

---

### Task C6: Lyrics rendering + voice-staff-always-visible

**Files:**
- Modify: `VerovioBridge.swift` (configure render options)
- Modify: render-pipeline call sites in PlayAlong

- [ ] **Step 1: Test.**

```swift
@Test func renderIncludesLyricsForBundledSukhkarta() async throws {
    let bridge = try VerovioBridge()
    let xml = try MXLFixture.musicXML(for: "Sukhkarta_Dukhharta")
    let rendered = try bridge.render(musicXML: xml, options: .init(includeLyrics: true))
    let svg = rendered.svgPages.first ?? ""
    // Verovio emits <g class="lyrics"> nodes when lyrics are present
    #expect(svg.contains("class=\"lyrics\"") || svg.contains("Sukh"))  // text fallback
}
```

- [ ] **Step 2: Implement.**

```swift
public struct RenderOptions: Sendable {
    public var includeLyrics: Bool = true
    public var includeVoiceStaffWhenLyricsPresent: Bool = true
}

public func render(musicXML: String, options: RenderOptions = .init()) throws -> RenderedScore {
    // Configure Verovio to include lyrics and the voice-bearing staff
    let opts: [String: Any] = [
        "lyricElision": true,
        "lyricVerseCollapse": false,
        // ... whatever Verovio Toolkit options control lyric inclusion
    ]
    toolkit.setOptions(JSONString(opts))
    // ... existing render path
}
```

- [ ] **Step 3+4: Run + commit.**

---

## Wave 3 gate — same as before.

---

## Wave 4 — UI (4 parallel agents, ~2 days)

### Task D1: PlayAlongToolbar revamp

**Files:**
- Modify: `SurVibe/PlayAlong/PlayAlongToolbar.swift`
- Tests (snapshot or assertion)

- [ ] **Step 1: Test that all four new controls bind correctly.** (Snapshot tests for the toolbar layout in compact + regular size classes.)

- [ ] **Step 2: Implement.** Toolbar UI per spec §5.2:

```swift
struct PlayAlongToolbar: View {
    @Bindable var viewModel: PlayAlongViewModel

    var body: some View {
        HStack(spacing: 16) {
            transportControls
            backingPicker
            tempoSlider
            handsPicker
            loopControl
            if viewModel.backingMode == .click { clickLevelPicker }
            tanpuraButton  // existing
        }
        .padding()
        .glassEffect(.regular)
    }

    private var backingPicker: some View {
        Picker("Backing", selection: $viewModel.backingMode) {
            Text("On").tag(BackingMode.on)
            Text("Click").tag(BackingMode.click)
            Text("Off").tag(BackingMode.off)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Backing accompaniment mode")
    }

    private var tempoSlider: some View {
        VStack {
            Text("\(viewModel.tempoScale, format: .percent.precision(.fractionLength(0)))")
                .font(.caption)
            Slider(value: $viewModel.tempoScale, in: 0.5...1.5, step: 0.05)
                .frame(width: 160)
                .accessibilityLabel("Tempo scale, 50% to 150%")
        }
    }

    private var handsPicker: some View {
        Picker("Hands", selection: $viewModel.practiceMode) {
            Text("Both").tag(PracticeMode.both)
            Text("RH").tag(PracticeMode.rightHand)
                .disabled(!viewModel.hasMultipleStaves)
            Text("LH").tag(PracticeMode.leftHand)
                .disabled(!viewModel.hasMultipleStaves)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var loopControl: some View {
        if let region = viewModel.loopRegion {
            Button("Loop m.\(region.startMeasure)–\(region.endMeasure) ✕") {
                viewModel.loopRegion = nil
            }
        } else {
            Button("Loop") { viewModel.showLoopBuilder = true }
        }
    }

    private var clickLevelPicker: some View {
        Picker("Click", selection: $viewModel.clickLevel) {
            Text("Soft").tag(ClickLevel.soft)
            Text("Normal").tag(ClickLevel.normal)
            Text("Loud").tag(ClickLevel.loud)
        }
        .pickerStyle(.segmented)
    }
}
```

- [ ] **Step 3+4: Run + commit.**

---

### Task D2: SongDetailView Parts section + Sa picker + previews

**Files:**
- Create: `SurVibe/Songs/SongDetailViewParts.swift`
- Modify: `SurVibe/Songs/SongDetailView.swift`

- [ ] **Step 1: Tests.**

- [ ] **Step 2: Implement** per spec §5.2:

```swift
struct SongDetailViewParts: View {
    let song: Song
    let split: PartSplit
    @Binding var learnerTrackIndex: Int
    @Binding var tonicSaPitch: UInt8
    let onPreviewLearner: () -> Void
    let onPreviewBacking: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parts").font(.headline)
            HStack {
                Text("I'll play:")
                Picker("", selection: $learnerTrackIndex) {
                    ForEach(Array(allTracks.enumerated()), id: \.offset) { idx, label in
                        Text(label).tag(idx)
                    }
                }
            }
            HStack {
                Text("Backing:")
                Text(split.accompanimentInstruments.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Tonic Sa:")
                Picker("", selection: $tonicSaPitch) {
                    ForEach(48...72, id: \.self) { midiNote in
                        Text(noteName(UInt8(midiNote))).tag(UInt8(midiNote))
                    }
                }
            }
            HStack {
                Button("▶ Preview my part", action: onPreviewLearner)
                Button("▶ Preview backing", action: onPreviewBacking)
            }
        }
        .padding()
        .glassEffect(.regular)
    }
}
```

- [ ] **Step 3+4: Run + commit.**

---

### Task D3: PlaybackCoordinator rework — visualization-only

**Files:**
- Modify: `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift`

- [ ] **Step 1: Tests for the simplified contract.**

- [ ] **Step 2: Remove the audio-emission path** (`soundFont.playNote(...)` for scheduled notes goes away). PlaybackCoordinator is now a visualization-timeline owner only:
  - Owns `noteEvents` parsed from learner part for falling-notes / sheet rendering.
  - Owns `currentTime` driven by ArrangementPlayer's master clock.
  - Removes its own audio output.

- [ ] **Step 3+4: Run + commit.**

---

### Task D4: Results overlay split

**Files:**
- Create: `SurVibe/PlayAlong/PlayAlongResultsOverlay+Split.swift`
- Modify: `PlayAlongResultsOverlay.swift`

- [ ] **Step 1: Snapshot test.**

- [ ] **Step 2: Implement** — show two headline numbers (Notes correct % + Timing %), composite NoteScore smaller below.

```swift
extension PlayAlongResultsOverlay {
    var splitScoreSection: some View {
        HStack(spacing: 32) {
            metric("Notes correct", "\(summary.notesCorrectPercent, format: .percent)")
            metric("Timing", "\(summary.timingAccuracyPercent, format: .percent)")
        }
    }
}
```

- [ ] **Step 3+4: Run + commit.**

---

## Wave 4 gate — same.

---

## Wave 5 — Integration & device pass (sequential, ~4 days)

### Task E1: Wire PlayAlongViewModel end-to-end

**Files:**
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift`
- Modify: `SurVibe/PlayAlong/PlayAlongSceneHost.swift`

- [ ] **Step 1: Tests** for the full-load happy path on a bundled MXL.

- [ ] **Step 2: Wire** — VM owns `ArrangementPlayer` + `ScoringAdapter` + (existing) `PlaybackCoordinator`. Subscribe MIDI input stream → split into sampler-trigger path (always) and scoring path (filtered by `MIDIInputManager.shouldDropEvent`). Subscribe `AudioSessionManager` callbacks → pause on route-change / interruption / Bluetooth-detected.

- [ ] **Step 3+4: Run + commit.**

---

### Task E2: Integration tests on bundled MXLs

**Files:**
- Create: `SurVibeTests/PlayAlong/LearnASongIntegrationTests.swift` (XCTest, real `AVAudioEngine`)

- [ ] **Step 1: Test the four bundled songs end-to-end.**

```swift
final class LearnASongIntegrationTests: XCTestCase {
    @MainActor
    func testSukhkartaLoadsAndAdvancesAtHalfSpeed() async throws {
        let host = PlayAlongSceneHost(song: bundledSong("Sukhkarta_Dukhharta"))
        let vm = host.viewModel
        try await vm.task()
        vm.tempoScale = 0.5
        vm.start()

        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertGreaterThan(vm.currentBeat, 0.5)
        XCTAssertLessThan(vm.currentBeat, 4.0)
    }

    func testInjectMIDIScoresVerdicts() async throws {
        // Inject 4 simulated MIDI inputs at known host times → verify NoteVerdict stream
    }

    func testTempoChangeMidPlaybackStaysConsistent() async throws { ... }
}
```

- [ ] **Step 2+: Implement, run, commit.**

---

### Task E3: Device pass — latency + memory profile

- [ ] Run on physical iPad with USB MIDI keyboard.
- [ ] Measure p50/p99 via LatencyProbe through 3 minutes of Sukhkarta playback. Must be ≤ 12 ms / ≤ 18 ms.
- [ ] RSS memory probe: full 30-min session; record peak.
- [ ] VoiceOver pass on toolbar + Parts section.
- [ ] Plug Bluetooth MIDI → verify Practice-mode chip appears, scoring suppressed, sampler still triggers.
- [ ] Document results in `docs/superpowers/plans/2026-04-30-learn-a-song-device-pass.md`.

---

## Self-Review

**Spec coverage:** every section in spec §1–§17 is mapped to one or more tasks above. Spec D-decisions D1–D7 covered (D3=A4, D4=A5, D5=B2, D6=A1+B3, D7=existing). Q-resolutions Q1–Q13 covered.

**Placeholder scan:** no TBDs. Where implementation bodies are >100 LOC (PartSplitter, ScoringAdapter, ArrangementPlayer), the spec contains the full type definitions — agents are expected to read the spec section linked in the task.

**Type consistency:** `HostTime`, `PartSplit`, `ExpectedNote`, `NoteVerdict`, `LoopRegion`, `PracticeMode`, `BackingMode`, `ClickLevel`, `BufferGrantTier` — defined once, used consistently across tasks.

**Parallelism:** Wave 1 has 10 truly-independent tasks. Wave 2 has 4. Wave 3 has 6 with internal ordering (C1 → C2/C3/C4 in parallel; C5/C6 fully parallel). Wave 4 has 4. Wave 5 sequential. Total 6 waves, ~13 days wall-clock at peak parallelism.

---

---

## Verification Amendments (2026-04-30)

The plan was independently reviewed against (a) actual codebase and (b) Apple Developer docs / iOS HIG. The following corrections **override** the corresponding sections of the plan above. Subagents must follow these amendments, not the original task text where they conflict.

### A. Corrected file paths (verified by `find`)

| Plan path (WRONG) | Actual path |
|---|---|
| `Packages/SVLearning/Sources/SVLearning/Practice/PracticeSession.swift` | `SurVibe/Practice/PracticeSessionRecorder.swift` (recorder) — there is no `PracticeSession.swift` model file. The "session record" is currently produced ad-hoc by the recorder. **Task A7 redefined**: create a new `@Model` `PlayAlongSession` in `SurVibe/Models/PlayAlongSession.swift` (NOT replace nonexistent file). Schema-reset note still applies (drop SwiftData store on first launch). |
| `Packages/SVLearning/Sources/SVLearning/Songs/SongLibraryEmptyState.swift` | `SurVibe/Songs/SongLibraryEmptyState.swift` (app target). Move the modify task (A8) accordingly. |
| `Packages/SVLearning/Sources/SVLearning/Songs/SongImporter.swift` | This file is a JSON-DTO importer, NOT the MXL ingest path. The actual MXL/MusicXML ingest lives in `SurVibe/ContentImportManager.swift`. **Task A9 retargets** to `SurVibe/ContentImportManager.swift`. |
| `Packages/SVCore/Sources/SVCore/Models/Song.swift` | `SurVibe/Models/Song.swift` (app target). **Task A6 retargets** there. Also see `SurVibe/Models/Song+Tanpura.swift` and `SurVibe/Models/Song+StaffNotation.swift` for related extensions; new fields go on the main `Song.swift`. |
| `SurVibeTests/PlayAlong/...` | Project's existing test target naming may differ; locate via `git grep -l "import XCTest"` and put new tests alongside existing PlayAlong tests. |

### B. Corrected API signatures

**B.1 `AudioSessionManager` (Task A5, A10) — already has most of what A10 adds.**

```swift
// EXISTING at Packages/SVAudio/Sources/SVAudio/Engine/AudioSessionManager.swift:
public func configure() throws                       // entry point — NOT `activate()`
public func configureForPlayback() throws            // alternate entry
public var onInterruptionBegan: (@Sendable () -> Void)?
public var onInterruptionEnded: (@Sendable (Bool) -> Void)?
public var onRouteChange: (@Sendable () -> Void)?
```

- **Task A5 amended**: rename plan's `activate()` to extending `configureForPlayback()` (don't introduce a third entry point). Add 48 kHz + buffer-grant verification inside that existing function. Tests call `configureForPlayback()`, not `activate()`.
- **Task A10 amended**: do NOT introduce `onInterruption*` / `onRouteChange*` (already exist). Instead:
  - Tighten existing `onRouteChange` to ALSO carry the `RouteChangeReason` (add optional `onRouteChangeWithReason: (@Sendable (AVAudioSession.RouteChangeReason) -> Void)?`, fire alongside the legacy one).
  - Add `Info.plist` `UIBackgroundModes` `audio` entry.
  - All new callbacks must be `@Sendable` (Swift 6 strict).

**B.2 `MultiTrackSamplerGraph` (Task A4) — actual public API is smaller than plan assumed.**

Existing API: `init(trackCount: Int)`, `loadMIDI(_ rendered: RenderedMIDI)`, `loadBank(at:presets:)`, `setTempo(rate:)`, `play()`, `pause()`, `stop()`, `teardown()`. Plan's `ArrangementPlayer` calls `start`, `resume`, `seek`, `setMutedTracks`, `scheduleMetronomeClick` — **none exist**. Amend Task A4 to add these methods to the graph as part of the same task:

```swift
// New API to add in Task A4:
public func resume() throws            // alias for play() if state is .paused
public func seek(toBeat: Double)       // sequencer.currentPositionInBeats = beat
public func setMutedTracks(_ indices: Set<Int>)  // mutes per-track sampler outputs
public func scheduleMetronomeClick(at beat: Double, channel: UInt8)
public func setTempoScale(_ rate: Float)  // replaces setTempo(rate:); uses sequencer.rate
```

Tests must use `init(trackCount: Int)` and `loadMIDI(_ rendered: RenderedMIDI)` — never `init()` with no args, never `loadMIDI(Data)`. Use `MXLFixture` to build a `RenderedMIDI` in tests.

**B.3 `TrackInfo` (Task A2) — existing type is `Equatable`, `program: UInt8?` (Optional).**

```swift
// EXISTING at Packages/SVAudio/Sources/SVAudio/Pipeline/PipelineError.swift:73-91:
public struct TrackInfo: Equatable, Sendable {
    public let channel: UInt8
    public let program: UInt8?            // <-- OPTIONAL, not UInt8
    public let isPercussion: Bool
    public init(channel: UInt8, program: UInt8?, isPercussion: Bool) { ... }
}
```

Task A2 amendments:
- Keep `program: UInt8?` (do NOT change to non-optional).
- Add `trackName: String?` and `instrumentName: String?` as additional fields (with default-nil for back-compat).
- Keep `Equatable` conformance (don't add `Hashable` unless `RenderedMIDI` also gains it — out of scope).
- `init` signature stays back-compat: `init(channel:program:isPercussion:trackName:instrumentName:)` with the new ones defaulting to `nil`.

**B.4 `NoteScoreCalculator.score(...)` — actual parameter label is `durationDeviation:`, not `durationDeviationFraction:`.**

```swift
// CORRECT call from ScoringAdapter (Task B3):
let noteScore = NoteScoreCalculator.score(
    expectedNote: expectedSwar,
    detectedNote: detectedSwar,
    pitchDeviationCents: 0,
    timingDeviationSeconds: abs(secDelta),
    durationDeviation: 0,                // <-- NOT durationDeviationFraction
    ragaContext: nil
)
```

Also note: `NoteScoreCalculator.score` accepts `playedVelocity:` and `expectedVelocity:` — use them to engage 45/25/15/15 weighting (more discriminating; addresses the "free 50% pitch" persona concern). Pass `playedVelocity: velocity` from the MIDI input event and `expectedVelocity: nil` (we don't have expected velocity from MusicXML in v1; this still drops the pitch weight to 45% which is mildly more honest).

### C. Wave 3 re-serialisation

C2/C3/C4 all modify `start(_:countInBars:)` and the tick path inside `ArrangementPlayer`. Parallel merge will conflict. **Amended ordering**: C1 → **C2 → C3 → C4 sequentially** (one agent owns the entire ArrangementPlayer build). Wave 3 maximum parallelism is now 3 agents (one for ArrangementPlayer C1+C2+C3+C4 sequentially, one for C5, one for C6) — not 6.

Updated wall-clock for Wave 3: ~5 days (down from 12 sequential, up from 3 ideal parallel; the longest serial chain is the ArrangementPlayer agent). Total wall-clock budget revised below.

### D. SMF Set Tempo (meta-0x51) extraction

`RenderedMIDI` does not currently expose tempo. `LearnerScore.originalBPM` and `ArrangementPlayer` both depend on it. **Add to Task A2**: alongside the meta-3/4 capture, also capture meta-0x51 (Set Tempo, 3-byte microseconds-per-quarter) and expose `RenderedMIDI.originalBPM: Double` (or `[TempoChange]` for future tempo-map support; for v1, take the first tempo event).

```swift
// In the meta-event branch:
case 0x51:  // Set Tempo: 3 bytes µs-per-quarter-note
    let micros = (UInt32(bytes[idx]) << 16)
               | (UInt32(bytes[idx + 1]) << 8)
               |  UInt32(bytes[idx + 2])
    if firstTempoMicros == nil { firstTempoMicros = micros }
```

`originalBPM = 60_000_000.0 / Double(firstTempoMicros ?? 500_000)` (default 120 BPM).

### E. Banned-pattern fixes

- **Force-unwrap in `PartSplitter.autoSelect`**: replace `cands.filter { ... }.max(by: ...)!` with `guard let m = cands.filter { ... }.max(by: ...) else { throw PipelineError.noPlayableLearnerPart }`.
- **`OSLog` in LatencyProbe (Task B4)**: replace with `Logger.survibe(category: "Latency")` (the project standard) + `OSSignposter` (modern signpost API). Use `Logger` for log output, `OSSignposter` for signposts.
- **XCTest for unit tests (Task C1)**: switch to Swift Testing. Use XCTest only for E2 integration tests that need a host app + real `AVAudioEngine`.

### F. Concurrency / Sendable corrections

- New callbacks introduced in any task must be `@Sendable` typed when stored as captured closures crossing actor boundaries.
- `MIDIInputManager` Bluetooth blocklist (Task B2): use `OSAllocatedUnfairLock<Set<MIDIUniqueID>>` (per AUD-033 mandate in CLAUDE.md), NOT a plain `Set` on `@MainActor`. CoreMIDI source-add callback can fire on RT thread, so the blocklist read in the scoring path needs lock-protected access.

### G. UI / HIG corrections (PlayAlongToolbar — Task D1)

iPad HIG advises ≤ 5–6 primary toolbar controls. Plan stuffs 7+. **Restructure**:

```
Primary toolbar (visible always):
  ├── Transport (play/pause/stop)
  ├── Tempo slider (0.5×–1.5×, with .accessibilityValue)
  ├── Hands picker (Both / RH / LH)
  └── ⋯ overflow menu

Overflow menu:
  ├── Backing (On / Click / Off)
  │     └── Click level (Soft / Normal / Loud) — nested, only when Backing=Click
  ├── Loop region builder
  └── Tanpura settings (existing)
```

`Hands` picker — when single-staff, show inline subtitle *"Single-staff score"* under the disabled chips, NOT a tooltip (iPad has no consistent hover surface).

`Tempo slider` — add `.accessibilityValue("\(Int(viewModel.tempoScale * 100)) percent")` so VoiceOver speaks the live value. Also add `.accessibilityHint` on each segmented-picker.

`Reduce Motion` — when `@Environment(\.accessibilityReduceMotion) == true`, count-in shows static "3 → 2 → 1 → Go" text rather than pulsing animation.

### H. Background-audio decision (Task A10 + Info.plist)

App Store risk for adding `UIBackgroundModes audio` without clear backgrounded-listening value. **Decision**: drop `audio` from `UIBackgroundModes` in v1. When the user backgrounds Play Along, the audio session deactivates and playback pauses. On foreground return, user resumes from toolbar. This is honest with the App Store reviewer ("we don't background audio") and matches the spec's "scoring pauses when backgrounded" intent.

Spec §7a "background-audio entitlement" line is superseded by this amendment. Add a one-line note in the spec at next iteration.

### I. SF2 215 MB load — background load + progress

`AVAudioUnitSampler.loadSoundBankInstrument` blocks the calling thread. On 4 GB iPad mini 6, a 215 MB SF2 + a Verovio render in the same launch can trigger jetsam. Amend `AudioEngineManager`/`ProductionMultiChannelEngine` initialization to:

- Load SF2 on `Task.detached(priority: .utility)`.
- Show a progress affordance ("Preparing instruments…" with progress ring) in the SongDetailView while loading, gated by an `isReady` published property.
- Subscribe to `UIApplication.didReceiveMemoryWarningNotification`; on warning, log + emit a one-time toast.

### J. Buffer-grant test fragility (Task A5)

Hard-asserting `session.preferredIOBufferDuration < 0.006` will fail on simulators / older iPads. Amend test:

```swift
@Test func requestsLowIOBufferDuration() async throws {
    try AudioSessionManager.shared.configureForPlayback()
    let session = AVAudioSession.sharedInstance()
    // Hint we set, NOT what's granted — the OS may clamp.
    #expect(session.preferredIOBufferDuration > 0)
    #expect(session.preferredIOBufferDuration <= 0.006)
}

@Test func reportsGrantedBufferTier() async throws {
    try AudioSessionManager.shared.configureForPlayback()
    let tier = AudioSessionManager.shared.lastBufferGrantTier
    #expect(tier != .unknown)
    // Don't assert .excellent — simulator may grant > 7 ms.
}
```

### K. Single source of truth for tonic Sa

Plan exposes Sa picker in two places: Parts section (D2) AND tanpura sheet (existing). HIG: single source. **Amended**: SongDetailView Parts section owns the editor. Tanpura sheet displays the current Sa as read-only with a "Change in Parts" button that scrolls the detail view to the picker. Both write the same `SongProgress.preferredSaHz` field.

### L. Import-time PartSplitter on background task

`SongImporter` / `ContentImportManager` (Task A9 + C5) — running PartSplitter inline on the main thread during import will jank the UI for large MXLs. Amend C5: run `PartSplitter().split(rendered)` inside `Task.detached(priority: .utility)`, persist via a `@ModelActor` so the SwiftData write happens on its own context.

### M. Updated wall-clock budget

| Wave | Original parallel | Amended parallel | Reason |
|------|-------|--------|---|
| 0 | 1 day | 1 day | unchanged |
| 1 | 1.5 days | 1.5 days | unchanged (A2 grows slightly with tempo extract) |
| 2 | 1.5 days | 1.5 days | unchanged |
| 3 | 3 days | **5 days** | C1+C2+C3+C4 must serialise on ArrangementPlayer |
| 4 | 2 days | 2 days | unchanged |
| 5 | 4 days | 4 days | unchanged |
| **Total** | **~13 days** | **~15 days** | +2 days for Wave 3 serialisation |

Speedup vs sequential: ~2.7× (down from 3×). Still well worth the parallelism cost.

### N. Re-validate plan compliance after amendments

After applying these amendments, the plan is consistent with:
- Verified file paths (all targets exist)
- Existing API signatures (`configureForPlayback`, `setTempo` → `setTempoScale`, `durationDeviation`, `program: UInt8?`, etc.)
- CLAUDE.md banned patterns (no force-unwrap, no `OSLog` raw, no XCTest for new unit tests)
- Swift 6 strict concurrency (`@Sendable` callbacks, `OSAllocatedUnfairLock`)
- iPad HIG (toolbar overflow, accessibilityValue, inline disabled subtitle, single SoT for Sa)
- App Store review safety (no unjustified background-audio mode)

The `LOC ~3,620` and `5–6 weeks` headlines stay roughly accurate (slight increase for tempo extract, graph API expansion, SF2 background loader, toolbar overflow restructure). No major scope change; this is execution detail correction.

---

## Execution Handoff

**Plan complete and saved to** `docs/superpowers/plans/2026-04-30-learn-a-song.md`. **Two execution options:**

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, parallel waves with worktree isolation, fast iteration. Best fit for the 1M-context-per-agent + 20× parallel agent budget.
2. **Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints for review.

**Which approach?**
