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
    /// No-op if the target tab is already selected.
    ///
    /// - Parameter tab: The target tab to select.
    func switchTab(to tab: AppTab) {
        guard currentTab != tab else { return }
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
