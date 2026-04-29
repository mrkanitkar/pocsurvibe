import SwiftUI

/// Represents the five main tabs in SurVibe's tab bar.
///
/// Each tab case provides its display label and SF Symbol for consistent
/// rendering across the tab bar and any tab-related UI.
///
/// Real-instrument pitch detection lives inside the play-along experience
/// (`SongPlayAlongView`) and the Sing/Exercise lesson steps; the standalone
/// Play tab provides a free-form practice surface with live MIDI/keyboard
/// input.
enum AppTab: String, CaseIterable, Hashable {
    case home
    case learn
    case play
    case songs
    case profile

    /// Localized display label for the tab.
    var label: String {
        switch self {
        case .home: "Home"
        case .learn: "Learn"
        case .play: "Play"
        case .songs: "Songs"
        case .profile: "Profile"
        }
    }

    /// SF Symbol name used for the tab icon.
    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .learn: "book.fill"
        case .play: "pianokeys"
        case .songs: "music.note.list"
        case .profile: "person.circle.fill"
        }
    }
}

// MARK: - Keyboard Shortcuts

extension AppTab {
    /// Keyboard-shortcut digit for ⌘1–⌘5 tab switching.
    var keyEquivalent: KeyEquivalent {
        switch self {
        case .home: "1"
        case .learn: "2"
        case .play: "3"
        case .songs: "4"
        case .profile: "5"
        }
    }
}
