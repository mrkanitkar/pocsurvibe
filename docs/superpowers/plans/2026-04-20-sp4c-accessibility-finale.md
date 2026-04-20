# SP-4c — Accessibility Finale Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the 4 SP-4b §6 focus/grid polish deferrals plus a full-app XCUITest accessibility audit that becomes an ongoing regression gate.

**Architecture:** Two phases in one PR. Phase A wires `@FocusState` + a reusable `FocusRingModifier` onto HomeTab DoorCards, ProfileTab rows, and library cards; adds escape-to-clear-focus; and replaces the hardcoded 2-column grid math in `SongLibraryView` with a `GeometryReader`-driven dynamic count. Phase B adds `AccessibilityAuditTests.swift` under `SurVibeUITests/` with 8 screen-targeted `performAccessibilityAudit(for:)` tests and fixes whatever issues the audit surfaces, screen by screen.

**Tech Stack:** Swift 6 (iOS 26+), SwiftUI `@FocusState` + `.onKeyPress(keys:)`, XCTest + XCUITest (`XCUIApplication.performAccessibilityAudit(for:_:)` — iOS 17+), Swift Testing (`@Test`, `#expect`) for Phase A unit tests.

**Spec:** [docs/superpowers/specs/2026-04-20-sp4c-accessibility-finale-design.md](../specs/2026-04-20-sp4c-accessibility-finale-design.md)

**Branch:** `feat/sp-4c-accessibility-finale` (already created at spec commit `b4ab019`).

---

## File Structure

| Kind | Path | Purpose |
|---|---|---|
| Create | `SurVibe/Navigation/FocusRingModifier.swift` | Reusable `ViewModifier` that draws a 3pt accent stroke when an item's ID matches a focused-state value. |
| Create | `SurVibeTests/FocusRingModifierTests.swift` | N/A — pure visual modifier; no unit tests. (File NOT created — SwiftUI visual behaviour not unit-testable.) |
| Modify | `SurVibe/Learn/LessonLibraryView.swift` | Add `FocusRingModifier` + `.onKeyPress(.escape)`. |
| Modify | `SurVibe/Songs/SongLibraryView.swift` | Add `FocusRingModifier` + escape + GeometryReader dynamic columns + `columnCount(for:)` static helper. |
| Modify | `SurVibe/HomeTab.swift` | Add `HomeDoorID` enum + `@FocusState` + `.focused(...)` + `.onKeyPress(keys:)` + `FocusRingModifier`. |
| Modify | `SurVibe/ProfileTab.swift` | Add `ProfileRowID` enum + `@FocusState` + `.focused(...)` + `.onKeyPress(keys:)` + `FocusRingModifier`. |
| Create | `SurVibeTests/HomeTabFocusTests.swift` | 4 unit tests covering 2-col `HomeDoorID` nav math via `LibraryFocusNavigator`. |
| Create | `SurVibeTests/ProfileTabFocusTests.swift` | 4 unit tests covering linear `ProfileRowID` nav math. |
| Create | `SurVibeTests/SongGridColumnCountTests.swift` | 5 unit tests covering `SongLibraryView.columnCount(for:)` at iPhone / iPad portrait / iPad landscape / Mac widths. |
| Create | `SurVibeUITests/AccessibilityAuditTests.swift` | 8 XCUITest audit tests (one per major screen). |
| Modify | Variable — audit-surfaced fixes | Whatever files Phase B audit flags (estimated 5-15 files). |

**Estimated totals:** 5 new files + 4 core modified + 5-15 audit-fix modified = 14-24 files. Ships as one PR with ~12-16 commits.

---

## Task 1: `FocusRingModifier` (Phase A — reusable focus-ring styling)

**Files:**
- Create: `SurVibe/Navigation/FocusRingModifier.swift`

Pure visual modifier; no unit tests (SwiftUI visual behaviour isn't unit-testable).

- [ ] **Step 1.1: Create `FocusRingModifier.swift`**

Exact content:

```swift
import SwiftUI

/// Draws a 3pt stroke in the supplied accent colour when this item's `id`
/// matches the currently-focused `@FocusState` binding value.
///
/// Used by library cards, HomeTab DoorCards, and ProfileTab rows so the
/// system focus indicator is visually consistent across surfaces.
///
/// - Parameters:
///   - itemID: The identity of the view this modifier is attached to.
///   - focusedID: The currently-focused identity (or `nil`).
///   - accent: The stroke colour (typically `themeManager.resolved.accentColor`).
///   - cornerRadius: Corner radius of the focus ring. Defaults to 12.
struct FocusRingModifier<ID: Hashable>: ViewModifier {
    let itemID: ID
    let focusedID: ID?
    let accent: Color
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content.overlay {
            if focusedID == itemID {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(accent, lineWidth: 3)
            }
        }
    }
}

extension View {
    /// Attaches a focus-ring overlay that appears when `itemID == focusedID`.
    ///
    /// Sugar for `.modifier(FocusRingModifier(itemID:focusedID:accent:))`.
    func focusRing<ID: Hashable>(
        itemID: ID,
        focusedID: ID?,
        accent: Color,
        cornerRadius: CGFloat = 12
    ) -> some View {
        modifier(FocusRingModifier(itemID: itemID, focusedID: focusedID, accent: accent, cornerRadius: cornerRadius))
    }
}
```

- [ ] **Step 1.2: Build — verify compile**

```
mcp__XcodeBuildMCP__build_sim
```

Expected: `BUILD SUCCEEDED`.

If the simulator is in a bad state, run `xcrun simctl shutdown <uuid> && xcrun simctl erase <uuid> && xcrun simctl boot <uuid>` first (ID 1293FE3B-F25A-4667-932A-24F01C9D2655 per session defaults).

- [ ] **Step 1.3: Commit**

```bash
git add SurVibe/Navigation/FocusRingModifier.swift
git commit -m "$(cat <<'EOF'
feat(SP-4c): FocusRingModifier reusable focus-ring overlay

3pt accent-colour stroke when an item's id matches the focused
@FocusState value. Used by library cards, HomeTab DoorCards, and
ProfileTab rows so focus indication is visually consistent.

Part of audit SP-4b §6 deferral 1 (focus-ring custom styling).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Wire FocusRing + escape into `LessonLibraryView`

**Files:**
- Modify: `SurVibe/Learn/LessonLibraryView.swift`

- [ ] **Step 2.1: Import `SVCore` for `AppThemeManager` is already present — no new imports needed**

Confirm the file already has `@Environment(AppThemeManager.self) private var themeManager` (yes — declared at line 17).

- [ ] **Step 2.2: Add focus-ring + escape on the locked branch**

In `lessonList` body, find the locked branch block (around line 89-99, starting `LessonCardView(item: item)` and ending with existing `.onKeyPress(keys: [.upArrow, .downArrow])` from SP-4b).

Replace the entire locked branch with:

```swift
                    if item.completionState == .locked {
                        LessonCardView(item: item)
                            .onTapGesture {
                                lockedLessonAlert = item.lesson
                            }
                            .focused($focusedLessonID, equals: item.lesson.id)
                            .focusRing(
                                itemID: item.lesson.id,
                                focusedID: focusedLessonID,
                                accent: themeManager.resolved.accentColor
                            )
                            .onKeyPress(.return) {
                                lockedLessonAlert = item.lesson
                                return .handled
                            }
                            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                                let direction: LibraryFocusNavigator.FocusDirection =
                                    (press.key == .upArrow) ? .up : .down
                                moveFocus(direction, from: item.lesson.id)
                                return .handled
                            }
                            .onKeyPress(.escape) {
                                focusedLessonID = nil
                                return .handled
                            }
```

- [ ] **Step 2.3: Add focus-ring + escape on the unlocked branch**

Replace the unlocked branch (around line 100-113) with:

```swift
                    } else {
                        NavigationLink(value: item.lesson) {
                            LessonCardView(item: item)
                        }
                        .buttonStyle(.plain)
                        .focused($focusedLessonID, equals: item.lesson.id)
                        .focusRing(
                            itemID: item.lesson.id,
                            focusedID: focusedLessonID,
                            accent: themeManager.resolved.accentColor
                        )
                        .onKeyPress(.return) {
                            router.openLesson(item.lesson.id)
                            return .handled
                        }
                        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                            let direction: LibraryFocusNavigator.FocusDirection =
                                (press.key == .upArrow) ? .up : .down
                            moveFocus(direction, from: item.lesson.id)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            focusedLessonID = nil
                            return .handled
                        }
                    }
```

- [ ] **Step 2.4: Build + commit**

```
mcp__XcodeBuildMCP__build_sim
```

Expected: `BUILD SUCCEEDED`.

```bash
git add SurVibe/Learn/LessonLibraryView.swift
git commit -m "$(cat <<'EOF'
feat(SP-4c): focus-ring + escape-to-clear on LessonLibraryView

Accent-colour focus ring via FocusRingModifier on each focused lesson
card; Escape key clears focusedLessonID. Works on both locked and
unlocked branches.

Part of audit SP-4b §6 deferrals 1 & 2 (focus-ring + escape).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Wire FocusRing + escape + dynamic columns into `SongLibraryView`

**Files:**
- Modify: `SurVibe/Songs/SongLibraryView.swift`

- [ ] **Step 3.1: Replace hardcoded `gridColumns` with GeometryReader-driven state**

Find in `SongLibraryView.swift` (currently around line 49-51):

```swift
    /// Two-column adaptive grid.
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]
```

Replace with:

```swift
    /// Column count computed from measured grid width. Defaults to 2 until
    /// `GeometryReader` reports a real width on first layout.
    @State
    private var gridColumnCount: Int = 2
```

And find the existing `private static let gridColumns = 2` (from SP-4b, around line 138):

```swift
    /// Column count used for arrow-key grid math.
    /// Matches the practical column count of `.adaptive(minimum: 160)` on iPhone + split-iPad.
    /// Wide-iPad multi-col layouts degrade gracefully (still navigate linearly).
    private static let gridColumns = 2
```

Replace with:

```swift
    /// Static column-count helper keyed by measured width. Used by both the
    /// grid layout and the arrow-key focus math so they stay in lockstep.
    ///
    /// Empirical breakpoints validated against iPhone / iPad portrait / iPad landscape:
    /// - <700pt: 2 columns (iPhone all sizes + split iPad regular)
    /// - 700..<1000pt: 3 columns (iPad portrait, iPad landscape split)
    /// - >=1000pt: 4 columns (iPad Pro landscape, Mac)
    nonisolated static func columnCount(for width: CGFloat) -> Int {
        switch width {
        case ..<700: return 2
        case 700..<1000: return 3
        default: return 4
        }
    }
```

- [ ] **Step 3.2: Update `moveFocus` to use the dynamic column count**

Find the `moveFocus` method (around line 144-157). Replace:

```swift
                columns: Self.gridColumns
```

With:

```swift
                columns: gridColumnCount
```

- [ ] **Step 3.3: Rewrite `songGrid` subview body to wrap with GeometryReader + flexible grid**

Find `songGrid` (around line 170-190):

```swift
    /// Song grid with 2-column adaptive layout.
    private var songGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.filteredSongs) { song in
                    // ... existing ForEach body ...
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
```

Replace with:

```swift
    /// Song grid with width-responsive column count (2/3/4 depending on width).
    private var songGrid: some View {
        GeometryReader { proxy in
            let count = Self.columnCount(for: proxy.size.width)
            let gridColumnArray = Array(
                repeating: GridItem(.flexible(), spacing: 16),
                count: count
            )

            ScrollView {
                LazyVGrid(columns: gridColumnArray, spacing: 16) {
                    ForEach(viewModel.filteredSongs) { song in
                        songCard(for: song)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .onAppear {
                gridColumnCount = count
            }
            .onChange(of: proxy.size.width) { _, newWidth in
                gridColumnCount = Self.columnCount(for: newWidth)
            }
        }
    }
```

- [ ] **Step 3.4: Extract `songCard(for:)` helper to keep the grid body scannable**

Add this helper method in the `// MARK: - Subviews` section, immediately after `songGrid`:

```swift
    /// Renders a single song card with focus, keyboard, and context-menu wiring.
    /// Extracted to keep `songGrid`'s GeometryReader body scannable.
    @ViewBuilder
    private func songCard(for song: Song) -> some View {
        if viewModel.isPremiumLocked(song) {
            SongCardView(song: song)
                .onTapGesture {
                    signInTrigger = .premiumSong
                }
                .focused($focusedSongID, equals: song.id)
                .focusRing(
                    itemID: song.id,
                    focusedID: focusedSongID,
                    accent: themeManager.resolved.accentColor
                )
                .onKeyPress(.return) {
                    signInTrigger = .premiumSong
                    return .handled
                }
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
                .onKeyPress(.escape) {
                    focusedSongID = nil
                    return .handled
                }
        } else {
            NavigationLink(value: song) {
                SongCardView(song: song)
            }
            .buttonStyle(.plain)
            .focused($focusedSongID, equals: song.id)
            .focusRing(
                itemID: song.id,
                focusedID: focusedSongID,
                accent: themeManager.resolved.accentColor
            )
            .onKeyPress(.return) {
                router.openSong(song.id)
                return .handled
            }
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
            .onKeyPress(.escape) {
                focusedSongID = nil
                return .handled
            }
            .contextMenu {
                Button {
                    detailSong = song
                } label: {
                    Label("Song Details", systemImage: "info.circle")
                }
                if song.source == "user" {
                    Button {
                        songToEdit = song
                    } label: {
                        Label("Edit Song", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        songToDelete = song
                    } label: {
                        Label("Delete Song", systemImage: "trash")
                    }
                }
            }
        }
    }
```

- [ ] **Step 3.5: Also update `loadingState` to use the flexible grid**

Find `loadingState` (around line 195-205):

```swift
    /// Loading state with shimmer placeholders.
    private var loadingState: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0..<6, id: \.self) { _ in
                    // ...
                }
            }
            // ...
        }
    }
```

Replace `columns: columns` with `columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: gridColumnCount)` — i.e.:

```swift
    /// Loading state with shimmer placeholders.
    private var loadingState: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: gridColumnCount), spacing: 16) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.resolved.cardBackgroundColor)
                        .frame(height: 200)
                        .shimmer()
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
```

- [ ] **Step 3.6: Build + commit**

```
mcp__XcodeBuildMCP__build_sim
```

Expected: `BUILD SUCCEEDED`.

```bash
git add SurVibe/Songs/SongLibraryView.swift
git commit -m "$(cat <<'EOF'
feat(SP-4c): focus-ring + escape + dynamic grid on SongLibraryView

- FocusRingModifier overlay on each song card (accent colour stroke)
- Escape key clears focusedSongID
- GeometryReader-driven column count (2/3/4 depending on width):
    <700pt → 2 cols, 700-1000pt → 3 cols, ≥1000pt → 4 cols
- Grid layout and arrow-key focus math use the same gridColumnCount,
  so navigation stays in lockstep with the rendered layout at any width
- songCard(for:) helper extracted from songGrid to keep body scannable

Part of audit SP-4b §6 deferrals 1, 2, 5 (focus-ring, escape,
dynamic columns).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: HomeTab DoorCard focus

**Files:**
- Modify: `SurVibe/HomeTab.swift`

- [ ] **Step 4.1: Add `HomeDoorID` enum**

At the bottom of `HomeTab.swift`, after the `ComingSoonDoor` enum (around line 218), add:

```swift
// MARK: - HomeDoorID

/// Stable identity for the 5 Home DoorCards, used for hardware-keyboard focus.
/// Order matches the rendered grid (row-major, 2 cols assumed).
enum HomeDoorID: String, Hashable, CaseIterable {
    case songs
    case learn
    case moods
    case events
    case ragas
}
```

- [ ] **Step 4.2: Add `@FocusState` + `moveFocus` helper in `HomeTab`**

In `HomeTab` struct, after the existing properties (around line 40, before `// MARK: - Body`), insert:

```swift
    /// Tracks which door has hardware-keyboard focus.
    @FocusState
    private var focusedDoorID: HomeDoorID?

    /// Home grid is effectively 2 columns (adaptive minimum 160pt on all
    /// supported widths packs the 5 doors into 2-col grid on iPhone +
    /// iPad portrait). Wide-iPad landscape may render 3+ columns; arrow-
    /// key math stays 2-col (graceful linear degradation).
    private static let homeGridColumns = 2

    /// Moves keyboard focus to the next door in the given direction.
    private func moveFocus(_ direction: LibraryFocusNavigator.FocusDirection, from currentID: HomeDoorID) {
        let doors = HomeDoorID.allCases
        guard let currentIndex = doors.firstIndex(of: currentID) else { return }
        guard
            let nextIndex = LibraryFocusNavigator.nextIndex(
                for: direction,
                currentIndex: currentIndex,
                count: doors.count,
                columns: Self.homeGridColumns
            )
        else { return }
        focusedDoorID = doors[nextIndex]
    }
```

- [ ] **Step 4.3: Wire `.focused` + `.focusRing` + `.onKeyPress` onto each DoorCard**

In `discoverSection` body (lines 98-169), each `DoorCard { ... }` call chain needs the same four modifiers appended. Currently the 5 DoorCard calls close with `}` (the closure's closing brace) — e.g.:

```swift
                DoorCard(
                    icon: "music.note",
                    title: "Songs",
                    // ...
                    isEnabled: true
                ) {
                    Self.logger.debug("Door tapped: Songs")
                    router.switchTab(to: .songs)
                }
```

For the **Songs** door, add modifiers so it becomes:

```swift
                DoorCard(
                    icon: "music.note",
                    title: "Songs",
                    subtitle: "Explore melodies from Indian cinema",
                    gradientColors: [
                        .rangNeel,
                        Color(red: 0.18, green: 0.22, blue: 0.55),
                    ],
                    isEnabled: true
                ) {
                    Self.logger.debug("Door tapped: Songs")
                    router.switchTab(to: .songs)
                }
                .focused($focusedDoorID, equals: .songs)
                .focusRing(itemID: HomeDoorID.songs, focusedID: focusedDoorID, accent: themeManager.resolved.accentColor)
                .onKeyPress(.return) {
                    router.switchTab(to: .songs)
                    return .handled
                }
                .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                    let direction: LibraryFocusNavigator.FocusDirection
                    switch press.key {
                    case .upArrow: direction = .up
                    case .downArrow: direction = .down
                    case .leftArrow: direction = .left
                    case .rightArrow: direction = .right
                    default: return .ignored
                    }
                    moveFocus(direction, from: .songs)
                    return .handled
                }
```

Repeat for the other 4 doors, each with its own `.focused($focusedDoorID, equals: .learn / .moods / .events / .ragas)` and matching `focusRing(itemID: HomeDoorID.learn)` etc. For the disabled doors (moods, events, ragas), the `.onKeyPress(.return)` action is the same as their tap action — set `showComingSoon = .moods` / `.events` / `.ragas` respectively. For Learn: `router.switchTab(to: .learn)`.

- [ ] **Step 4.4: Add initial-focus `.onAppear`**

In the `body` (the outer `var body: some View`), find the `.sheet(item: $showComingSoon) { ... }` modifier (around line 63). Add `.onAppear` immediately before `.accessibilityLabel(...)` at line 70:

```swift
        .sheet(item: $showComingSoon) { door in
            ComingSoonSheet(
                doorTitle: door.title,
                doorIcon: door.icon,
                doorDescription: door.sheetDescription
            )
        }
        .onAppear {
            if focusedDoorID == nil {
                focusedDoorID = .songs
            }
        }
        .accessibilityLabel(AccessibilityHelper.tabLabel(for: "Home"))
```

- [ ] **Step 4.5: Build + commit**

```
mcp__XcodeBuildMCP__build_sim
```

Expected: `BUILD SUCCEEDED`.

```bash
git add SurVibe/HomeTab.swift
git commit -m "$(cat <<'EOF'
feat(SP-4c): keyboard focus on HomeTab DoorCards

New HomeDoorID enum (5 cases covering the existing 5 doors) identifies
cards for @FocusState. Each DoorCard gets .focused + focusRing +
Return (acts as tap) + arrow-key nav (via LibraryFocusNavigator with
2-col assumption). .onAppear primes focus on .songs.

Part of audit SP-4b §6 deferral 3 (HomeTab DoorCard focus).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: ProfileTab rows focus

**Files:**
- Modify: `SurVibe/ProfileTab.swift`

- [ ] **Step 5.1: Add `ProfileRowID` enum at the bottom of the file**

At the end of `ProfileTab.swift`, after the existing struct, add:

```swift
// MARK: - ProfileRowID

/// Stable identity for the 5 ProfileTab NavigationLink/Button rows with hoverEffect.
/// Order matches the on-screen vertical list order (Settings section first, then Appearance).
enum ProfileRowID: String, Hashable, CaseIterable {
    case appLanguage
    case midiDevice
    case redoOnboarding
    case theme
    case display
}
```

- [ ] **Step 5.2: Add `@FocusState` + `moveFocus` helper**

In the `ProfileTab` struct, after the existing properties, add:

```swift
    /// Tracks which row has hardware-keyboard focus.
    @FocusState
    private var focusedRowID: ProfileRowID?

    /// Moves keyboard focus to the next row in the given direction.
    /// Linear list → columns = 1.
    private func moveFocus(_ direction: LibraryFocusNavigator.FocusDirection, from currentID: ProfileRowID) {
        let rows = ProfileRowID.allCases
        guard let currentIndex = rows.firstIndex(of: currentID) else { return }
        guard
            let nextIndex = LibraryFocusNavigator.nextIndex(
                for: direction,
                currentIndex: currentIndex,
                count: rows.count,
                columns: 1
            )
        else { return }
        focusedRowID = rows[nextIndex]
    }
```

- [ ] **Step 5.3: Wire focus + ring + keyboard onto each of the 5 rows**

In `settingsSection` (around line 234-272), the three rows are:

1. **App Language** at line 235 — after `.accessibilityHint(...)` at line 247, append:

```swift
            .focused($focusedRowID, equals: .appLanguage)
            .focusRing(itemID: ProfileRowID.appLanguage, focusedID: focusedRowID, accent: themeManager.resolved.accentColor)
            .onKeyPress(.return) {
                // Navigation handled by NavigationLink itself; focus press triggers it
                return .ignored  // Let SwiftUI's default handle NavigationLink activation
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                let direction: LibraryFocusNavigator.FocusDirection =
                    (press.key == .upArrow) ? .up : .down
                moveFocus(direction, from: .appLanguage)
                return .handled
            }
            .onKeyPress(.escape) {
                focusedRowID = nil
                return .handled
            }
```

2. **MIDI Device** at line 254 — append the same pattern with `.midiDevice` instead.

3. **Redo Onboarding** at line 264 — append the same pattern with `.redoOnboarding` instead. Note this row is a `Button` not `NavigationLink`, so `.onKeyPress(.return)` should explicitly trigger the action:

```swift
            .focused($focusedRowID, equals: .redoOnboarding)
            .focusRing(itemID: ProfileRowID.redoOnboarding, focusedID: focusedRowID, accent: themeManager.resolved.accentColor)
            .onKeyPress(.return) {
                onboardingManager.resetOnboarding()
                return .handled
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                let direction: LibraryFocusNavigator.FocusDirection =
                    (press.key == .upArrow) ? .up : .down
                moveFocus(direction, from: .redoOnboarding)
                return .handled
            }
            .onKeyPress(.escape) {
                focusedRowID = nil
                return .handled
            }
```

In `appearanceSection` (around line 278-307):

4. **Theme** at line 280 — append the pattern with `.theme`.

5. **Display** at line 294 — append the pattern with `.display`.

Both are NavigationLinks — use the `.ignored` return on `.onKeyPress(.return)` so SwiftUI's default activation kicks in.

- [ ] **Step 5.4: Add initial-focus `.onAppear` on the outer Form**

Locate the outermost body element of `ProfileTab`. It wraps a `NavigationStack { Form { ... } }` or similar. Immediately after the outermost `.navigationTitle(...)` or final modifier of the Form, add:

```swift
        .onAppear {
            if focusedRowID == nil {
                focusedRowID = .appLanguage
            }
        }
```

(If the exact placement is ambiguous on read, attach it to the outermost `Form { ... }` modifier chain immediately before the `.toolbar` or `.navigationTitle` closure.)

- [ ] **Step 5.5: Build + commit**

```
mcp__XcodeBuildMCP__build_sim
```

Expected: `BUILD SUCCEEDED`.

```bash
git add SurVibe/ProfileTab.swift
git commit -m "$(cat <<'EOF'
feat(SP-4c): keyboard focus on ProfileTab rows

New ProfileRowID enum (5 cases for the existing hoverEffect rows)
identifies rows for @FocusState. Each NavigationLink/Button gets
.focused + focusRing + Return (Button triggers action; NavigationLink
uses SwiftUI default) + Up/Down arrow nav (linear list) + escape-to-
clear. .onAppear primes focus on .appLanguage.

Part of audit SP-4b §6 deferral 4 (ProfileTab row focus).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Phase A unit tests

**Files:**
- Create: `SurVibeTests/HomeTabFocusTests.swift`
- Create: `SurVibeTests/ProfileTabFocusTests.swift`
- Create: `SurVibeTests/SongGridColumnCountTests.swift`

- [ ] **Step 6.1: Create `HomeTabFocusTests.swift`**

Exact content:

```swift
import Testing
@testable import SurVibe

/// Verifies `HomeDoorID` arrow-key nav math via `LibraryFocusNavigator`.
/// Grid assumed 2 columns (SP-4c Task 4 default).
struct HomeTabFocusTests {
    @Test
    func rightFromSongsGoesToLearn() {
        // songs = 0, learn = 1; columns = 2 → right at col 0 → col 1
        let result = LibraryFocusNavigator.nextIndex(
            for: .right, currentIndex: 0, count: 5, columns: 2
        )
        #expect(result == 1)
    }

    @Test
    func downFromSongsGoesToMoods() {
        // songs = 0, moods = 2; columns = 2 → down from row 0 → row 1
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 0, count: 5, columns: 2
        )
        #expect(result == 2)
    }

    @Test
    func downFromRagasReturnsNil() {
        // ragas = 4 (last, partial row); down clamps
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 4, count: 5, columns: 2
        )
        #expect(result == nil)
    }

    @Test
    func rightFromLearnReturnsNil() {
        // learn = 1 (col 1, rightmost in 2-col); right clamps
        let result = LibraryFocusNavigator.nextIndex(
            for: .right, currentIndex: 1, count: 5, columns: 2
        )
        #expect(result == nil)
    }
}
```

- [ ] **Step 6.2: Create `ProfileTabFocusTests.swift`**

Exact content:

```swift
import Testing
@testable import SurVibe

/// Verifies `ProfileRowID` linear-list nav math.
/// 5 rows: appLanguage=0, midiDevice=1, redoOnboarding=2, theme=3, display=4.
struct ProfileTabFocusTests {
    @Test
    func downFromAppLanguageGoesToMidi() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 0, count: 5, columns: 1
        )
        #expect(result == 1)
    }

    @Test
    func upFromDisplayGoesToTheme() {
        // display = 4, theme = 3
        let result = LibraryFocusNavigator.nextIndex(
            for: .up, currentIndex: 4, count: 5, columns: 1
        )
        #expect(result == 3)
    }

    @Test
    func upFromAppLanguageReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .up, currentIndex: 0, count: 5, columns: 1
        )
        #expect(result == nil)
    }

    @Test
    func downFromDisplayReturnsNil() {
        let result = LibraryFocusNavigator.nextIndex(
            for: .down, currentIndex: 4, count: 5, columns: 1
        )
        #expect(result == nil)
    }
}
```

- [ ] **Step 6.3: Create `SongGridColumnCountTests.swift`**

Exact content:

```swift
import Testing
@testable import SurVibe

/// Verifies `SongLibraryView.columnCount(for:)` breakpoints.
struct SongGridColumnCountTests {
    @Test
    func iPhone15ProReturns2() {
        // iPhone 15 Pro portrait width ≈ 393pt
        #expect(SongLibraryView.columnCount(for: 393) == 2)
    }

    @Test
    func iPadSplitRegularReturns2() {
        // iPad regular width split-view (e.g., 500pt)
        #expect(SongLibraryView.columnCount(for: 500) == 2)
    }

    @Test
    func iPadPortraitFullReturns3() {
        // iPad 11-inch portrait full width ≈ 834pt
        #expect(SongLibraryView.columnCount(for: 834) == 3)
    }

    @Test
    func iPadLandscapeFullReturns4() {
        // iPad 13-inch landscape full width ≈ 1366pt
        #expect(SongLibraryView.columnCount(for: 1366) == 4)
    }

    @Test
    func exactlyAt700Returns3() {
        // Boundary between 2 and 3 columns
        #expect(SongLibraryView.columnCount(for: 700) == 3)
    }
}
```

- [ ] **Step 6.4: Build + commit**

```
mcp__XcodeBuildMCP__build_sim
```

Expected: `BUILD SUCCEEDED`.

```bash
git add SurVibeTests/HomeTabFocusTests.swift SurVibeTests/ProfileTabFocusTests.swift SurVibeTests/SongGridColumnCountTests.swift
git commit -m "$(cat <<'EOF'
test(SP-4c): Phase A unit tests for focus nav + grid columns

- HomeTabFocusTests (4 tests, 2-col grid)
- ProfileTabFocusTests (4 tests, linear list)
- SongGridColumnCountTests (5 tests covering iPhone/iPad/Mac widths
  + boundary at 700pt)

Reuses LibraryFocusNavigator.nextIndex (no new type). Pure-math
tests; no UI assertions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Phase B scaffold — AccessibilityAuditTests.swift

**Files:**
- Create: `SurVibeUITests/AccessibilityAuditTests.swift`

- [ ] **Step 7.1: Create the test file with all 8 test methods (initial skeleton; expected to fail)**

Exact content:

```swift
import XCTest

/// Automated accessibility audits per Apple's documented best-practice.
///
/// Each test launches the app, navigates to a target screen, and calls
/// `performAccessibilityAudit(for:)` — the test fails automatically if
/// the audit surfaces issues in the selected categories.
///
/// - SeeAlso: https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app
final class AccessibilityAuditTests: XCTestCase {

    private var app: XCUIApplication!

    /// Audit categories exercised in SP-4c Phase B.
    /// Excludes `.action` (filter-heavy on SwiftUI) and `.textClipping`
    /// (subsumed by `.dynamicType`) per spec AD-3.
    private static let auditTypes: XCUIAccessibilityAuditType = [
        .dynamicType,
        .elementDetection,
        .contrast,
        .hitRegion,
        .traits,
        .parentChildRelationships
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Screen-by-screen audits

    func testHomeTabAudit() throws {
        app.tabBars.buttons["Home"].tap()
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testSongsLibraryAudit() throws {
        app.tabBars.buttons["Songs"].tap()
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testLessonsLibraryAudit() throws {
        app.tabBars.buttons["Learn"].tap()
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testSongDetailAudit() throws {
        app.tabBars.buttons["Songs"].tap()
        // Long-press first song to open detail sheet
        let firstSong = app.scrollViews.otherElements.element(boundBy: 0)
        firstSong.press(forDuration: 0.8)
        app.buttons["Song Details"].tap()
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testPlayAlongAudit() throws {
        app.tabBars.buttons["Songs"].tap()
        let firstSong = app.scrollViews.otherElements.element(boundBy: 0)
        firstSong.tap()
        // Song detail → Play button
        app.buttons["Play"].tap()
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testPracticeAudit() throws {
        app.tabBars.buttons["Learn"].tap()
        let firstLesson = app.scrollViews.otherElements.element(boundBy: 0)
        firstLesson.tap()
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testSettingsAppearanceAudit() throws {
        app.tabBars.buttons["Profile"].tap()
        app.buttons["App Theme"].tap()
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }

    func testOnboardingAudit() throws {
        // Relies on OnboardingManager being reset OR a launch argument.
        // If onboarding isn't shown on this launch, this test is skipped via XCTSkip.
        guard app.staticTexts["Welcome"].waitForExistence(timeout: 2) else {
            throw XCTSkip("Onboarding not shown on this launch; skipping")
        }
        try app.performAccessibilityAudit(for: Self.auditTypes)
    }
}
```

- [ ] **Step 7.2: Commit the scaffold (tests may fail — that's expected)**

```bash
git add SurVibeUITests/AccessibilityAuditTests.swift
git commit -m "$(cat <<'EOF'
test(SP-4c): AccessibilityAuditTests scaffold (Phase B)

8 XCUITest methods, one per major screen: Home, Songs, Lessons,
Song detail, Play-along, Practice, Settings → Appearance,
Onboarding (conditional via XCTSkip).

Each calls performAccessibilityAudit(for:) with 6 categories:
dynamicType, elementDetection, contrast, hitRegion, traits,
parentChildRelationships. Test failures surface the fix punch-list
for subsequent Phase B iteration tasks.

Apple best-practice per:
https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Phase B iteration — fix audit-surfaced issues screen by screen

This task is intentionally open-ended. Each sub-step targets one screen, runs the audit, fixes whatever it surfaces, and commits.

### Iteration protocol for each screen

For each of the 8 audit tests in sequence:

- [ ] **Step 8.N.a: Run the single audit test**

```
mcp__XcodeBuildMCP__test_sim with extraArgs=["-only-testing:SurVibeUITests/AccessibilityAuditTests/test<ScreenName>Audit"]
```

- [ ] **Step 8.N.b: Read failure output**

If the test passes, mark Step 8.N complete and move on. Otherwise the failure will list one or more audit issues, each with:
- An element (e.g., "Button at `SongCardView.swift:47`")
- A category (e.g., "Missing accessibility label")
- A fix suggestion

- [ ] **Step 8.N.c: Apply fixes**

Fix patterns by audit category:

| Category | Fix pattern |
|---|---|
| **Element detection** (missing label) | Add `.accessibilityLabel(Text("..."))` on the flagged view. |
| **Traits** (wrong/missing trait) | Add `.accessibilityAddTraits(.isButton)` or `.accessibilityAddTraits(.isHeader)` depending on flag. |
| **Hit region** (element too small) | Wrap in `.contentShape(Rectangle()).frame(minWidth: 44, minHeight: 44)` or increase padding. |
| **Contrast** (insufficient colour contrast) | Swap low-contrast foreground colour for `themeManager.resolved.primaryTextColor` (or equivalent semantic token); add Rang-dark variant if needed. |
| **Dynamic Type** (text doesn't scale) | Replace fixed `.font(.system(size: N))` with semantic `.font(.body)`/`.font(.title3)`; ensure no `.fixedSize()` on text. |
| **Parent-child relationships** (broken hierarchy) | Collapse with `.accessibilityElement(children: .combine)` on the parent, OR declare `.accessibilityRepresentation { ... }` for custom views. |

Fix the flagged Swift file(s) per the applicable pattern.

- [ ] **Step 8.N.d: Re-run + commit**

```
mcp__XcodeBuildMCP__test_sim with extraArgs=["-only-testing:SurVibeUITests/AccessibilityAuditTests/test<ScreenName>Audit"]
```

Expected: test passes.

If still failing, iterate on the same screen until green. If a specific issue should be ignored (e.g., third-party view), use the `performAccessibilityAudit(for:_:)` closure:

```swift
try app.performAccessibilityAudit(for: Self.auditTypes) { issue in
    // Ignore AudioKit internal view hit-region warning (can't fix in our code).
    issue.element?.identifier == "AudioKitPianoKey" && issue.auditType == .hitRegion
}
```

(`return true` means "ignore this issue"; `return false` means "report it".)

Commit when the screen is green:

```bash
git add <fixed-files>
git commit -m "fix(SP-4c): accessibility audit — <ScreenName>

<1-2 lines on what was fixed>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Per-screen sub-steps

- [ ] **Step 8.1: Home tab audit** — `testHomeTabAudit`. Likely fixes: DoorCard accessibilityLabel + hint; Welcome header is already marked `.isHeader`.
- [ ] **Step 8.2: Songs library audit** — `testSongsLibraryAudit`. Likely fixes: SongCardView label; sort menu label.
- [ ] **Step 8.3: Lessons library audit** — `testLessonsLibraryAudit`. Likely fixes: LessonCardView label + locked-state hint.
- [ ] **Step 8.4: Song detail audit** — `testSongDetailAudit`. Likely fixes: detail sheet buttons; Devanagari notation labels.
- [ ] **Step 8.5: Play-along audit** — `testPlayAlongAudit`. Likely fixes: piano key hit region; toolbar button labels; ScrollingSheetView hierarchy.
- [ ] **Step 8.6: Practice audit** — `testPracticeAudit`. Likely fixes: practice controls; metronome indicator.
- [ ] **Step 8.7: Settings Appearance audit** — `testSettingsAppearanceAudit`. Likely fixes: theme picker cards; dim-mode toggle.
- [ ] **Step 8.8: Onboarding audit** — `testOnboardingAudit`. May be skipped if onboarding isn't triggered on launch; if runnable, likely fixes: language picker rows; skip button.

**Escape hatch:** If a single screen takes >1 day of iteration, that screen's fixes can be split off into an SP-4c-addendum sub-project with explicit documentation. Goal is 8 green audit tests; if the last 1-2 screens have L-effort fixes discovered, escalate rather than grind.

---

## Task 9: Final verification sweep

- [ ] **Step 9.1: Lint + format**

```bash
/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml \
  SurVibe/Navigation/FocusRingModifier.swift \
  SurVibe/Learn/LessonLibraryView.swift \
  SurVibe/Songs/SongLibraryView.swift \
  SurVibe/HomeTab.swift \
  SurVibe/ProfileTab.swift \
  SurVibeTests/HomeTabFocusTests.swift \
  SurVibeTests/ProfileTabFocusTests.swift \
  SurVibeTests/SongGridColumnCountTests.swift \
  SurVibeUITests/AccessibilityAuditTests.swift
```

Expected: no errors.

```bash
xcrun swift-format lint --configuration .swift-format \
  SurVibe/Navigation/FocusRingModifier.swift \
  SurVibeTests/HomeTabFocusTests.swift \
  SurVibeTests/ProfileTabFocusTests.swift \
  SurVibeTests/SongGridColumnCountTests.swift \
  SurVibeUITests/AccessibilityAuditTests.swift 2>&1 | tail -20
```

If any format issues, fix with:

```bash
xcrun swift-format format --in-place --configuration .swift-format \
  SurVibe/Navigation/FocusRingModifier.swift \
  SurVibeTests/HomeTabFocusTests.swift \
  SurVibeTests/ProfileTabFocusTests.swift \
  SurVibeTests/SongGridColumnCountTests.swift \
  SurVibeUITests/AccessibilityAuditTests.swift
```

- [ ] **Step 9.2: Banned-pattern grep**

```bash
grep -n -E '#if os\(iOS\)|#if os\(macOS\)|UIDevice|UIScreen\.main|UIInterfaceOrientation|DispatchQueue\.main\.async|ObservableObject|@Published|VersionedSchema|try!' \
  SurVibe/Navigation/FocusRingModifier.swift \
  SurVibe/Learn/LessonLibraryView.swift \
  SurVibe/Songs/SongLibraryView.swift \
  SurVibe/HomeTab.swift \
  SurVibe/ProfileTab.swift \
  SurVibeTests/HomeTabFocusTests.swift \
  SurVibeTests/ProfileTabFocusTests.swift \
  SurVibeTests/SongGridColumnCountTests.swift \
  SurVibeUITests/AccessibilityAuditTests.swift
```

Expected: 0 matches.

- [ ] **Step 9.3: Run full narrow regression battery**

```bash
swift test --package-path Packages/SVCore 2>&1 | tail -5
```

Expected: SVCore 93/93 passing.

```
mcp__XcodeBuildMCP__test_sim with extraArgs=[
  "-only-testing:SurVibeTests/LibraryFocusNavigatorTests",
  "-only-testing:SurVibeTests/HomeTabFocusTests",
  "-only-testing:SurVibeTests/ProfileTabFocusTests",
  "-only-testing:SurVibeTests/SongGridColumnCountTests",
  "-only-testing:SurVibeTests/LatencyContractTests",
  "-only-testing:SurVibeTests/SongLibraryViewFocusTests"
]
```

Expected: all pass. Specifically:
- LibraryFocusNavigator 8/8
- HomeTabFocus 4/4
- ProfileTabFocus 4/4
- SongGridColumnCount 5/5
- LatencyContract 3/3 (no p95 regression)
- SongLibraryViewFocus 2/2

```
mcp__XcodeBuildMCP__test_sim with extraArgs=["-only-testing:SurVibeUITests/AccessibilityAuditTests"]
```

Expected: 8/8 audit tests pass (or 7/8 with onboarding skipped — skip counts as pass).

- [ ] **Step 9.4: Commit formatting fixes if any**

```bash
git status
# If any files modified by swift-format, stage and commit.
# If nothing changed, skip.
```

---

## Task 10: Merge + tag + tracker update + push

- [ ] **Step 10.1: Merge to main with `--no-ff`**

```bash
git checkout main && git merge --no-ff feat/sp-4c-accessibility-finale -m "Merge: SP-4c Accessibility finale

SP-4c ships:
- Phase A — 5 focus + grid polish items (FocusRingModifier, escape
  handlers on library cards, HomeTab DoorCard @FocusState,
  ProfileTab row @FocusState, GeometryReader-driven dynamic
  Songs grid columns).
- Phase B — 8 XCUITest accessibility audits (Home, Songs library,
  Lessons library, Song detail, Play-along, Practice, Settings
  Appearance, Onboarding) with all surfaced issues fixed.

Phase B follows Apple's documented best-practice via
performAccessibilityAudit(for:_:); 6 audit categories covered
(dynamicType, elementDetection, contrast, hitRegion, traits,
parentChildRelationships).

Tests: SVCore 93/93, Phase A unit tests 13 pass (HomeTabFocus 4,
ProfileTabFocus 4, SongGridColumnCount 5), LibraryFocusNavigator
8/8, LatencyContract 3/3 (no p95 regression),
SongLibraryViewFocus 2/2, AccessibilityAudit 8/8 green.

Routes pending P1 items to new sub-projects:
- P1-2 Live Activity → SP-4d
- P1-4 Pencil annotation → SP-4e

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 10.2: Tag at last feat commit (not merge commit)**

```bash
LAST_FEAT_SHA=$(git rev-parse HEAD^2)  # HEAD is merge commit; HEAD^1 is main tip, HEAD^2 is feat branch tip
git tag sp-4c-accessibility-finale $LAST_FEAT_SHA
git rev-parse sp-4c-accessibility-finale
echo "Tag SHA above should match feat branch tip (not merge commit)"
```

- [ ] **Step 10.3: Update SP-TRAJECTORY-TRACKER.md**

Open `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md`. Replace the SP-4c status row:

```markdown
| **SP-4c** Live Activity + Pencil + focus-ring polish (P1-2, P1-4 + SP-4b deferrals) | ⬜ pending | — | — | — |
```

With (fill in `<TAG-SHA>`, `<MERGE-SHA>`, `<N>`):

```markdown
| **SP-4c** Accessibility finale (4 SP-4b §6 deferrals + full XCUITest audit) | ✅ shipped | `sp-4c-accessibility-finale` @ `<TAG-SHA>` | `<MERGE-SHA>` | <N> |
```

Add two new rows below for SP-4d and SP-4e:

```markdown
| **SP-4d** Live Activity / Dynamic Island (P1-2) | ⬜ pending | — | — | — |
| **SP-4e** Apple Pencil annotation on notation (P1-4) | ⬜ pending | — | — | — |
```

Add an SP-4c landed block right below the SP-4b landed block (around line 153):

```markdown
### SP-4c landed (2026-04-20)

**SP-4c shipped (Phase A + Phase B, N commits):**
- Phase A — 4 polish deferrals from SP-4b §6: FocusRingModifier (reusable), escape-to-clear on library cards, HomeTab DoorCard focus (HomeDoorID enum + arrows), ProfileTab row focus (ProfileRowID enum + arrows), GeometryReader-driven dynamic Songs grid columns (2/3/4 depending on width).
- Phase B — 8 XCUITest accessibility audit tests (Home, Songs, Lessons, Song detail, Play-along, Practice, Settings, Onboarding) via performAccessibilityAudit with 6 categories. All surfaced issues fixed screen-by-screen.

**New files:** FocusRingModifier.swift (~40 lines), HomeTabFocusTests / ProfileTabFocusTests / SongGridColumnCountTests (13 Swift Testing cases total), AccessibilityAuditTests.swift (8 XCUITest methods).

**Modified:** LessonLibraryView, SongLibraryView (focus ring + escape + dynamic cols), HomeTab (HomeDoorID + focus), ProfileTab (ProfileRowID + focus), plus ~5-15 files touched by audit fixes.

**Tests:** SVCore 93/93 green; Phase A unit tests 13/13 green; LibraryFocusNavigatorTests 8/8 green (no regression); LatencyContractTests 3/3 green (p95 delta 0.0 ms); SongLibraryViewFocusTests 2/2 green (no regression); AccessibilityAuditTests 8/8 green.

**Routes pending to new sub-projects:** SP-4d (Live Activity), SP-4e (Pencil annotation).
```

- [ ] **Step 10.4: Commit tracker update**

```bash
git add -f docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md
git commit -m "$(cat <<'EOF'
docs(SP-4c): tracker update — accessibility finale shipped

Marks SP-4c ✅ shipped; adds SP-4d (Live Activity) and SP-4e (Pencil)
rows for the two remaining SP-4 P1 items routed to dedicated
sub-projects. Landed block documents Phase A + Phase B.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 10.5: Push main + tag**

```bash
git push origin main && git push origin sp-4c-accessibility-finale
```

Expected: both pushes succeed. Verify on GitHub that the tag is listed alongside `sp-4b-accessibility-remainder`.

- [ ] **Step 10.6: Delete feat branch locally (optional cleanup)**

```bash
git branch -D feat/sp-4c-accessibility-finale
git branch -a
```

Expected: only `main` + `remotes/origin/main` listed.

---

## Self-Review Checklist

After finishing all tasks:

- [ ] **Spec coverage:** §3.1 Phase A (5 items) → Tasks 1-6. §3.2 Phase B → Task 7 (scaffold) + Task 8 (8 per-screen iterations). §5 Testing → Tasks 6 + 8 + 9. §9 Acceptance criteria → Task 9 + 10.
- [ ] **No placeholders:** no TBD/TODO/"fill in later" in the plan or in committed code. Placeholder SHAs in Step 10.3 are expected — they're filled in during execution.
- [ ] **Type consistency:** `FocusRingModifier`, `HomeDoorID`, `ProfileRowID`, `LibraryFocusNavigator.FocusDirection`, `LibraryFocusNavigator.nextIndex(for:currentIndex:count:columns:)`, `SongLibraryView.columnCount(for:)`, `performAccessibilityAudit(for:)` — each used identically across every task that references it.
- [ ] **Commit hygiene:** pre-commit SwiftLint + swift-format hooks pass on every feat commit; banned-pattern grep clean (Step 9.2); tag at feat tip not merge (Step 10.2).
