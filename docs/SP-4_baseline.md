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
