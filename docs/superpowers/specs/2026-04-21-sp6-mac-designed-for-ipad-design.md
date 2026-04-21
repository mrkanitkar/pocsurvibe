# SP-6 — Mac (Designed for iPad) Interim Ship

> Sub-project: SP-6
> Date: 2026-04-21
> Predecessor: SP-4c (`sp-4c-accessibility-finale @ 8d5178d`, merge `ea2b60b`)
> Successor: SP-7 (native Mac port — SVAudio `#if os(iOS)` guards, `.macOS(.v15)` on all packages, `LatencyContractTests+macOS` body, Mac-idiomatic windowing/menus)
> Audit items covered: P2-8 (Designed-for-iPad interim ship)

## 1. Purpose

Deliver first-day Mac coverage via the Designed-for-iPad compatibility layer. No SVAudio port, no `#if os(macOS)` source changes, no package-platform additions. The iOS binary runs on Apple Silicon Macs as-is.

## 2. Reference grounding (verified 2026-04-21)

- **Environment check on this machine.** MacBook Air (Mac16,12), Apple M4, macOS 26.4.1, Xcode 26.3, iOS 26.2 SDK, macOS 26.2 SDK.
- **Xcode 26 enables Designed-for-iPad by default** for iOS 26 apps on Apple Silicon. `grep SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD project.pbxproj` returns zero hits yet `xcodebuild -showdestinations` lists `platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], name:My Mac`.
- **Verified build.** `xcodebuild build -destination 'platform=macOS,arch=arm64,variant=Designed for iPad' -configuration Debug CODE_SIGNING_ALLOWED=NO` → `BUILD SUCCEEDED` on `feat/sp-6-mac-designed-for-ipad @ main tip`. Only hurdle is the provisioning profile (Mac UDID `00008132-001C096434FB801C` not yet in `iOS Team Provisioning Profile: com.survibe.SurVibe`).
- **Apple docs on `ProcessInfo.isiOSAppOnMac`** (iOS 14.0+): `true` when "the process is an iOS app running on a Mac" — stable detection for Designed-for-iPad mode. Returns `false` in iPad simulator.

## 3. Scope

### 3.1 Analytics call site — `macWindowOpened`

**Files touched:**
- `SurVibe/SurVibeApp.swift` (one new initializer side-effect)

**Mechanism:**
- At app launch, detect `ProcessInfo.processInfo.isiOSAppOnMac`. When `true` AND `featureFlagStore.isEnabled(.macDestination)`, dispatch `AnalyticsManager.shared.track(.macWindowOpened)` exactly once per process.
- Guard with a `@State` "fired" flag (or a `static var hasFired = false` on `SurVibeApp`) so repeated `onAppear` calls don't re-fire the event.
- Preferred site: inside a dedicated `macWindowOpenedOnce()` helper called from `SurVibeApp.body`'s root WindowGroup `.task { ... }`.

### 3.2 `FeatureFlag.macDestination` default flip

**Files touched:**
- `Packages/SVCore/Sources/SVCore/FeatureFlags/FeatureFlag.swift` (if the default is currently `false`, flip to `true`).

**Mechanism:**
- Confirm at plan-time whether `macDestination` is already enabled by default. If not, flip the default so Mac-launch telemetry fires without requiring manual per-install toggling.
- Alternative considered: leave default `false` and toggle via debug UI only. Rejected — telemetry value requires shipping with it on.

### 3.3 `MacLaunchAnalyticsTests`

**Files touched:**
- Create: `SurVibeTests/MacLaunchAnalyticsTests.swift` (new Swift Testing suite).
- Create (small helper): `Packages/SVCore/Sources/SVCore/Platform/ProcessInfoProviding.swift` — tiny protocol that lets tests inject a mock `isiOSAppOnMac` value without touching real `ProcessInfo`.

**Mechanism:**
- Protocol: `protocol ProcessInfoProviding: Sendable { var isiOSAppOnMac: Bool { get } }`.
- Real conformance: `extension ProcessInfo: ProcessInfoProviding {}` (ProcessInfo already has `isiOSAppOnMac`).
- Injection seam: `macWindowOpenedOnce(processInfo: any ProcessInfoProviding = ProcessInfo.processInfo, analytics: any AnalyticsProviding = AnalyticsManager.shared, flags: any FeatureFlagStoring = FeatureFlagStore.shared)` — matches SP-0 D-SP0-1 nil-sentinel/default-value pattern used by `AppCommands`.
- Tests:
  - `firesOnceWhenOnMac()` — mock reports `true`, flag on → exactly one `.macWindowOpened` recorded.
  - `doesNotFireOnIPad()` — mock reports `false` → zero events.
  - `doesNotFireWhenFlagOff()` — mock reports `true`, flag off → zero events.
  - `firesExactlyOnceAcrossMultipleInvocations()` — call `macWindowOpenedOnce()` twice; verify event fires once.

### 3.4 Manual QA on this MacBook Air (M4, macOS 26.4.1)

Verified as part of merge gate. Goal: confirm no regressions when running the iOS binary on Mac.

**Steps:**
1. Fix provisioning: Xcode > SurVibe target > Signing & Capabilities > "Automatically manage signing" checked; team selected; Xcode registers Mac UDID and regenerates provisioning profile. Or: use "Sign to Run Locally" (`CODE_SIGN_IDENTITY = -`) for local dev only.
2. Build + run on "My Mac (Designed for iPad)" destination.
3. Verify each of the 4 tabs renders: Home (DoorCards), Songs (library grid), Learn (lesson list), Profile.
4. Verify play-along audio: tap a song → detail → Play → audio plays via CoreAudio through the compat layer.
5. Verify mic permission flow: tap into practice mode → `MicPermissionPrePrompt` shows → system prompt → practice session records.
6. Verify analytics event fires: observe PostHog or debug overlay that `macWindowOpened` appears once.
7. No crashes in 10-minute exploratory session.

QA results documented in merge commit.

## 4. Architecture decisions

### AD-1 — No pbxproj flip needed (Xcode 26 default)

The audit task P2-8 prescribed `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES`. Verified 2026-04-21: Xcode 26 enables this by default for iOS 26 apps on Apple Silicon without the explicit setting. `grep` of `project.pbxproj` returns zero hits yet the destination is live. No action required.

### AD-2 — `isiOSAppOnMac` as the runtime gate

Apple's documented detection API, iOS 14+. Prefers this over `#if targetEnvironment(macCatalyst)` (which isn't Designed-for-iPad — it's a different technology) or checking `UIDevice.current.userInterfaceIdiom` (which reports `.pad` on Mac since Designed-for-iPad impersonates iPad).

### AD-3 — `FeatureFlag.macDestination` default `true`

Telemetry requires the event to fire on shipped builds. Keeping the default `false` plus a debug toggle would yield zero production Mac-launch data. Note: this doesn't gate any behaviour — it just guards the analytics call. Mac support itself is always enabled.

### AD-4 — Tiny `ProcessInfoProviding` protocol in SVCore

Matches SP-0 AD-3 ("Platform interop via SVCore protocols"). One-property protocol. Enables dependency injection for unit tests without touching real `ProcessInfo`. Conforms: `extension ProcessInfo: ProcessInfoProviding {}` — zero runtime cost.

### AD-5 — Single-fire via static flag on the helper

Analytics should fire once per process. Using a `static let` or a `static nonisolated(unsafe) var` gate on the helper. Tests verify single-fire by invoking the helper twice and asserting only one event.

### AD-6 — No source changes to SVAudio / SVLearning / SVSocial / SVAdvanced

Designed-for-iPad runs the iOS binary via the compat layer — iOS AVAudioSession APIs work via emulation. No `#if os(iOS)` guards needed. Platform additions (`.macOS(.v15)` on these packages) are SP-7 territory.

## 5. Testing

### 5.1 Unit tests (Swift Testing)

`SurVibeTests/MacLaunchAnalyticsTests.swift` — 4 tests per §3.3. All run on iOS Simulator since the helper is pure Swift + protocol-injected (no Mac hardware required).

### 5.2 Regression battery

- SVCore 93/93
- Narrow SurVibeTests (LibraryFocusNavigator 8, HomeTabFocus 4, ProfileTabFocus 4, SongGridColumnCount 5, LatencyContract 3, SongLibraryViewFocus 2)
- AccessibilityAuditTests 9/9 skipped (parked)

### 5.3 Manual QA — required merge gate

Per §3.4 on actual MacBook Air hardware.

### 5.4 Latency

No audio-path changes. `LatencyContractTests.featureFlagToggleDoesNotRestartEngine` + `rotationDoesNotRestartAudioEngine` stay green. The `FeatureFlag.macDestination` default flip is a `UserDefaults.bool` read at init — doesn't touch the engine.

## 6. Out of scope → SP-7 (native Mac port)

The following items belong to SP-7 when SurVibe wants proper native Mac:

| Item | SP-7 scope |
|---|---|
| `AVAudioSession` → `#if os(iOS)` guards | SP-7 |
| `AudioSessionManager` macOS no-op path | SP-7 |
| `.macOS(.v15)` on SVAudio, SVLearning, SVSocial, SVAdvanced | SP-7 |
| `LatencyContractTests+macOS.swift` body (Mac p95 budget, 5-15 ms) | SP-7 |
| Mac-idiomatic window management, menu-bar `CommandMenu` tuning | SP-7 |
| Intel Mac support | SP-7 (may also require Catalyst) |
| 48 kHz Mac default sample rate verification in `MicPitchDetector` / `YINPitchDetector` | SP-7 |

Also out of scope for SP-6:

- CI wiring for Mac builds.
- Mac App Store distribution setup.
- Entitlements review beyond what iOS already requires.
- `Settings{}` scene activation on Mac (already `#if os(macOS)` guarded — no-op in Designed-for-iPad).

## 7. Risks

| Risk | Mitigation |
|---|---|
| Some iOS API crashes on Mac compat layer (e.g., specific AVAudioSession option unsupported) | Manual QA §3.4 covers the primary audio flow. Crashes documented as SP-7 candidates. |
| Provisioning profile gate blocks build on user's Mac | Documented fix in §3.4 step 1 (Xcode auto-signing or local-only signing). |
| `AnalyticsManager.shared` is `@MainActor`-isolated and can't be a default parameter | Use SP-0 D-SP0-1 nil-sentinel pattern (proven precedent). |
| `FeatureFlag.macDestination` default flip breaks a pre-existing test that assumes all flags default false | `FeatureFlagStoreTests` (SP-0) has a `everyFlagDefaultsToFalse` test — need to update it or rename the flag-check test. Verified at plan-time. |
| `macWindowOpened` analytics fires in iPad simulator on wrong platform check | Apple doc: `isiOSAppOnMac` returns `false` in sim. Tested by `doesNotFireOnIPad`. |

## 8. Acceptance criteria

- ✅ `xcodebuild build -destination 'platform=macOS,arch=arm64,variant=Designed for iPad'` succeeds on this MacBook Air.
- ✅ `MacLaunchAnalyticsTests` 4/4 pass on iOS Simulator.
- ✅ SVCore 93/93 + narrow SurVibeTests battery remain green (no regression from flag default flip).
- ✅ Manual QA §3.4 completed on this MacBook Air; 4 tabs render, play-along audio works, `macWindowOpened` fires once.
- ✅ `/latency-check` merge gate green; `LatencyContractTests` 3/3; p95 delta ≤ 0.5 ms.
- ✅ Zero banned-pattern introductions (grep clean on touched files).
- ✅ Tracker SP-6 row → ✅ shipped; SP-7 row added for native Mac port.

## 9. Tag + merge

- Branch: `feat/sp-6-mac-designed-for-ipad` (already created 2026-04-21 at `02df16a`).
- Tag: `sp-6-mac-designed-for-ipad` at last feat commit before merge (matches SP-4b/4c convention).
- Merge commit on `main` with `--no-ff`.

## 10. File-count budget

**New files (2):**
- `Packages/SVCore/Sources/SVCore/Platform/ProcessInfoProviding.swift` (~25 lines protocol + extension)
- `SurVibeTests/MacLaunchAnalyticsTests.swift` (~70 lines, 4 Swift Testing cases)

**Modified files (2):**
- `SurVibe/SurVibeApp.swift` (+~15 lines: `macWindowOpenedOnce(...)` helper added inline + `.task` wiring on root scene)
- `Packages/SVCore/Sources/SVCore/FeatureFlags/FeatureFlag.swift` (flip `.macDestination` default to `true` — plus a matching edit to `FeatureFlagStoreTests.everyFlagDefaultsToFalse` since that test now has one exception to document)

**Plus tracker (1):**
- `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md` (SP-6 shipped + SP-7 row added)

**Estimated totals:** 2 new + 2 modified + tracker = 5 files. Ships as 1 PR with ~5 commits.

---

*Spec author: Claude (Opus 4.7). Reviewed by: [pending — user review gate after spec-self-review].*
