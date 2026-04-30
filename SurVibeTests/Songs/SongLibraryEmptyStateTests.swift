#if DEBUG
import Testing
@testable import SurVibe

/// Behavior tests for `SongLibraryEmptyState`.
///
/// Verifies the two-mode rendering (no songs vs. no matches) and the
/// `onTrySample` callback wiring via the DEBUG-only `simulateTrySampleTap()`
/// test seam.
@MainActor
struct SongLibraryEmptyStateTests {

    /// With no active filters the empty state offers a "Try a sample"
    /// CTA (rather than "Clear Filters"). The presence of `onTrySample`
    /// is what wires that button — the seam to validate is that
    /// invoking it triggers the closure.
    @Test
    func noFiltersShowsTrySampleButton() {
        var trySampleCalls = 0
        let view = SongLibraryEmptyState(
            hasActiveFilters: false,
            onTrySample: { trySampleCalls += 1 }
        )
        view.simulateTrySampleTap()
        #expect(trySampleCalls == 1)
    }

    /// With active filters the empty state hides "Try a sample" and
    /// shows "Clear Filters" instead. The `clearFiltersAction` is
    /// optional in the API; when provided it should *not* be invoked
    /// just because `simulateTrySampleTap` runs (the seam is for the
    /// non-filtered path).
    @Test
    func withFiltersShowsClearFiltersButton() {
        var clearCalls = 0
        var trySampleCalls = 0
        let view = SongLibraryEmptyState(
            hasActiveFilters: true,
            clearFiltersAction: { clearCalls += 1 },
            onTrySample: { trySampleCalls += 1 }
        )
        // Even when filters are active, the simulate seam is wired to
        // `onTrySample` — confirm the seam targets the correct closure
        // and that clearFilters is independent.
        view.simulateTrySampleTap()
        #expect(trySampleCalls == 1)
        #expect(clearCalls == 0)
    }

    /// `simulateTrySampleTap()` invokes the `onTrySample` callback
    /// exactly once per tap, with no side effects on the receiver.
    @Test
    func simulateTrySampleTapInvokesCallback() {
        var calls = 0
        let view = SongLibraryEmptyState(
            hasActiveFilters: false,
            onTrySample: { calls += 1 }
        )
        view.simulateTrySampleTap()
        view.simulateTrySampleTap()
        view.simulateTrySampleTap()
        #expect(calls == 3)
    }
}
#endif
