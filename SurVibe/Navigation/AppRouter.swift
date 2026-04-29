import SVCore
import SwiftUI
import os.log

/// Centralized navigation router managing tab selection and per-tab navigation paths.
///
/// AppRouter is an `@Observable` class injected into the environment. It provides
/// programmatic tab switching, push/pop navigation within each tab's NavigationStack,
/// and binding accessors for NavigationStack path parameters.
///
/// ## Usage
/// ```swift
/// @Environment(AppRouter.self) private var router
/// router.switchTab(to: .songs)
/// router.navigate(to: .songDetail(song))
/// ```
@Observable
@MainActor
final class AppRouter {
    // MARK: - Properties

    /// The currently selected tab.
    private(set) var currentTab: AppTab = .home

    /// Independent navigation paths for each tab.
    private var navigationPaths: [AppTab: [AppDestination]] = [:]

    /// Logger for navigation events.
    private static let logger = Logger.survibe(category: "AppRouter")

    // MARK: - Play tab guard hooks

    /// Shared guard surface used by the Play tab's "unsaved scratchpad"
    /// protection. `ContentView` creates the guard, attaches it here, and
    /// renders the `confirmationDialog` driven by `guard.pending`. When the
    /// guard is `nil` (e.g. early launch, previews), `switchTab(to:)` falls
    /// through to its v1 behaviour.
    var scratchpadGuard: UnsavedScratchpadGuard?

    /// Closure that reports whether the Play tab's scratchpad has captured
    /// content. Wired by `PlayTab` on appear; `nil` when Play is unmounted
    /// (in which case `switchTab(to:)` skips the guard).
    var playTabHasUnsavedContent: (() -> Bool)?

    /// Closure that wipes the Play tab scratchpad. Invoked from the guard's
    /// "Discard" branch so the tab change can complete cleanly.
    var clearPlayTabScratchpad: (() -> Void)?

    /// Closure that presents the Save Take sheet. Invoked from the guard's
    /// "Save" branch — after the sheet's onSave completes the take is
    /// persisted and the scratchpad frozen, so we can advance the tab.
    var presentSaveTakeSheet: (() -> Void)?

    // MARK: - Initialization

    /// Creates a new AppRouter with empty navigation stacks for all tabs.
    init() {
        for tab in AppTab.allCases {
            navigationPaths[tab] = []
        }
    }

    // MARK: - Public Methods

    /// Switch to a different tab.
    ///
    /// No-op if the target tab is already selected. If the user is leaving
    /// the Play tab while its scratchpad has unsaved content, the switch is
    /// deferred and routed through ``UnsavedScratchpadGuard``: the guard
    /// raises a Save / Discard / Cancel confirmation dialog (rendered by
    /// `ContentView`), and the actual `currentTab = tab` assignment happens
    /// only after the user picks Save (after the sheet completes) or
    /// Discard.
    ///
    /// - Parameter tab: The target tab to select.
    func switchTab(to tab: AppTab) {
        guard currentTab != tab else { return }

        // Intercept tab-leave when the Play tab has unsaved scratchpad
        // content. Any of the three hooks missing means the guard isn't
        // wired yet (early launch, preview) — fall through to v1 behaviour.
        if currentTab == .play,
            let hasContent = playTabHasUnsavedContent,
            hasContent(),
            let guardObj = scratchpadGuard
        {
            guardObj.raise(.tabChange(to: tab)) { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .save:
                    // Caller of presentSaveTakeSheet is responsible for
                    // calling switchTab(to:) again after the save completes.
                    self.presentSaveTakeSheet?()
                case .discard:
                    self.clearPlayTabScratchpad?()
                    self.performSwitch(to: tab)
                case .cancel:
                    break  // already rolled back; stay on Play
                }
            }
            return
        }

        performSwitch(to: tab)
    }

    /// Unguarded tab assignment. Separated so the guard's resolver can
    /// invoke it after the user picks Discard (or after a Save completes).
    private func performSwitch(to tab: AppTab) {
        Self.logger.debug(
            "Tab switch: \(self.currentTab.rawValue, privacy: .public) → \(tab.rawValue, privacy: .public)"
        )
        currentTab = tab
    }

    /// Push a destination onto the current tab's navigation stack.
    ///
    /// - Parameter destination: The destination to navigate to.
    func navigate(to destination: AppDestination) {
        navigationPaths[currentTab, default: []].append(destination)
    }

    /// Pop the current tab's navigation stack to its root.
    func popToRoot() {
        navigationPaths[currentTab] = []
    }

    /// Pop the top destination from the current tab's navigation stack.
    ///
    /// No-op if the stack is already empty.
    func pop() {
        guard navigationPaths[currentTab, default: []].isEmpty == false else { return }
        navigationPaths[currentTab, default: []].removeLast()
    }

    /// Returns a binding to the navigation path for a specific tab.
    ///
    /// Used by `NavigationStack(path:)` in ContentView to bind each tab's
    /// navigation state to its corresponding stack.
    ///
    /// - Parameter tab: The tab to get the path for.
    /// - Returns: A `Binding<[AppDestination]>` for the tab's navigation stack.
    func pathForTab(_ tab: AppTab) -> Binding<[AppDestination]> {
        Binding(
            get: { [weak self] in
                self?.navigationPaths[tab] ?? []
            },
            set: { [weak self] newPath in
                self?.navigationPaths[tab] = newPath
            }
        )
    }

    // MARK: - SP-2: NavigationSplitView column selection

    /// Highlighted song in Songs tab's NavigationSplitView sidebar.
    /// `nil` = nothing selected (detail column renders `ContentUnavailableView`).
    var selectedSongID: Song.ID?

    /// Highlighted lesson in Learn tab's NavigationSplitView sidebar.
    var selectedLessonID: Lesson.ID?

    /// Deep-link: switch to Songs tab and select a song in the sidebar.
    ///
    /// - Parameters:
    ///   - songID: The Song's `UUID` identifier.
    ///   - analytics: Analytics sink (test-injection seam). Defaults to the shared singleton.
    func openSong(
        _ songID: Song.ID,
        analytics: (any AnalyticsProviding)? = nil
    ) {
        switchTab(to: .songs)
        selectedSongID = songID
        let provider = analytics ?? AnalyticsManager.shared
        provider.track(.sidebarUsed, properties: ["destination": "song"])
        Self.logger.debug("Deep-link: open song")
    }

    /// Deep-link: switch to Learn tab and select a lesson in the sidebar.
    ///
    /// - Parameters:
    ///   - lessonID: The Lesson's `UUID` identifier.
    ///   - analytics: Analytics sink (test-injection seam). Defaults to the shared singleton.
    func openLesson(
        _ lessonID: Lesson.ID,
        analytics: (any AnalyticsProviding)? = nil
    ) {
        switchTab(to: .learn)
        selectedLessonID = lessonID
        let provider = analytics ?? AnalyticsManager.shared
        provider.track(.sidebarUsed, properties: ["destination": "lesson"])
        Self.logger.debug("Deep-link: open lesson")
    }
}
