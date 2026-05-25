---
name: apple-api-verification
description: Use when writing or editing Swift code that touches any Apple framework — SwiftUI, SwiftData, AVAudioEngine/AVFoundation, CoreMIDI, StoreKit, CloudKit, CoreML, or Foundation Models — in the SurVibe app. Verifies API symbols, signatures, and iOS 26.2 availability against the offline Cupertino docs before writing, so generated code matches the modern stack instead of drifting to deprecated UIKit / ObservableObject / StoreKit 1 / completion-handler patterns.
---

# Apple API Verification (SurVibe)

SurVibe targets **iOS 26.2, Swift 6 strict concurrency, SwiftUI-only**. Model
knowledge drifts toward older APIs, so verify before writing framework code.

## Routine

1. **Identify** every Apple framework API the task will touch (types, initializers,
   modifiers, methods, property wrappers).
2. **Verify against Cupertino** for anything unfamiliar or that may predate iOS 26.2:
   - `cupertino search "<symbol or concept>"` — confirm the symbol exists, its exact
     signature, and availability.
   - Prefer the newest API for iOS 26.2. If an API predates the target, a newer
     replacement likely exists — use it.
   - If Cupertino returns nothing, say so and ask rather than guessing.
3. **Prefer the patterns pinned in CLAUDE.md:**
   - State: `@Observable` / `@State` / `@Bindable` — never `ObservableObject` / `@StateObject` / `@Published`.
   - Concurrency: `async/await`, `@MainActor` — never completion handlers or `DispatchQueue.main.async`.
   - Purchases: StoreKit 2 (`Product`, `Transaction`) — never StoreKit 1 (`SKProduct`, `SKPaymentQueue`).
   - UI: SwiftUI only — no UIKit unless explicitly requested.
4. **Audio / MIDI threading:** `AVAudioEngine` and `CoreMIDI` own their own threading
   via actors/locks (e.g. `MIDIInputManager` uses `OSAllocatedUnfairLock`, not `@MainActor`).
   Don't route real-time audio/MIDI state through app-level `@MainActor` state.
5. **Source of truth on conflict:** if Cupertino and the live SDK (what `xcodebuild`
   actually compiles) disagree, trust the SDK — it matches the installed toolchain.

## Notes

- Cupertino is an MCP server (`cupertino serve`) plus a CLI (`cupertino search`,
  `cupertino doctor`, `cupertino read <uri>`). Data lives in `~/.cupertino`.
- A PostToolUse hook (`swift-deprecation-lint.sh`) backstops this: it flags the legacy
  patterns above on every Swift edit. This skill is the proactive layer; the hook is
  the deterministic catch.
