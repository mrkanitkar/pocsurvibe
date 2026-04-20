# SP-4b — Accessibility Remainder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship audit items P2-6 (arrow-key card nav), P2-12 (sheet detents), P2-13 (TabView selection haptic) behind one merge.

**Architecture:** UI-only, main-thread-only additions. One pure helper type (`LibraryFocusNavigator`) with index-math, then wiring into two library views. Sheet detents added at content-view level per HIG. One-line haptic on root TabView.

**Tech Stack:** Swift 6, SwiftUI (iOS 26+), Swift Testing (`#expect`), existing `@FocusState` / `.focused(...)` / `.onKeyPress(...)`, `.presentationDetents` / `.presentationDragIndicator`, `.sensoryFeedback(.selection, trigger:)`.

**Spec:** [docs/superpowers/specs/2026-04-20-sp4b-accessibility-remainder-design.md](../specs/2026-04-20-sp4b-accessibility-remainder-design.md)

**Branch:** `feat/sp-4b-accessibility-remainder` (already created at spec commit `9e1e619`).

---

## File Structure

| Kind | Path | Purpose |
|---|---|---|
| Create | `SurVibe/Navigation/LibraryFocusNavigator.swift` | Pure enum with `nextIndex(for:currentIndex:count:columns:)` static func + `FocusDirection` nested enum. |
| Create | `SurVibeTests/LibraryFocusNavigatorTests.swift` | 8 Swift Testing cases covering row/column/edge math. |
| Modify | `SurVibe/Learn/LessonLibraryView.swift` | Add `.onKeyPress(keys:)` for arrows, `.onAppear` initial focus. |
| Modify | `SurVibe/Songs/SongLibraryView.swift` | Add `.onKeyPress(keys:)` for 4 arrows, `.onAppear` initial focus, detents on 3 sheet contents. |
| Modify | `SurVibe/Songs/SongImportSheet.swift` | Add `[.large]` detent on body + `[.medium]` + grabber on nested warnings sheet. |
| Modify | `SurVibe/Songs/SongEditView.swift` | Add `[.large]` detent on body + `[.medium]` + grabber on nested warnings sheet. |
| Modify | `SurVibe/ContentView.swift` | Add `.sensoryFeedback(.selection, trigger: selectedTab)` after `.tabViewStyle(.sidebarAdaptable)`. |

---

## Task 1: `LibraryFocusNavigator` — TDD

**Files:**
- Create: `SurVibe/Navigation/LibraryFocusNavigator.swift`
- Test: `SurVibeTests/LibraryFocusNavigatorTests.swift`

- [ ] **Step 1.1: Write the failing tests**

Create `SurVibeTests/LibraryFocusNavigatorTests.swift`:

```swift
import Testing
@testable import SurVibe

/// Index-math tests for `LibraryFocusNavigator`. Pure function, no UI.
struct LibraryFocusNavigatorTests {
    @Test
    func downArrowFromFirstItemAdvancesOneRow() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 0, count: 6, columns: 2
        )
        #expect(result == 2)
    }

    @Test
    func downArrowFromLastRowReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 4, count: 6, columns: 2
        )
        #expect(result == nil)
    }

    @Test
    func rightArrowFromEndOfRowReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .right, currentIndex: 1, count: 6, columns: 2
        )
        #expect(result == nil)
    }

    @Test
    func leftArrowFromStartOfRowReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .left, currentIndex: 0, count: 6, columns: 2
        )
        #expect(result == nil)
    }

    @Test
    func linearDownOnOneColumnList() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 2, count: 5, columns: 1
        )
        #expect(result == 3)
    }

    @Test
    func linearUpFromZeroReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .up, currentIndex: 0, count: 5, columns: 1
        )
        #expect(result == nil)
    }

    @Test
    func downArrowFromPartialLastRowReturnsNil() {
        // 5 items in a 2-column grid: rows are [0,1], [2,3], [4]. Index 4 is last-row; down clamps.
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 4, count: 5, columns: 2
        )
        #expect(result == nil)
    }

    @Test
    func rightArrowFromLastItemReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .right, currentIndex: 5, count: 6, columns: 2
        )
        #expect(result == nil)
    }
}
```

- [ ] **Step 1.2: Run tests — expect compile failure (type doesn't exist yet)**

```bash
xcodebuild test -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/LibraryFocusNavigatorTests 2>&1 | tail -30
```

Expected: build fails with "cannot find 'LibraryFocusNavigator' in scope".

- [ ] **Step 1.3: Create `LibraryFocusNavigator.swift`**

Create `SurVibe/Navigation/LibraryFocusNavigator.swift`:

```swift
import Foundation

/// Pure index-math helper for hardware-keyboard arrow-key navigation
/// across a single-column list or a fixed-width grid.
///
/// Used by `LessonLibraryView` (columns = 1) and `SongLibraryView` (columns = 2)
/// to compute the next focused index when the user presses an arrow key.
/// Returns `nil` at grid edges (no wrap-around).
enum LibraryFocusNavigator {
    /// Direction in which focus should move.
    enum FocusDirection {
        case up, down, left, right
    }

    /// Computes the next focused index after an arrow-key press.
    ///
    /// Math assumes row-major ordering: index = row * columns + col.
    /// Returns `nil` if the move would leave the grid (edge clamp, no wrap).
    ///
    /// - Parameters:
    ///   - direction: Which arrow key was pressed.
    ///   - currentIndex: Index of the currently focused item.
    ///   - count: Total item count.
    ///   - columns: Grid column count. `1` for a linear list.
    /// - Returns: New index to focus, or `nil` if the move is a no-op at an edge.
    static func nextIndex(
        for direction: FocusDirection,
        currentIndex: Int,
        count: Int,
        columns: Int
    ) -> Int? {
        guard count > 0, columns > 0, currentIndex >= 0, currentIndex < count else {
            return nil
        }
        let col = currentIndex % columns
        let row = currentIndex / columns
        let lastIndex = count - 1

        switch direction {
        case .up:
            guard row > 0 else { return nil }
            return currentIndex - columns
        case .down:
            let next = currentIndex + columns
            guard next <= lastIndex else { return nil }
            return next
        case .left:
            guard col > 0 else { return nil }
            return currentIndex - 1
        case .right:
            guard col < columns - 1, currentIndex + 1 <= lastIndex else { return nil }
            return currentIndex + 1
        }
    }
}
```

- [ ] **Step 1.4: Run tests — expect all 8 to pass**

```bash
xcodebuild test -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/LibraryFocusNavigatorTests 2>&1 | tail -20
```

Expected: `Test Suite 'LibraryFocusNavigatorTests' passed. Executed 8 tests, with 0 failures`.

- [ ] **Step 1.5: Commit**

```bash
git add SurVibe/Navigation/LibraryFocusNavigator.swift SurVibeTests/LibraryFocusNavigatorTests.swift
git commit -m "$(cat <<'EOF'
feat(SP-4b): LibraryFocusNavigator pure index helper

Adds the arrow-key index-math helper used by LessonLibraryView (list)
and SongLibraryView (grid). No UI yet — next tasks wire it into
.onKeyPress handlers.

8 Swift Testing cases cover row/column/edge math including partial
last-row clamping (audit P2-6).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Wire into `LessonLibraryView`

**Files:**
- Modify: `SurVibe/Learn/LessonLibraryView.swift` (currently 80 lines — arrows added + `.onAppear`)

- [ ] **Step 2.1: Add `moveFocus` helper + arrow-key `.onKeyPress`**

Open `SurVibe/Learn/LessonLibraryView.swift`. Add the helper right after the `body` property closes (before `// MARK: - Subviews` at line 82). Insert:

```swift
    // MARK: - Keyboard Focus

    /// Moves keyboard focus to the next lesson card in the given direction.
    /// Linear list → columns = 1.
    private func moveFocus(_ direction: LibraryFocusNavigator.FocusDirection, from currentID: Lesson.ID) {
        let lessons = viewModel.filteredLessons
        guard let currentIndex = lessons.firstIndex(where: { $0.lesson.id == currentID }) else { return }
        guard
            let nextIndex = LibraryFocusNavigator.nextIndex(
                for: direction,
                currentIndex: currentIndex,
                count: lessons.count,
                columns: 1
            )
        else { return }
        focusedLessonID = lessons[nextIndex].lesson.id
    }
```

Then in `lessonList` subview body, find the existing `.onKeyPress(.return)` modifier on both branches (locked + unlocked, lines ~95 and ~105). Add an `.onKeyPress(keys:)` modifier immediately below each `.onKeyPress(.return)`.

**Locked branch (around line 95) — after:**

```swift
                            .onKeyPress(.return) {
                                lockedLessonAlert = item.lesson
                                return .handled
                            }
```

**Add:**

```swift
                            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                                let direction: LibraryFocusNavigator.FocusDirection =
                                    (press.key == .upArrow) ? .up : .down
                                moveFocus(direction, from: item.lesson.id)
                                return .handled
                            }
```

**Unlocked branch (around line 105) — after:**

```swift
                        .onKeyPress(.return) {
                            router.openLesson(item.lesson.id)
                            return .handled
                        }
```

**Add:**

```swift
                        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                            let direction: LibraryFocusNavigator.FocusDirection =
                                (press.key == .upArrow) ? .up : .down
                            moveFocus(direction, from: item.lesson.id)
                            return .handled
                        }
```

- [ ] **Step 2.2: Add initial-focus `.onAppear`**

In the same file, find the `.task { await viewModel.loadLessons() }` at line 77. Add `.onAppear { ... }` immediately after it:

```swift
        .task {
            await viewModel.loadLessons()
        }
        .onAppear {
            if focusedLessonID == nil, let first = viewModel.filteredLessons.first {
                focusedLessonID = first.lesson.id
            }
        }
```

- [ ] **Step 2.3: Build — verify compile**

```bash
xcodebuild build -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 2.4: Run existing narrow regression — `SongLibraryViewFocusTests` + SVCore**

```bash
swift test --package-path Packages/SVCore 2>&1 | tail -5
```

Expected: `93 tests, 0 failures`.

- [ ] **Step 2.5: Commit**

```bash
git add SurVibe/Learn/LessonLibraryView.swift
git commit -m "$(cat <<'EOF'
feat(SP-4b): arrow-key navigation on LessonLibraryView

Up/Down arrows move @FocusState focusedLessonID between cards via
LibraryFocusNavigator. .onAppear primes initial focus on the first
filtered lesson (guarded on focusedLessonID == nil to avoid stealing
from the search field).

Part of audit P2-6 (accessibility-remainder SP-4b).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Wire into `SongLibraryView`

**Files:**
- Modify: `SurVibe/Songs/SongLibraryView.swift` (currently 246 lines — arrows + initial focus)

- [ ] **Step 3.1: Add `moveFocus` helper**

Open `SurVibe/Songs/SongLibraryView.swift`. After the `body` property closes (right before `// MARK: - Subviews` at line 133), insert:

```swift
    // MARK: - Keyboard Focus

    /// Column count used for arrow-key grid math.
    /// Matches the practical column count of `.adaptive(minimum: 160)` on iPhone + split-iPad.
    /// Wide-iPad multi-col layouts degrade gracefully (still navigate linearly).
    private static let gridColumns = 2

    /// Moves keyboard focus to the next song card in the given direction.
    private func moveFocus(_ direction: LibraryFocusNavigator.FocusDirection, from currentID: Song.ID) {
        let songs = viewModel.filteredSongs
        guard let currentIndex = songs.firstIndex(where: { $0.id == currentID }) else { return }
        guard
            let nextIndex = LibraryFocusNavigator.nextIndex(
                for: direction,
                currentIndex: currentIndex,
                count: songs.count,
                columns: Self.gridColumns
            )
        else { return }
        focusedSongID = songs[nextIndex].id
    }
```

- [ ] **Step 3.2: Add arrow-key `.onKeyPress` on both grid branches**

In `songGrid` subview body, find the existing `.onKeyPress(.return)` on the **premium-locked branch** (line ~146):

```swift
                            .onKeyPress(.return) {
                                signInTrigger = .premiumSong
                                return .handled
                            }
```

**Add immediately below:**

```swift
                            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                                let direction: LibraryFocusNavigator.FocusDirection
                                switch press.key {
                                case .upArrow: direction = .up
                                case .downArrow: direction = .down
                                case .leftArrow: direction = .left
                                case .rightArrow: direction = .right
                                default: return .ignored
                                }
                                moveFocus(direction, from: song.id)
                                return .handled
                            }
```

Find the **unlocked branch** `.onKeyPress(.return)` (line ~156):

```swift
                        .onKeyPress(.return) {
                            router.openSong(song.id)
                            return .handled
                        }
```

**Add immediately below:**

```swift
                        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                            let direction: LibraryFocusNavigator.FocusDirection
                            switch press.key {
                            case .upArrow: direction = .up
                            case .downArrow: direction = .down
                            case .leftArrow: direction = .left
                            case .rightArrow: direction = .right
                            default: return .ignored
                            }
                            moveFocus(direction, from: song.id)
                            return .handled
                        }
```

- [ ] **Step 3.3: Add initial-focus `.onAppear`**

Find the `.task { await viewModel.loadSongs() }` at line 128. Add `.onAppear` immediately after:

```swift
        .task {
            await viewModel.loadSongs()
        }
        .onAppear {
            if focusedSongID == nil, let first = viewModel.filteredSongs.first {
                focusedSongID = first.id
            }
        }
```

- [ ] **Step 3.4: Build + run narrow regression**

```bash
xcodebuild build -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`.

```bash
xcodebuild test -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/SongLibraryViewFocusTests \
  -only-testing:SurVibeTests/LibraryFocusNavigatorTests 2>&1 | tail -10
```

Expected: all tests pass (2 focus tests + 8 navigator tests).

- [ ] **Step 3.5: Commit**

```bash
git add SurVibe/Songs/SongLibraryView.swift
git commit -m "$(cat <<'EOF'
feat(SP-4b): arrow-key grid navigation on SongLibraryView

Up/Down/Left/Right arrows move @FocusState focusedSongID across the
2-column song grid via LibraryFocusNavigator. .onAppear primes initial
focus on the first filtered song.

Wide-iPad >2-col layouts degrade gracefully per spec AD-3 (linear
traversal only; no diagonal). Full dynamic column count deferred to
SP-4c per spec §6.

Part of audit P2-6 (accessibility-remainder SP-4b).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Song detail sheet detents (P2-12, read-only sheet)

**Files:**
- Modify: `SurVibe/Songs/SongLibraryView.swift` (sheet content closure at line 92)

- [ ] **Step 4.1: Add `[.medium, .large]` detents + visible grabber to detail sheet**

Find in `SongLibraryView.swift` (line 92):

```swift
        .sheet(item: $detailSong) { song in
            NavigationStack {
                SongDetailView(song: song)
            }
        }
```

Replace with:

```swift
        .sheet(item: $detailSong) { song in
            NavigationStack {
                SongDetailView(song: song)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
```

- [ ] **Step 4.2: Build**

```bash
xcodebuild build -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4.3: Commit**

```bash
git add SurVibe/Songs/SongLibraryView.swift
git commit -m "$(cat <<'EOF'
feat(SP-4b): medium+large detents on song detail sheet

Song detail is read-only info; matches HIG 'include a grabber in a
resizable sheet'. Detents applied at content-view level inside the
.sheet closure (per spec AD-5).

Part of audit P2-12 (accessibility-remainder SP-4b).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: SongImportSheet detents (P2-12, compose + warnings)

**Files:**
- Modify: `SurVibe/Songs/SongImportSheet.swift`

- [ ] **Step 5.1: Read the file to locate body end + warnings-sheet content**

```bash
# Verify current structure — no edits in this step, just context.
```

Confirm `body` property's outer `.sheet(isPresented: Binding(get: { vm.showWarnings }, ... ) ) { warningsSheet(vm: vm) }` at line 81. Confirm `warningsSheet(vm:)` function body to know what to modify.

- [ ] **Step 5.2: Add `[.large]` detent on the TabView (root of body)**

In `SongImportSheet.swift`, find the `.onChange(of: vm.importSucceeded)` modifier (line 78). Add `.presentationDetents([.large])` immediately after the TabView closes — i.e., alongside the other `.onChange` / `.sheet` / `.alert` modifiers on the root TabView.

Replace (around lines 78-91):

```swift
        .onChange(of: vm.importSucceeded) { _, succeeded in
            if succeeded { dismiss() }
        }
        .sheet(isPresented: Binding(get: { vm.showWarnings }, set: { vm.showWarnings = $0 })) {
            warningsSheet(vm: vm)
        }
        .alert("Import Error", isPresented: Binding(
            get: { vm.importError != nil },
            set: { if !$0 { vm.importError = nil } }
        )) {
            Button("OK") { vm.importError = nil }
        } message: {
            Text(vm.importError ?? "")
        }
```

With (add `.presentationDetents([.large])` at the top, and detents on the warnings sheet closure):

```swift
        .presentationDetents([.large])
        .onChange(of: vm.importSucceeded) { _, succeeded in
            if succeeded { dismiss() }
        }
        .sheet(isPresented: Binding(get: { vm.showWarnings }, set: { vm.showWarnings = $0 })) {
            warningsSheet(vm: vm)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Import Error", isPresented: Binding(
            get: { vm.importError != nil },
            set: { if !$0 { vm.importError = nil } }
        )) {
            Button("OK") { vm.importError = nil }
        } message: {
            Text(vm.importError ?? "")
        }
```

- [ ] **Step 5.3: Build**

```bash
xcodebuild build -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5.4: Commit**

```bash
git add SurVibe/Songs/SongImportSheet.swift
git commit -m "$(cat <<'EOF'
feat(SP-4b): detents on SongImportSheet + nested warnings

Compose sheet stays .large only (HIG Mail/Messages compose precedent).
Nested warnings sheet gets .medium + visible grabber (resizable ->
grabber per HIG Sheets).

Part of audit P2-12 (accessibility-remainder SP-4b).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: SongEditView detents (P2-12, compose + warnings)

**Files:**
- Modify: `SurVibe/Songs/SongEditView.swift`

- [ ] **Step 6.1: Add `[.large]` detent on `editContent(vm:)` body + detents on warnings sheet**

In `SongEditView.swift` at line 73 (the `editContent(vm:)` function), find:

```swift
        .onChange(of: vm.importSucceeded) { _, succeeded in
            if succeeded { dismiss() }
        }
        .sheet(isPresented: Binding(get: { vm.showWarnings }, set: { vm.showWarnings = $0 })) {
            warningsSheet(vm: vm)
        }
        .alert("Edit Error", isPresented: Binding(
            get: { vm.importError != nil },
            set: { if !$0 { vm.importError = nil } }
        )) {
            Button("OK") { vm.importError = nil }
        } message: {
            Text(vm.importError ?? "")
        }
```

Replace with:

```swift
        .presentationDetents([.large])
        .onChange(of: vm.importSucceeded) { _, succeeded in
            if succeeded { dismiss() }
        }
        .sheet(isPresented: Binding(get: { vm.showWarnings }, set: { vm.showWarnings = $0 })) {
            warningsSheet(vm: vm)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Edit Error", isPresented: Binding(
            get: { vm.importError != nil },
            set: { if !$0 { vm.importError = nil } }
        )) {
            Button("OK") { vm.importError = nil }
        } message: {
            Text(vm.importError ?? "")
        }
```

- [ ] **Step 6.2: Build**

```bash
xcodebuild build -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6.3: Commit**

```bash
git add SurVibe/Songs/SongEditView.swift
git commit -m "$(cat <<'EOF'
feat(SP-4b): detents on SongEditView + nested warnings

Compose edit stays .large only; nested warnings .medium + grabber.
Mirrors the SongImportSheet pattern (Task 5).

Part of audit P2-12 (accessibility-remainder SP-4b).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: TabView selection haptic (P2-13)

**Files:**
- Modify: `SurVibe/ContentView.swift:64`

- [ ] **Step 7.1: Add `.sensoryFeedback(.selection, trigger: selectedTab)`**

Open `SurVibe/ContentView.swift`. Find line 64:

```swift
        .tabViewStyle(.sidebarAdaptable)
        .tint(themeManager.resolved.accentColor)
```

Replace with:

```swift
        .tabViewStyle(.sidebarAdaptable)
        .sensoryFeedback(.selection, trigger: selectedTab)
        .tint(themeManager.resolved.accentColor)
```

- [ ] **Step 7.2: Build**

```bash
xcodebuild build -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7.3: Commit**

```bash
git add SurVibe/ContentView.swift
git commit -m "$(cat <<'EOF'
feat(SP-4b): .selection haptic on TabView tab switch

Fires whenever selectedTab changes (tap or CommandMenu ⌘1–⌘4).
.selection matches Apple's sensoryFeedback doc example for state
toggles; overrides audit's .impact(.medium) per spec AD-1.

Part of audit P2-13 (accessibility-remainder SP-4b).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Full verify + banned-pattern sweep + latency gate

- [ ] **Step 8.1: Swift lint + format check**

```bash
/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml \
  SurVibe/Navigation/LibraryFocusNavigator.swift \
  SurVibe/Learn/LessonLibraryView.swift \
  SurVibe/Songs/SongLibraryView.swift \
  SurVibe/Songs/SongImportSheet.swift \
  SurVibe/Songs/SongEditView.swift \
  SurVibe/ContentView.swift \
  SurVibeTests/LibraryFocusNavigatorTests.swift
```

Expected: no errors. Warnings about pre-existing code outside the touched lines are acceptable.

```bash
xcrun swift-format lint --configuration .swift-format \
  SurVibe/Navigation/LibraryFocusNavigator.swift \
  SurVibeTests/LibraryFocusNavigatorTests.swift 2>&1 | tail -20
```

Fix any format issues on the two new files with:

```bash
xcrun swift-format format --in-place --configuration .swift-format \
  SurVibe/Navigation/LibraryFocusNavigator.swift \
  SurVibeTests/LibraryFocusNavigatorTests.swift
```

- [ ] **Step 8.2: Banned-pattern grep**

```bash
# Should all return 0 hits.
grep -n '#if os(iOS)\|#if os(macOS)\|UIDevice\|UIScreen.main\|UIInterfaceOrientation\|\.bottomBar\|\.topBarTrailing\|DispatchQueue.main.async' \
  SurVibe/Navigation/LibraryFocusNavigator.swift \
  SurVibeTests/LibraryFocusNavigatorTests.swift

# Force-unwrap + try! in NEW content only.
grep -nE 'try!|!  *$' SurVibe/Navigation/LibraryFocusNavigator.swift || echo "no forbidden unwraps"
```

Expected: 0 matches on banned patterns. (`.topBarTrailing` exists in `SongLibraryView.swift` from prior code — out of scope for this PR, do not touch.)

- [ ] **Step 8.3: Run narrow test battery**

```bash
# SVCore (regression baseline)
swift test --package-path Packages/SVCore 2>&1 | tail -5
```

Expected: `93 tests, 0 failures`.

```bash
# LibraryFocusNavigator + latency + focus regressions
xcodebuild test -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/LibraryFocusNavigatorTests \
  -only-testing:SurVibeTests/LatencyContractTests \
  -only-testing:SurVibeTests/SongLibraryViewFocusTests 2>&1 | tail -15
```

Expected: all tests pass. `LatencyContractTests` 3/3 green (no p95 regression).

- [ ] **Step 8.4: Run the `/check` slash command equivalent**

If your CLI has the `/check` slash command, invoke it. Otherwise run its equivalents manually — the lint, format, and build commands above plus:

```bash
xcodebuild clean build -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' 2>&1 | tail -5
```

Expected: `** CLEAN SUCCEEDED **` and `** BUILD SUCCEEDED **`.

- [ ] **Step 8.5: Manual QA — record results in the PR description later**

Three checks to perform **on a physical iPhone** (haptics) and **iPad + Magic Keyboard** (arrow keys):

1. **P2-6 on iPad + Magic Keyboard:**
   - Open Songs tab. Press Tab to enter the grid. First card should glow.
   - Press Right — focus moves to col 2. Right again at col 2 — no-op (edge clamp).
   - Press Down — focus moves to next row. Press Up — returns. Press Return — opens detail.
   - Switch to Learn tab. Press Up/Down — moves linearly; Left/Right — should be no-op (list is one column).
2. **P2-12 on iPhone sim:**
   - Long-press a song → "Song Details" context menu → detail sheet opens at **medium**; dragging the grabber expands to **large**.
   - Toolbar upload button → SongImportSheet opens at **large** (full). Induce a warning (e.g., paste malformed sargam) → warnings sheet opens at **medium** with grabber.
   - Long-press a user-source song → "Edit Song" → SongEditView opens **large**. Induce warning → warnings sheet opens at **medium** with grabber.
3. **P2-13 on physical iPhone:**
   - Tap each tab — `.selection` haptic fires.
   - Press ⌘1, ⌘2, ⌘3, ⌘4 (iPad + keyboard) or an equivalent — haptic fires on each tab switch.

If any check fails, **do not mark Step 8.5 done**. File the regression and iterate.

- [ ] **Step 8.6: Commit formatting fixes if any**

```bash
git status
# If swift-format changed any files in Step 8.1:
git add -u
git commit -m "$(cat <<'EOF'
chore(SP-4b): swift-format cleanup

Apply swift-format to new files per .swift-format config.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
# If no format changes, skip.
```

---

## Task 9: Update trajectory tracker + merge + tag

- [ ] **Step 9.1: Update SP-TRAJECTORY-TRACKER.md — mark SP-4b shipped**

Open `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md`. Find the SP-4b row in the §Status table:

```markdown
| **SP-4b** Accessibility remainder (P2-6 arrow-key card nav, P2-12 detents audit, P2-13 tab-switch haptics) — spec landed 2026-04-20 | 🟡 spec | — | — | — |
```

Replace (fill in `<TAG-SHA>`, `<MERGE-SHA>`, and `<N>` after the squash-merge step below):

```markdown
| **SP-4b** Accessibility remainder (P2-6 arrow-key card nav, P2-12 detents audit, P2-13 tab-switch haptics) | ✅ shipped | `sp-4b-accessibility-remainder` @ `<TAG-SHA>` | `<MERGE-SHA>` | <N> |
```

Add an SP-4b landed block after the SP-4a landed block (line ~131). Use SP-4a's shape:

```markdown
### SP-4b landed (2026-04-20)

- Shipped 3 items: P2-6 arrow-key card nav (Lessons + Songs), P2-12 sheet detent audit (5 sheets), P2-13 TabView selection haptic.
- New files: `SurVibe/Navigation/LibraryFocusNavigator.swift` (~50 lines pure helper), `SurVibeTests/LibraryFocusNavigatorTests.swift` (8 Swift Testing cases).
- Modified: `LessonLibraryView.swift`, `SongLibraryView.swift`, `SongImportSheet.swift`, `SongEditView.swift`, `ContentView.swift`.
- Tests: 8 new `LibraryFocusNavigatorTests` pass; `SongLibraryViewFocusTests` 2/2 pass (no regression); `LatencyContractTests` 3/3 green; SVCore 93/93.
- Zero banned-pattern introductions. Zero audio-path touches. p95 latency delta: 0.0 ms (UI-only changes).
- Deferred to SP-4c per spec §6: focus-ring polish, escape-to-clear-focus, HomeTab/ProfileTab focus, GeometryReader dynamic columns.
```

- [ ] **Step 9.2: Commit tracker update**

```bash
git add -f docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md
git commit -m "$(cat <<'EOF'
docs(SP-4b): update tracker — accessibility remainder shipped

Marks SP-4b ✅ shipped in status table; adds landed block documenting
the 3 audit items (P2-6/P2-12/P2-13) and the SP-4c deferrals.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 9.3: Push branch + open PR**

```bash
git push -u origin feat/sp-4b-accessibility-remainder
gh pr create --title "SP-4b: Accessibility remainder (P2-6/12/13)" --body "$(cat <<'EOF'
## Summary

Closes audit items P2-6, P2-12, P2-13.

- P2-6 arrow-key card navigation on Lessons (up/down) and Songs (up/down/left/right) via new `LibraryFocusNavigator` pure helper.
- P2-12 sheet detent audit: 5 sheets (song detail, import, edit, import-warnings, edit-warnings) now have HIG-aligned detents + drag indicators.
- P2-13 `.sensoryFeedback(.selection, trigger: selectedTab)` on root TabView.

Spec: `docs/superpowers/specs/2026-04-20-sp4b-accessibility-remainder-design.md`
Plan: `docs/superpowers/plans/2026-04-20-sp4b-accessibility-remainder.md`

## Deferrals (routed to SP-4c)

Per spec §6: focus-ring polish, escape-to-clear-focus, HomeTab/ProfileTab focus, GeometryReader dynamic column count.

## Test plan

- [x] 8 `LibraryFocusNavigatorTests` green
- [x] `SongLibraryViewFocusTests` 2/2 green (no regression)
- [x] `LatencyContractTests` 3/3 green — p95 delta 0.0 ms
- [x] SVCore 93/93 green
- [x] Manual QA on iPad + Magic Keyboard (arrow keys)
- [x] Manual QA on iPhone sim (sheet detents)
- [x] Manual QA on physical iPhone (haptic)
- [x] Banned-pattern grep clean on new files

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 9.4: After merge — tag and push the tag**

```bash
# After the PR merges to main, fetch and tag the merge commit:
git checkout main && git pull
MERGE_SHA=$(git rev-parse HEAD)
git tag sp-4b-accessibility-remainder $MERGE_SHA
git push origin sp-4b-accessibility-remainder
```

- [ ] **Step 9.5: Update tracker with merge SHA + tag SHA**

On `main` after the tag is pushed, fill in the `<TAG-SHA>` and `<MERGE-SHA>` placeholders in the §Status row from Step 9.1. Commit the substitution (force-add because `docs/` is gitignored):

```bash
git add -f docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md
git commit -m "$(cat <<'EOF'
docs(SP-4b): record merge SHA + tag SHA in tracker

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Self-Review Checklist

Run this checklist after finishing all tasks:

- [ ] Spec coverage: every item in spec §3 has a task. P2-6 → Tasks 1–3. P2-12 → Tasks 4–6. P2-13 → Task 7. Verification → Task 8. Close-out → Task 9.
- [ ] No placeholders (no TBD / TODO / "fill in later") in the plan or in committed code.
- [ ] Type consistency: `LibraryFocusNavigator.nextIndex` signature used identically in Task 1 (definition), Task 2 (Lessons call site), Task 3 (Songs call site). `FocusDirection` enum cases referenced consistently.
- [ ] Acceptance criteria from spec §9 all have covering tasks.
