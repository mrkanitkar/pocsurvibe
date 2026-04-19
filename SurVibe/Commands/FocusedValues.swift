// SurVibe/Commands/FocusedValues.swift
import SwiftUI

/// Actions a focused play-along surface publishes for keyboard-shortcut dispatch.
///
/// Published via `.focusedSceneValue(\.transportActions, ...)` on the active
/// play-along surface. Consumed via `@FocusedValue(\.transportActions)` inside
/// `TransportCommands`. When no play-along surface is focused, the focused
/// value is `nil` and `TransportCommands` disables its buttons.
struct TransportActions {
    var playPause: () -> Void
    var seekBackward: () -> Void
    var seekForward: () -> Void
    var stop: () -> Void
}

extension FocusedValues {
    @Entry
    var transportActions: TransportActions? = nil
}
