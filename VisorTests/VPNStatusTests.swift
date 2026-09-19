import Testing
@testable import Visor

struct VPNStatusTests {
    @Test
    func pullsTheServiceIDOutOfADynamicStoreKey() {
        #expect(
            VPNStatus.serviceID(fromKey: "State:/Network/Service/ABC-123/IPSec") == "ABC-123"
        )
        #expect(
            VPNStatus.serviceID(fromKey: "State:/Network/Service/ABC-123/PPP") == "ABC-123"
        )
    }

    @Test
    func ignoresKeysThatAreNotServiceKeys() {
        #expect(VPNStatus.serviceID(fromKey: "State:/Network/Global/IPv4") == nil)
        #expect(VPNStatus.serviceID(fromKey: "State:/Network/Service") == nil)
    }

    /// One VPN publishes several keys; it is still one service.
    @Test
    func collapsesSeveralKeysForOneServiceIntoOneID() {
        let ids = VPNStatus.activeServiceIDs([
            "State:/Network/Service/ABC-123/IPSec",
            "State:/Network/Service/ABC-123/PPP",
            "State:/Network/Global/IPv4"
        ])
        #expect(ids == ["ABC-123"])
    }

    @Test
    func noKeysMeansNoVPN() {
        #expect(VPNStatus.activeServiceIDs([]).isEmpty)
    }
}
