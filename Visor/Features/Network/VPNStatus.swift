import Foundation
import SystemConfiguration

/// Whether a VPN is actually up, and what it is called.
///
/// The obvious check — does an interface called `utun*` exist — is wrong, and
/// the reference implementation this is ported from used it as its primary
/// signal. macOS creates `utun` interfaces for Handoff, Continuity, AirDrop
/// and iCloud Private Relay on a machine with no VPN configured at all, so
/// that check reports a VPN almost permanently.
///
/// What is actually true is the dynamic store: a VPN service publishes a
/// `State:/Network/Service/<id>/{PPP,IPSec,VPN}` key while it is connected
/// and removes it when it drops. Matching those service IDs against the
/// configured services also gives us the VPN's name for free.
enum VPNStatus {
    /// The dynamic-store key patterns a live VPN service publishes.
    static let statePatterns = [
        "State:/Network/Service/.*/PPP",
        "State:/Network/Service/.*/IPSec",
        "State:/Network/Service/.*/VPN"
    ]

    /// The service ID embedded in a `State:/Network/Service/<id>/...` key.
    /// Pure, so the parsing is testable without a live VPN.
    static func serviceID(fromKey key: String) -> String? {
        let components = key.split(separator: "/")
        guard
            let index = components.firstIndex(of: "Service"),
            components.indices.contains(index + 1)
        else {
            return nil
        }
        return String(components[index + 1])
    }

    static func activeServiceIDs(_ keys: [String]) -> Set<String> {
        Set(keys.compactMap(serviceID(fromKey:)))
    }

    /// The name of whichever configured service is currently up, or nil when
    /// none is. Nil is "no VPN", not "unknown".
    static func current() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "com.apurvamukherjee.visor.vpn" as CFString, nil, nil) else {
            return nil
        }
        let keys = statePatterns.flatMap { pattern in
            SCDynamicStoreCopyKeyList(store, pattern as CFString) as? [String] ?? []
        }
        let active = activeServiceIDs(keys)
        guard !active.isEmpty else { return nil }
        guard
            let preferences = SCPreferencesCreate(nil, "com.apurvamukherjee.visor.vpn" as CFString, nil),
            let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService]
        else {
            // The keys say a VPN is up even if we cannot name it.
            return "VPN"
        }
        let name = services
            .filter { active.contains(SCNetworkServiceGetServiceID($0) as String? ?? "") }
            .compactMap { (SCNetworkServiceGetName($0) as String?)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return name ?? "VPN"
    }
}
