---
paths:
  - "Packages/SVAudio/**"
---

# Audio Rules

## Single AVAudioEngine (WWDC 2014/2019)
- ONE `AVAudioEngine` instance via `AudioEngineManager.shared` singleton.
- NEVER create a second engine.
- Nodes: AVAudioInputNode (mic), AVAudioUnitSampler (SoundFont), AVAudioPlayerNode x2 (tanpura, metronome), main mixer.
- Engine starts ONLY when user enters practice mode, NOT at app launch.

## Pitch Detection
- Two implementations behind `PitchDetectorProtocol` (defined in `SVAudio/Pitch/PitchDetector.swift`):
  1. **AudioKitPitchDetector** — autocorrelation via `vDSP_dotpr` + `vDSP_vsmul` (primary).
  2. **YINPitchDetector** — YIN algorithm using `Accelerate/vDSP` (fallback).
- Chord detection uses `LatencyPreset` for user-configurable FFT window sizes:
  - **Ultra Fast**: 1024 samples (~23ms) — fastest response, lower frequency resolution
  - **Fast** (default): 2048 samples (~46ms) — good for C3 and above
  - **Balanced**: 4096 samples (~93ms) — full range, better accuracy
  - **Precise**: 8192 samples (~186ms) — low bass, complex chords
- Melody detection (autocorrelation) uses the engine's fixed 2048-sample buffer.
- Both return `AsyncStream<PitchResult>` (frequency, amplitude, note name, octave, cents offset, confidence).
- Shared frequency-to-note conversion in `SwarUtility.swift` using `Swar.allCases`.
- **Note:** PitchTap from SoundpipeAudioKit conflicts with single-engine pattern; re-evaluate in Sprint 2.

## Audio Session
```swift
// ALWAYS configure before starting engine
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
try session.setMode(.measurement) // accurate pitch detection
try session.setActive(true)
```

## Microphone Permission
- Request in context (first practice attempt), NOT at app launch (Apple HIG).
- Use `AVAudioApplication.requestRecordPermission()`.
- Handle denied state: show inline message + Settings deep link. SoundFont still plays.
- NEVER block the app if mic is denied.

## Haptics
```swift
// CORRECT syntax:
let heavy = UIImpactFeedbackGenerator(style: .heavy)  // sam beats
let light = UIImpactFeedbackGenerator(style: .light)   // other beats
let notification = UINotificationFeedbackGenerator()    // success/error
```

## Swar (Note) System
The `Swar` enum in `SVAudio/Models/Note.swift` defines the 12 notes of Indian classical music:

| Swar | Raw Value | MIDI Offset | Western Equivalent |
|------|-----------|-------------|-------------------|
| Sa | "Sa" | 0 | C (tonic) |
| Komal Re | "Komal Re" | 1 | Db |
| Re | "Re" | 2 | D |
| Komal Ga | "Komal Ga" | 3 | Eb |
| Ga | "Ga" | 4 | E |
| Ma | "Ma" | 5 | F |
| Tivra Ma | "Tivra Ma" | 6 | F# |
| Pa | "Pa" | 7 | G |
| Komal Dha | "Komal Dha" | 8 | Ab |
| Dha | "Dha" | 9 | A |
| Komal Ni | "Komal Ni" | 10 | Bb |
| Ni | "Ni" | 11 | B |

- Frequency calculation: `frequency(octave:referencePitch:)` — defaults to octave 4, A4 = 440 Hz.
- Sa is relative to the performer's chosen pitch (not fixed to C).

## Playback
- **TanpuraPlayer** — looped drone using `AVAudioPCMBuffer` with `.loops` option. Provides tonic reference (Sa-Pa drone).
- **MetronomePlayer** — pre-loaded click buffer with sample-accurate `AVAudioTime` scheduling. A look-ahead loop pre-schedules 4 beats on the audio timeline, eliminating wall-clock jitter.
- **SoundFontManager** — `AVAudioUnitSampler` with `loadSoundBankInstrument(at:program:bankMSB:bankLSB:)`. Piano SoundFont for note playback.
