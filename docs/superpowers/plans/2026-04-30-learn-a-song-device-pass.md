# Learn-a-Song — Device Pass Results (E3)

**Date:** 2026-04-30
**Build:** `513a686 feat(SurVibe): Wave 5 E2 — integration tests + AppLatencyProbe wiring`
**Device:** iPad Air (4th generation) — `00008101-00094D413463001E`
**iOS:** Verified at install time; Debug build (Sign to Run Locally).

---

## 1. Latency profile (p50 / p99)

**Spec gate (plan §E3):** p50 ≤ 12 ms, p99 ≤ 18 ms over a 3-minute Sukhkarta_Dukhharta playback with USB MIDI keyboard.

**How to capture:**
1. Plug a USB MIDI keyboard into the iPad via USB-C dock or Lightning-to-USB-3 adapter.
2. Open SurVibe → Songs → import or pick `Sukhkarta_Dukhharta` → Play Along.
3. Play the song through for ≥ 3 minutes. Each note-on event records into `AppLatencyProbe.shared` (DEBUG only).
4. Pause briefly at end. Read `latencyProbe.p50()` and `latencyProbe.p99()` from a Diagnostics button (DEBUG-only) OR via Console:
   ```
   log stream --predicate 'subsystem == "com.survibe" AND category == "Latency"' --style compact
   ```
   Each `LatencySample` event prints the per-note ms.

| Metric | Target | Measured | Pass? |
|--------|--------|----------|-------|
| p50    | ≤ 12 ms | __ ms | ☐ |
| p99    | ≤ 18 ms | __ ms | ☐ |

---

## 2. Memory profile (30-min session)

**Spec gate:** Peak RSS during a 30-min continuous Play-Along session.

**How to capture:**
- Xcode → Product → Profile → Allocations / Activity Monitor.
- Run a full Sukhkarta loop for 30 minutes, with at least one tempo change and one section-loop set/clear.

| Metric | Target | Measured | Pass? |
|--------|--------|----------|-------|
| Peak RSS | reasonable (< ~250 MB on iPad Air gen 4) | __ MB | ☐ |
| RSS growth between min 5 and min 30 | < 20 MB | __ MB | ☐ |

---

## 3. VoiceOver pass

**Surfaces to verify:**
- [ ] Songs list — `SongLibraryEmptyState` "Try a sample" button has label + hint announced.
- [ ] Song detail — `SongDetailViewParts` track picker, Sa picker, Preview buttons all announced.
- [ ] Play-Along toolbar:
  - [ ] Play / Pause / Stop transport
  - [ ] Tempo slider — value announced as percent (e.g., "100 percent")
  - [ ] Hands picker (Both / RH / LH) — disabled state announced when single-staff
  - [ ] Loop button — toggles between "Loop" and "Loop measures X to Y, dismiss"
  - [ ] Backing picker (On / Click / Off)
  - [ ] Click level picker (only visible when Backing == Click)
  - [ ] Tanpura settings
- [ ] Loop builder sheet — Steppers ("Start measure", "End measure") and Done/Cancel announced.
- [ ] Results overlay — split scores read in order: "Notes correct: X percent. Timing: Y percent."

Mark each ☑ as you verify. Do a single sweep with VoiceOver on (triple-click side button) and tab through.

---

## 4. Bluetooth MIDI — Practice mode

**Spec:** When a Bluetooth MIDI source is detected (CoreMIDI driver-owner contains "btmidi" or "bluetooth"), the Practice-mode chip appears, scoring is suppressed, but the sampler still triggers (so the user hears their playing).

**How to verify:**
1. Pair a BLE MIDI keyboard via Settings → Bluetooth → MIDI (or via the dedicated CoreMIDI BLE pairing flow inside another music app).
2. Open SurVibe → Play Along on Sukhkarta.
3. Confirm:
   - [ ] "Practice Mode" chip appears at top of view.
   - [ ] Pressing keys produces audible piano tone via SurVibe's sampler.
   - [ ] No NoteVerdicts increment in the scoring HUD (no "+1 correct" / "-1 missed").
4. Switch to USB MIDI keyboard (or close BLE):
   - [ ] Chip disappears.
   - [ ] Scoring resumes.

---

## 5. Tempo + loop + hand-isolation smoke

| Action | Expected | Pass? |
|--------|----------|-------|
| Set tempo slider to 50% | playback halves; metronome count-in slows | ☐ |
| Set tempo slider to 150% | playback at 1.5x | ☐ |
| Loop measures 5-8 | playback wraps from m.8 → m.5 with no count-in re-trigger | ☐ |
| Practice mode = RH, hearOtherHand = false | LH track muted in mock; user hears only RH accompaniment | ☐ |
| Stop session | `PlayAlongSession` row appears in SwiftData (verify via Profile → Recent Sessions if surfaced, or via the modelContext) | ☐ |

---

## 6. Known limitations / follow-ups

These are explicitly deferred (see Wave 5 audit). Not blockers for v1:

- Seed-content path (`mapSongDTO` from `seed-songs.json`) doesn't run PartSplitter — seed songs ship with `learnerTrackIndices == nil`. Live MXL imports are fully wired.
- `PartSplit.lyricsStaffTrackIndex` is populated but not yet consumed by the score renderer (TODO marker in PartSplitter.swift).
- `MIDIInputEvent` does not carry an `endpointID`, so per-event `shouldDropEvent(fromEndpointID:)` filtering is done at the chip-flag level instead of per-event. Sufficient for the single-endpoint v1 case.

---

## Verdict

- [ ] All gates passed → Learn-a-Song ready for wider testing.
- [ ] Failures recorded above → file follow-ups before TestFlight.

_Manual verification owner: Maheshwar Kanitkar_
