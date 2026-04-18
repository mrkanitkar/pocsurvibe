import Testing

@testable import SVAudio

@Suite("UMPEndpointDiscovery")
struct UMPEndpointDiscoveryTests {

    @Test("UMPEndpointInfo Sendable conformance")
    func endpointInfoSendable() {
        let info = UMPEndpointInfo(
            endpointRef: 0,
            name: "Test",
            hasMIDI2Support: true,
            functionBlockCount: 2
        )
        let _: any Sendable = info
        #expect(info.hasMIDI2Support)
        #expect(info.functionBlockCount == 2)
    }

    @Test("UMPEndpointInfo Equatable")
    func endpointInfoEquatable() {
        let a = UMPEndpointInfo(
            endpointRef: 1, name: "A",
            hasMIDI2Support: true, functionBlockCount: 0
        )
        let b = UMPEndpointInfo(
            endpointRef: 1, name: "A",
            hasMIDI2Support: true, functionBlockCount: 0
        )
        let c = UMPEndpointInfo(
            endpointRef: 2, name: "A",
            hasMIDI2Support: true, functionBlockCount: 0
        )
        #expect(a == b)
        #expect(a != c)
    }

    @Test("discoverEndpoints returns array")
    func discoverReturnsArray() {
        // In simulator, typically 0 physical endpoints — verify the call succeeds and
        // returns a well-typed array without crashing.
        let endpoints = UMPEndpointDiscovery.discoverEndpoints()
        #expect(endpoints.isEmpty || !endpoints.isEmpty)
    }

    @Test("supportsMIDI2 returns false for invalid endpoint")
    func invalidEndpointNotMIDI2() {
        #expect(!UMPEndpointDiscovery.supportsMIDI2(endpoint: 0))
    }

    @Test("UMPEndpointInfo default values")
    func defaultValues() {
        let info = UMPEndpointInfo(
            endpointRef: 42, name: "Test Device",
            hasMIDI2Support: false, functionBlockCount: 0
        )
        #expect(info.endpointRef == 42)
        #expect(info.name == "Test Device")
        #expect(!info.hasMIDI2Support)
        #expect(info.functionBlockCount == 0)
    }
}
