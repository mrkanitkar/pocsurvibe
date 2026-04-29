import SwiftUI

/// The user action that the guard is currently intercepting.
///
/// `tabChange` carries the destination tab so the resolver can advance to it
/// after the user picks Save / Discard. `newSession` corresponds to the
/// ⋯ → "New session" toolbar entry — there is no destination tab, the
/// resolver only needs to know which side won.
enum GuardAction: Equatable {
    case tabChange(to: AppTab)
    case newSession
}

/// Outcome returned by the user from the confirmation dialog.
enum GuardOutcome: Equatable {
    case save
    case discard
    case cancel
}

/// Holds the pending action and resolution callback for the
/// "you have unsaved scratchpad recording" confirmation dialog.
///
/// The Play tab's scratchpad is always-recording: any tab switch or
/// ⋯ → "New session" tap with `scratchpad.hasContent == true` must be
/// intercepted, the user must be asked Save / Discard / Cancel, and the
/// pending action only completes after they choose. `UnsavedScratchpadGuard`
/// is the small piece of state that lets `ContentView` show the
/// `confirmationDialog` and route the answer back to whichever site raised
/// the action (`AppRouter.switchTab(to:)` for tab changes, the toolbar's
/// New-session button otherwise).
///
/// Spec §5.8 + §9-2 (rollback approach). Marked `@Observable` per
/// SurVibe rules — the legacy Combine observable protocol is banned.
@Observable
@MainActor
final class UnsavedScratchpadGuard {
    /// The currently pending action, or `nil` when no dialog is active.
    /// Drives the `confirmationDialog` `isPresented` binding.
    var pending: GuardAction?

    /// Callback invoked exactly once when the user chooses an outcome.
    /// `@ObservationIgnored` because mutating the closure should never
    /// invalidate observers (it's a sink, not a source of UI state).
    @ObservationIgnored
    var onResolve: ((GuardOutcome) -> Void)?

    init() {}

    /// Raise a guarded action. The caller supplies the resolution closure;
    /// the dialog (driven by `pending != nil`) presents Save / Discard /
    /// Cancel buttons that all funnel into ``answer(_:)``.
    func raise(_ action: GuardAction, then resolve: @escaping (GuardOutcome) -> Void) {
        pending = action
        onResolve = resolve
    }

    /// Resolve the pending action. Invokes the stored callback exactly once
    /// and clears the dialog state. No-op if no action is pending.
    func answer(_ outcome: GuardOutcome) {
        let resolver = onResolve
        onResolve = nil
        pending = nil
        resolver?(outcome)
    }
}
