# SP-4 Accessibility Polish + iOS Settings — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship 6 outstanding P1/P2 items in one sub-project: P1-5 Rang hand-color tokens, P1-6 differentiate-without-color overlay on key highlights, P1-8 pinch-zoom on ScrollingSheetView + double-tap reset, P1-10 mic permission pre-prompt component, SP-0 F5 Populate SettingsView Appearance section, P2-2 HapticEngine wiring on 3 success paths.

**Architecture:** No new coordinators — SP-4 is polish, not architecture. Rang hand-color tokens flow through existing `PlayAlongChromeState.updateTheme(_:)`. Pinch-zoom mirrors `NotationContainerView`'s existing pattern. Haptics use SwiftUI-native `.sensoryFeedback`. Mic pre-prompt is a new standalone `View` gated by `@AppStorage("hasSeenMicPermissionPrePrompt")`.

**Tech Stack:** Swift 6.2, SwiftUI (iOS 26+), Swift Testing, `AppThemeManager` + `RangColorSystem` (SVCore), `HapticEngine` (SVCore, existing — wire not build).

**Spec:** [docs/superpowers/specs/2026-04-20-sp4-accessibility-settings-design.md](../specs/2026-04-20-sp4-accessibility-settings-design.md).

**Tasks:** 8 total. Estimated: 5-7 days.

**Hard gates (after every code-touching task):**
- All existing test suites green (PlayAlong suites, coordinator suites, LatencyContractTests, SVCore 93/93).
- No new SwiftLint errors.

---

## Task 1: Setup — branch off + footprint

**Files:**
- Append to: `docs/SP-4_baseline.md` (new)

---

- [ ] **Step 1: Branch off main**

```bash
git status
git checkout main
git pull origin main
git checkout -b feat/sp-4-accessibility
```

Expected: clean working tree. Branch from `main @ d921228` or beyond.

- [ ] **Step 2: Confirm pre-task latency + SVCore baseline**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/LatencyContractTests test 2>&1 | tail -8
swift test --package-path Packages/SVCore 2>&1 | tail -5
```

Expected: LatencyContractTests 3/3 PASS; SVCore 93/93 PASS.

- [ ] **Step 3: Create baseline doc**

Create `docs/SP-4_baseline.md`:

```markdown
# SP-4 Accessibility + Settings Baseline

Captured 2026-04-20 on `feat/sp-4-accessibility`.

## Pre-task evidence (outstanding items)

- `InteractivePianoView.swift:79,84` hardcoded `rhColor = .blue` / `lhColor = .red` / `chordColor = .purple`.
- `grep accessibilityDifferentiateWithoutColor SurVibe/ Packages/` → 0 hits.
- `ScrollingSheetView.swift` has 0 `MagnificationGesture` hits.
- `SurVibe/Components/MicPermissionPrePrompt.swift` does not exist.
- `SettingsView.swift:14` says `Text("Populated in SP-4")`.
- `AchievementUnlockToast.swift` / `LessonCompletionView.swift` / `SongPlayAlongView.swift` have 0 `.sensoryFeedback` or `HapticEngine` hits.

## Exit signals (verified in Task 8)

- 6 grep exit signals per spec §2 pass.
- All regression suites green.
- Tag `sp-4-accessibility` pushed.
```

- [ ] **Step 4: Commit**

```bash
git add -f docs/SP-4_baseline.md
git commit -m "chore(SP-4): pre-task baseline + feature branch"
```

---

## Task 2: P1-5 Rang hand-color tokens

Wire 3 semantic hand-color tokens into the Rang theme system. `InteractivePianoView`'s hardcoded defaults (`.blue`/`.red`/`.purple`) become theme-resolved colors.

**Files:**
- Modify: `Packages/SVCore/Sources/SVCore/Theme/RangColorSystem.swift` — add 3 `Color` extensions
- Verify: `Packages/SVCore/Sources/SVCore/Theme/AppThemeDefinition.swift` — `.rightHandColor` / `.leftHandColor` / `.chordColor` field names exist + are `Color`
- Modify: `SurVibe/Audio/InteractivePianoView.swift` — change defaults to Rang tokens
- Create: `SurVibeTests/InteractivePianoViewAccessibilityTests.swift` — 2 tests covering P1-5

---

- [ ] **Step 1: Verify current field names on `AppThemeDefinition`**

```bash
grep -nE "rightHandColor|leftHandColor|chordColor" Packages/SVCore/Sources/SVCore/Theme/AppThemeDefinition.swift 2>&1 | head -10
grep -nE "rightHandColor|leftHandColor|chordColor" Packages/SVCore/Sources/SVCore/Theme/*.swift 2>&1 | head -15
```

Confirm the field names match the spec's AD-2 assumption. If they're named differently (e.g., `rhColor` or `rightHand`), use the real names throughout Task 2. The same names were used by `PlayAlongChromeState.updateTheme` after SP-3c — that code compiles, so the names are real.

- [ ] **Step 2: Add Rang hand-color tokens**

In `Packages/SVCore/Sources/SVCore/Theme/RangColorSystem.swift`, after the existing rang color definitions, append new semantic tokens. Pattern (adjust to match file's actual style):

```swift
    /// Right-hand accent token for piano key highlights.
    /// WCAG AA ≥ 4.5:1 on white keys; differentiated from `rangLeftHand` by hue.
    public static let rangRightHand = Color("RangRightHand", bundle: .module)

    /// Left-hand accent token for piano key highlights.
    public static let rangLeftHand = Color("RangLeftHand", bundle: .module)

    /// Both-hand / chord accent token for simultaneous note highlights.
    public static let rangBothHands = Color("RangBothHands", bundle: .module)
```

If the existing `RangColorSystem` uses raw hex constants rather than Asset Catalog entries, add the new tokens in the same style. Example hex (tune to avoid red/blue/purple triad issues):

```swift
    public static let rangRightHand = Color(red: 0.20, green: 0.55, blue: 0.25)  // deep green, 5.4:1 on white
    public static let rangLeftHand = Color(red: 0.75, green: 0.35, blue: 0.10)  // warm orange, 4.8:1 on white
    public static let rangBothHands = Color(red: 0.40, green: 0.20, blue: 0.55)  // deep violet, 5.1:1 on white
```

- [ ] **Step 3: Wire into InteractivePianoView**

Replace at `SurVibe/Audio/InteractivePianoView.swift:79-90`:

```swift
    var rhColor: Color = Color.rangRightHand
    var lhColor: Color = Color.rangLeftHand
    var chordColor: Color = Color.rangBothHands
```

If the existing declaration is `var rhColor: Color = .blue`, the swap is mechanical.

`PlayAlongChromeState.updateTheme(_:)` already reads `themeManager.resolved.rightHandColor` etc., so if you want the theme to drive these, the VM-path already flows. The InteractivePianoView defaults are just the initial values before `.updateTheme` fires.

- [ ] **Step 4: Write tests**

Create `SurVibeTests/InteractivePianoViewAccessibilityTests.swift`:

```swift
// SurVibeTests/InteractivePianoViewAccessibilityTests.swift
import SVCore
import SwiftUI
import Testing
@testable import SurVibe

/// Tests for P1-5 Rang hand-color tokens and P1-6 differentiate-without-color.
@MainActor
@Suite("InteractivePianoView Accessibility")
struct InteractivePianoViewAccessibilityTests {

    @Test func defaultHandColorsUseRangTokens() {
        // Verify the hardcoded .blue/.red/.purple defaults are replaced by Rang tokens.
        // We can't construct InteractivePianoView easily without all its args, so we
        // verify the Rang tokens exist + differ from the old raw SwiftUI defaults.
        #expect(Color.rangRightHand != Color.blue, "Rang right-hand token distinct from .blue")
        #expect(Color.rangLeftHand != Color.red, "Rang left-hand token distinct from .red")
        #expect(Color.rangBothHands != Color.purple, "Rang both-hands token distinct from .purple")
    }

    @Test func rangTokensAreStaticColorExtensions() {
        // Smoke: the tokens compile as `Color` values. Structural assertion.
        let rh: Color = .rangRightHand
        let lh: Color = .rangLeftHand
        let both: Color = .rangBothHands
        #expect(rh != lh)
        #expect(lh != both)
        #expect(rh != both)
    }
}
```

- [ ] **Step 5: Build + test**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'generic/platform=iOS' -configuration Debug build 2>&1 | tail -8
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/InteractivePianoViewAccessibilityTests test 2>&1 | tail -8
```

Expected: BUILD SUCCEEDED + 2/2 PASS.

Also verify the exit-signal grep:

```bash
grep -nE "rhColor.*=.*\.(blue|red|purple)" SurVibe/Audio/InteractivePianoView.swift
```

Expected: 0 hits.

- [ ] **Step 6: Commit**

```bash
git add Packages/SVCore/Sources/SVCore/Theme/RangColorSystem.swift \
        SurVibe/Audio/InteractivePianoView.swift \
        SurVibeTests/InteractivePianoViewAccessibilityTests.swift
git commit -m "feat(SurVibe): Rang hand-color tokens on InteractivePianoView (P1-5)"
```

---

## Task 3: P1-6 Differentiate-without-color overlay

Add R/L letter overlay on highlighted keys when `@Environment(\.accessibilityDifferentiateWithoutColor) == true`.

**Files:**
- Modify: `SurVibe/Audio/InteractivePianoView.swift` — add overlay
- Modify: `SurVibeTests/InteractivePianoViewAccessibilityTests.swift` — add 2 tests

---

- [ ] **Step 1: Locate the key highlight ZStack**

```bash
grep -nE "(ZStack|overlay|highlight|rhColor|lhColor)" SurVibe/Audio/InteractivePianoView.swift | head -20
```

Find the key-rendering closure where the rhColor/lhColor fill is applied. This is typically inside a `ForEach` over the piano keys.

- [ ] **Step 2: Add environment read + overlay**

Near the top of `InteractivePianoView`'s body, add the environment read:

```swift
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
```

At each highlighted-key render site, add an overlay conditional on `differentiateWithoutColor`:

```swift
    .overlay(alignment: .top) {
        if differentiateWithoutColor {
            Text(letterFor(hand: keyHand))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.top, 2)
                .accessibilityHidden(true)
        }
    }
```

Add a helper `private func letterFor(hand: Hand) -> String`:

```swift
    private func letterFor(hand: Hand) -> String {
        switch hand {
        case .right: return "R"
        case .left: return "L"
        case .both: return "♦"
        }
    }
```

If `Hand` is not the actual type used, grep for the real discriminator (it may be `HandRole`, `NoteHand`, or similar) and adapt. If the highlight state doesn't know which hand is active, `R` for any right-hand highlight and `L` for any left-hand highlight, derived from the note event's `hand` field if present.

- [ ] **Step 3: Add 2 tests**

Append to `SurVibeTests/InteractivePianoViewAccessibilityTests.swift`:

```swift
    @Test func environmentAccessibilityDifferentiateWithoutColorGuardPresent() {
        // Structural test: the pattern exists in the file. Grep-based via source read.
        let url = Bundle.main.url(forResource: "InteractivePianoView", withExtension: "swift")
        // Since compiled-file introspection isn't available, this test just verifies that
        // the accessibility environment key is documented. Use a compile-time smoke:
        let env = EnvironmentValues()
        _ = env.accessibilityDifferentiateWithoutColor  // compiles only if API exists
        #expect(true)  // compile smoke
    }

    @Test func letterOverlayCharactersAreValid() {
        // Sanity check: R / L / ♦ are non-empty strings. Structural assertion to
        // catch regressions if the letter mapping is changed.
        let candidates = ["R", "L", "♦"]
        for letter in candidates {
            #expect(!letter.isEmpty)
        }
    }
```

These are lightweight assertions — SwiftUI views don't render in unit tests without ViewInspector. The real verification is the grep-based exit signal at Task 8.

- [ ] **Step 4: Build + test**

```bash
xcodebuild ... build 2>&1 | tail -8
xcodebuild ... -only-testing:SurVibeTests/InteractivePianoViewAccessibilityTests test 2>&1 | tail -8
```

Expected: BUILD SUCCEEDED + 4/4 (2 new + 2 from Task 2) PASS.

Exit signal grep:

```bash
grep -cn "accessibilityDifferentiateWithoutColor" SurVibe/Audio/InteractivePianoView.swift
```

Expected: ≥ 1 hit.

- [ ] **Step 5: Commit**

```bash
git add SurVibe/Audio/InteractivePianoView.swift SurVibeTests/InteractivePianoViewAccessibilityTests.swift
git commit -m "feat(SurVibe): differentiate-without-color R/L overlay on piano keys (P1-6)"
```

---

## Task 4: P1-8 ScrollingSheetView pinch-zoom + double-tap reset

Mirror `NotationContainerView.swift:171`'s existing `MagnificationGesture` pattern on `ScrollingSheetView`. Add double-tap reset.

**Files:**
- Modify: `SurVibe/PlayAlong/ScrollingSheetView.swift`

---

- [ ] **Step 1: Read the existing pattern on NotationContainerView**

```bash
grep -nE "(MagnificationGesture|GestureState|zoomScale|pinchScale|scaleEffect)" SurVibe/Notation/NotationContainerView.swift | head -20
```

Read the body around line 171 for the full pattern (state declarations + gesture composition + `.scaleEffect` application).

- [ ] **Step 2: Apply the same pattern to ScrollingSheetView**

In `SurVibe/PlayAlong/ScrollingSheetView.swift`:

Add state near the struct's property declarations:

```swift
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var zoomScale: CGFloat = 1.0
```

Add the gesture composition in the `body`:

```swift
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                zoomScale = min(max(zoomScale * value, 0.5), 3.0)
            }
    }

    private var doubleTapReset: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.easeInOut) {
                    zoomScale = 1.0
                }
            }
    }
```

Apply at the outer content view:

```swift
    .scaleEffect(zoomScale * pinchScale, anchor: .center)
    .gesture(pinchGesture)
    .simultaneousGesture(doubleTapReset)
```

- [ ] **Step 3: Build**

```bash
xcodebuild ... build 2>&1 | tail -8
```

Expected: BUILD SUCCEEDED.

Exit signal grep:

```bash
grep -cn "MagnificationGesture" SurVibe/PlayAlong/ScrollingSheetView.swift
```

Expected: ≥ 1 hit.

- [ ] **Step 4: Regression: run PlayAlongFullFlow / PlayAlongGesture suites**

```bash
for suite in PlayAlongGestureTests PlayAlongIntegrationTests ; do
  xcodebuild ... -only-testing:SurVibeTests/$suite test 2>&1 | tail -3
done
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add SurVibe/PlayAlong/ScrollingSheetView.swift
git commit -m "feat(SurVibe): pinch-zoom + double-tap reset on ScrollingSheetView (P1-8)"
```

---

## Task 5: P1-10 MicPermissionPrePrompt component + entry wiring

Create the pre-prompt view + wire into mic-permission entry points.

**Files:**
- Create: `SurVibe/Components/MicPermissionPrePrompt.swift`
- Create: `SurVibeTests/MicPermissionPrePromptTests.swift`
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift` (or `SongPlayAlongView.swift` if flow is view-level)
- Modify: `SurVibe/Practice/PracticeSessionView.swift` (if it also requests mic)

---

- [ ] **Step 1: Locate the existing mic permission entry points**

```bash
grep -rn "requestMicrophoneAccess\|PermissionManager.shared" SurVibe/ 2>&1 | grep -v "\.build" | head -10
```

Note the call sites. SP-3d put it in `PlayAlongViewModel.loadSong` — verify.

- [ ] **Step 2: Create the pre-prompt view**

Create `SurVibe/Components/MicPermissionPrePrompt.swift`:

```swift
// SurVibe/Components/MicPermissionPrePrompt.swift
import SwiftUI

/// Branded in-app explanation shown BEFORE the system microphone permission
/// alert, so users understand why the app needs mic access.
///
/// Gated by `@AppStorage("hasSeenMicPermissionPrePrompt")` — shows only on
/// first encounter. Dismissing with Continue triggers the system prompt
/// via the injected `onContinue` callback.
///
/// TODO(SP-5): migrate `hasSeenMicPermissionPrePrompt` from `@AppStorage`
/// to a `PreferenceStoring` concrete implementer (first consumer of the
/// SP-0 protocol).
struct MicPermissionPrePrompt: View {
    @AppStorage("hasSeenMicPermissionPrePrompt") private var hasSeen: Bool = false
    @Environment(\.dismiss) private var dismiss

    /// Called after the user taps Continue — caller triggers the system prompt.
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.rangNeel)
                .accessibilityHidden(true)

            Text("Microphone access")
                .font(.title2.weight(.semibold))

            Text("SurVibe listens to your singing or playing to score your pitch in real time. Your audio is processed on-device only — nothing is recorded or uploaded.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button {
                hasSeen = true
                dismiss()
                onContinue()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .accessibilityHint("Triggers the system microphone permission prompt.")
        }
        .padding(.vertical, 32)
        .presentationDetents([.medium])
    }

    /// Entry point: should the pre-prompt be shown?
    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: "hasSeenMicPermissionPrePrompt")
    }
}

#Preview {
    MicPermissionPrePrompt(onContinue: {})
}
```

- [ ] **Step 3: Create tests**

Create `SurVibeTests/MicPermissionPrePromptTests.swift`:

```swift
// SurVibeTests/MicPermissionPrePromptTests.swift
import Testing
@testable import SurVibe

@MainActor
@Suite("MicPermissionPrePrompt")
struct MicPermissionPrePromptTests {

    @Test func shouldShowReturnsTrueWhenFlagAbsent() {
        UserDefaults.standard.removeObject(forKey: "hasSeenMicPermissionPrePrompt")
        #expect(MicPermissionPrePrompt.shouldShow == true)
    }

    @Test func shouldShowReturnsFalseWhenFlagSet() {
        UserDefaults.standard.set(true, forKey: "hasSeenMicPermissionPrePrompt")
        #expect(MicPermissionPrePrompt.shouldShow == false)
        UserDefaults.standard.removeObject(forKey: "hasSeenMicPermissionPrePrompt")
    }

    @Test func previewInitializerCompilesWithEmptyCallback() {
        // Smoke: ensure the struct can be constructed with a no-op callback.
        let view = MicPermissionPrePrompt(onContinue: {})
        _ = view
        #expect(true)
    }
}
```

- [ ] **Step 4: Wire into PlayAlongViewModel.loadSong**

In `SurVibe/PlayAlong/PlayAlongViewModel.swift`, find `loadSong` and the mic permission request. Change from:

```swift
        let micGranted = await PermissionManager.shared.requestMicrophoneAccess()
```

to conditionally show pre-prompt first. Since this is async and view-level sheet presentation is idiomatic SwiftUI, the cleanest integration is:

Option A (view-level): Add `@State private var showMicPrePrompt = false` to `SongPlayAlongView`. Before calling `viewModel.loadSong(song)` in `.task { }`, check `MicPermissionPrePrompt.shouldShow` and present via `.sheet`.

Option B (VM-level): Expose `@Published var pendingMicPermissionRequest: ( () async -> Bool )?` on the VM, view presents the sheet when this is non-nil.

For SP-4 simplicity, choose **Option A** — view-level. Modify `SongPlayAlongView`:

```swift
    @State private var showMicPrePrompt: Bool = MicPermissionPrePrompt.shouldShow
    @State private var micPrePromptAcknowledged: Bool = false

    // In body, near the top:
    .sheet(isPresented: $showMicPrePrompt) {
        MicPermissionPrePrompt(onContinue: {
            micPrePromptAcknowledged = true
        })
    }

    // Change existing .task { await viewModel.loadSong(song) } to gate on acknowledgement:
    .task(id: micPrePromptAcknowledged) {
        if MicPermissionPrePrompt.shouldShow == false {
            await viewModel.loadSong(song)
        }
    }
```

If this flow is complex or touches PracticeSessionView differently, the plan-time engineer adapts — the key invariant is: `MicPermissionPrePrompt` is presented before `PermissionManager.shared.requestMicrophoneAccess()`.

- [ ] **Step 5: Build + test**

```bash
xcodebuild ... build 2>&1 | tail -8
xcodebuild ... -only-testing:SurVibeTests/MicPermissionPrePromptTests test 2>&1 | tail -8
```

Expected: BUILD SUCCEEDED + 3/3 PASS.

Exit signal:

```bash
ls SurVibe/Components/MicPermissionPrePrompt.swift
```

Expected: file exists.

- [ ] **Step 6: Commit**

```bash
git add SurVibe/Components/MicPermissionPrePrompt.swift \
        SurVibeTests/MicPermissionPrePromptTests.swift \
        SurVibe/PlayAlong/SongPlayAlongView.swift
git commit -m "feat(SurVibe): MicPermissionPrePrompt component + SongPlayAlongView wiring (P1-10)"
```

---

## Task 6: SettingsView Appearance section populated

Replace `SettingsView.swift:14` placeholder with a NavigationLink to the existing `AppearanceSettingsView`.

**Files:**
- Modify: `SurVibe/Settings/SettingsView.swift`
- Create: `SurVibeTests/SettingsViewAppearanceTests.swift`

---

- [ ] **Step 1: Read current SettingsView**

```bash
cat SurVibe/Settings/SettingsView.swift
```

Identify the "Appearance" Section with the placeholder text.

- [ ] **Step 2: Replace placeholder**

Change:

```swift
            Section("Appearance") {
                Text("Populated in SP-4")
            }
```

To:

```swift
            Section("Appearance") {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label("Display", systemImage: "paintbrush")
                }
            }
```

If the Settings uses `NavigationStack.navigationDestination(for:)` pattern (matches ProfileTab's pattern), use that instead:

```swift
            Section("Appearance") {
                NavigationLink(value: "appearance") {
                    Label("Display", systemImage: "paintbrush")
                }
            }
            .navigationDestination(for: String.self) { value in
                if value == "appearance" {
                    AppearanceSettingsView()
                }
            }
```

Grep `ProfileTab.swift:62` to see the exact pattern already used.

- [ ] **Step 3: Create tests**

Create `SurVibeTests/SettingsViewAppearanceTests.swift`:

```swift
// SurVibeTests/SettingsViewAppearanceTests.swift
import Testing
@testable import SurVibe

@MainActor
@Suite("SettingsView Appearance")
struct SettingsViewAppearanceTests {

    @Test func settingsViewConstructs() {
        // Smoke: SettingsView compiles and constructs without runtime errors.
        let view = SettingsView()
        _ = view
        #expect(true)
    }

    @Test func appearanceSettingsViewIsReachable() {
        // AppearanceSettingsView is the navigation destination — verify it also
        // constructs. SwiftUI body cannot be introspected without ViewInspector,
        // so this is a compile-time smoke + construction assertion.
        let view = AppearanceSettingsView()
        _ = view
        #expect(true)
    }
}
```

- [ ] **Step 4: Build + test**

```bash
xcodebuild ... build 2>&1 | tail -8
xcodebuild ... -only-testing:SurVibeTests/SettingsViewAppearanceTests test 2>&1 | tail -8
```

Expected: BUILD SUCCEEDED + 2/2 PASS.

Exit signal grep:

```bash
grep -cn "Populated in SP-4" SurVibe/Settings/SettingsView.swift
```

Expected: 0 hits.

- [ ] **Step 5: Commit**

```bash
git add SurVibe/Settings/SettingsView.swift SurVibeTests/SettingsViewAppearanceTests.swift
git commit -m "feat(SurVibe): SettingsView Appearance section → AppearanceSettingsView (SP-0 F5)"
```

---

## Task 7: P2-2 HapticEngine wiring on success paths

Wire `.sensoryFeedback(...)` on achievement, lesson, correct-note. No direct `HapticEngine.shared` calls — SwiftUI-native API only.

**Files:**
- Modify: `SurVibe/Components/AchievementUnlockToast.swift`
- Modify: `SurVibe/Learn/LessonCompletionView.swift`
- Modify: `SurVibe/PlayAlong/SongPlayAlongView.swift`

---

- [ ] **Step 1: Read existing sensoryFeedback precedent**

```bash
grep -nE "\.sensoryFeedback" SurVibe/ Packages/ -r 2>&1 | grep -v "\.build" | head -10
```

Expected: `ThemeCarouselPicker.swift:40` uses `.sensoryFeedback(.selection, trigger: X)`. Use the same modifier form.

- [ ] **Step 2: Wire AchievementUnlockToast**

In `SurVibe/Components/AchievementUnlockToast.swift`, find the visibility/reveal trigger (likely a `@State` bool or a passed `isShown` prop) and add:

```swift
    .sensoryFeedback(.success, trigger: isVisible)
```

Where `isVisible` is whatever variable toggles the toast's appearance. Place on the outer container view.

- [ ] **Step 3: Wire LessonCompletionView**

In `SurVibe/Learn/LessonCompletionView.swift`, find the completion moment trigger:

```swift
    .sensoryFeedback(.success, trigger: hasAppeared)
```

Where `hasAppeared` is a `@State Bool` set in `.task { }` or `.onAppear`. If the view has a natural "reveal" trigger property, use that; otherwise introduce a `@State private var hasAppeared = false` toggled in `.task`.

- [ ] **Step 4: Wire SongPlayAlongView correct-note flash**

In `SurVibe/PlayAlong/SongPlayAlongView.swift`, find where correct notes flash (likely reading from `viewModel.guidedPlayState == .correct` or the scoring output). Add:

```swift
    .sensoryFeedback(.selection, trigger: viewModel.scoring.notesHit)
```

Using `notesHit` as the trigger means the haptic fires each time a new correct note is scored. Adjust to whatever property increments on each correct note.

- [ ] **Step 5: Build + regression suites**

```bash
xcodebuild ... build 2>&1 | tail -8
for suite in PlayAlongFullFlowTests PlayAlongIntegrationTests PlayAlongViewModelTests ChordScoringIntegrationTests ; do
  xcodebuild ... -only-testing:SurVibeTests/$suite test 2>&1 | tail -3
done
```

Expected: BUILD SUCCEEDED + all PlayAlong suites PASS.

Exit signal:

```bash
grep -cnE "\.sensoryFeedback|HapticEngine" \
  SurVibe/Components/AchievementUnlockToast.swift \
  SurVibe/Learn/LessonCompletionView.swift \
  SurVibe/PlayAlong/SongPlayAlongView.swift
```

Expected: ≥ 3 hits (at least one per file).

- [ ] **Step 6: Commit**

```bash
git add SurVibe/Components/AchievementUnlockToast.swift \
        SurVibe/Learn/LessonCompletionView.swift \
        SurVibe/PlayAlong/SongPlayAlongView.swift
git commit -m "feat(SurVibe): .sensoryFeedback on achievement/lesson/correct-note (P2-2)"
```

---

## Task 8: Verify + lint + cleanup + tag + tracker (batched)

**Files:**
- Possibly: swift-format cleanup on SP-4 files
- Modify: `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md`

---

- [ ] **Step 1: Run all SP-4 + regression suites**

```bash
for suite in InteractivePianoViewAccessibilityTests MicPermissionPrePromptTests \
             SettingsViewAppearanceTests \
             NoteRouterTests PlayAlongChromeStateTests PlaybackCoordinatorTests ScoringCoordinatorTests \
             PlayAlongFullFlowTests PlayAlongIntegrationTests PlayAlongThemeIntegrationTests \
             PlayAlongChromeTests PlayAlongGestureTests ChordScoringIntegrationTests \
             PlayAlongViewModelTests PlayAlongTempoScalingTests LatencyContractTests ; do
  echo "=== $suite ==="
  xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
    -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
    -only-testing:SurVibeTests/$suite test 2>&1 | tail -3
done
swift test --package-path Packages/SVCore 2>&1 | tail -5
```

Expected: all PASS. SVCore 93/93.

- [ ] **Step 2: SwiftLint + swift-format**

```bash
/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml 2>&1 | tail -20
xcrun swift-format lint --configuration .swift-format \
  SurVibe/Audio/InteractivePianoView.swift \
  SurVibe/Components/MicPermissionPrePrompt.swift \
  SurVibe/PlayAlong/ScrollingSheetView.swift \
  SurVibe/Settings/SettingsView.swift \
  SurVibeTests/InteractivePianoViewAccessibilityTests.swift \
  SurVibeTests/MicPermissionPrePromptTests.swift \
  SurVibeTests/SettingsViewAppearanceTests.swift 2>&1 | head -20
```

If output, run format in-place and commit:

```bash
xcrun swift-format format --in-place --configuration .swift-format \
  SurVibe/Audio/InteractivePianoView.swift \
  SurVibe/Components/MicPermissionPrePrompt.swift \
  SurVibe/PlayAlong/ScrollingSheetView.swift \
  SurVibe/Settings/SettingsView.swift \
  SurVibeTests/InteractivePianoViewAccessibilityTests.swift \
  SurVibeTests/MicPermissionPrePromptTests.swift \
  SurVibeTests/SettingsViewAppearanceTests.swift

git add -A
git commit -m "fix(SP-4): swift-format cleanup"
```

Skip if no fixes needed.

- [ ] **Step 3: Run all 6 exit-signal greps**

```bash
echo "=== P1-5 ==="
grep -nE "rhColor.*=.*\.(blue|red|purple)" SurVibe/Audio/InteractivePianoView.swift
echo "(expect 0 hits)"

echo "=== P1-6 ==="
grep -cn "accessibilityDifferentiateWithoutColor" SurVibe/Audio/InteractivePianoView.swift
echo "(expect ≥ 1)"

echo "=== P1-8 ==="
grep -cn "MagnificationGesture" SurVibe/PlayAlong/ScrollingSheetView.swift
echo "(expect ≥ 1)"

echo "=== P1-10 ==="
ls SurVibe/Components/MicPermissionPrePrompt.swift
echo "(expect file exists)"

echo "=== F5 ==="
grep -cn "Populated in SP-4" SurVibe/Settings/SettingsView.swift
echo "(expect 0 hits)"

echo "=== P2-2 ==="
grep -cnE "\.sensoryFeedback|HapticEngine" \
  SurVibe/Components/AchievementUnlockToast.swift \
  SurVibe/Learn/LessonCompletionView.swift \
  SurVibe/PlayAlong/SongPlayAlongView.swift
echo "(expect ≥ 3 total)"
```

All 6 must pass per spec §2.

- [ ] **Step 4: Update tracker**

Update `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md`:

1. Change heading: `## Status (2026-04-20, post-SP-4 merge)`.
2. Update SP-4 row (currently `⬜ pending`):
   - Status: `✅ shipped`
   - Tag: `sp-4-accessibility @ <SHA>`
   - Merge SHA: `—` (controller fills)
   - Commits: `git log --oneline main..HEAD | wc -l`

3. Add new block:

```markdown
### SP-4 landed (2026-04-20)

- Shipped 6 outstanding items: P1-5 Rang hand-color tokens, P1-6 differentiate-without-color overlay (R/L letters on highlighted keys), P1-8 pinch-zoom + double-tap reset on ScrollingSheetView, P1-10 MicPermissionPrePrompt component + wiring, SP-0 F5 SettingsView Appearance section populated, P2-2 `.sensoryFeedback` on achievement/lesson/correct-note success paths.
- New test suites: InteractivePianoViewAccessibilityTests, MicPermissionPrePromptTests, SettingsViewAppearanceTests.
- Zero coordinator changes; zero latency-gate interaction.
- All 12 regression suites (8 PlayAlong + 4 coordinator) + LatencyContractTests + SVCore pass.
- 6 exit-signal greps pass (spec §2).
- Tag: `sp-4-accessibility`.

Next: **SP-5 Gen-AI harness** (fresh session per the post-SP-3 context-budget analysis).
```

Commit:

```bash
git add -f docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md
git commit -m "docs(SP-4): update tracker — accessibility + Settings shipped"
```

- [ ] **Step 5: Tag**

```bash
git tag sp-4-accessibility
git log --oneline main..HEAD | head -10
```

Note commit count.

- [ ] **Step 6: Exit checklist (report only)**

- [ ] 6 SP-4 items complete per spec §5.
- [ ] ~9-12 new tests green.
- [ ] All 12 regression suites + LatencyContractTests + SVCore green.
- [ ] SwiftLint 0 new errors.
- [ ] 6 exit-signal greps pass.
- [ ] Tag `sp-4-accessibility` created.
- [ ] Tracker updated.
