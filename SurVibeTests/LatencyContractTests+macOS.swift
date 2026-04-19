// SurVibeTests/LatencyContractTests+macOS.swift
//
// Mac-specific latency regression tests. No-op on iOS CI.
// Populated in SP-6 with a Mac-specific p95 budget (5–15 ms expected).

#if os(macOS)
import Testing

@Suite("Latency contracts — macOS")
struct LatencyContractTestsMac {
    @Test func macP95WithinMacBudget() async throws {
        // TODO(SP-6): implement Mac latency measurement and assertion
        //  against the Mac-specific p95 budget.
    }
}
#endif
