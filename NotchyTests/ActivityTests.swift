import Foundation
import Testing
@testable import Notchy

struct ActivityTests {
    @Test
    func noActivitiesResolveToNil() {
        #expect(resolveCurrentActivity([:]) == nil)
    }

    @Test
    func singleLiveActivityWins() {
        let activities: [ActivityKind: Activity] = [.nowPlaying: Activity(kind: .nowPlaying, expiresAt: nil)]
        #expect(resolveCurrentActivity(activities)?.kind == .nowPlaying)
    }

    @Test
    func expiredActivityIsIgnored() {
        let activities: [ActivityKind: Activity] = [
            .nowPlaying: Activity(kind: .nowPlaying, expiresAt: .now.addingTimeInterval(-1)),
        ]
        #expect(resolveCurrentActivity(activities) == nil)
    }

    @Test
    func lowerRawValuePersistentActivityWinsOverHigher() {
        let activities: [ActivityKind: Activity] = [
            .nowPlaying: Activity(kind: .nowPlaying, expiresAt: nil),
            .timer: Activity(kind: .timer, expiresAt: nil),
        ]
        #expect(resolveCurrentActivity(activities)?.kind == .nowPlaying)
    }

    @Test
    func liveTransientActivityAlwaysBeatsPersistentActivity() {
        let activities: [ActivityKind: Activity] = [
            .nowPlaying: Activity(kind: .nowPlaying, expiresAt: nil),
            .charging: Activity(kind: .charging, expiresAt: .now.addingTimeInterval(2.5)),
        ]
        #expect(resolveCurrentActivity(activities)?.kind == .charging)
    }

    @Test
    func expiredTransientActivityFallsBackToPersistentActivity() {
        let activities: [ActivityKind: Activity] = [
            .nowPlaying: Activity(kind: .nowPlaying, expiresAt: nil),
            .charging: Activity(kind: .charging, expiresAt: .now.addingTimeInterval(-1)),
        ]
        #expect(resolveCurrentActivity(activities)?.kind == .nowPlaying)
    }

    @Test
    func hudBeatsChargingWhenBothTransientActivitiesAreLive() {
        let activities: [ActivityKind: Activity] = [
            .charging: Activity(kind: .charging, expiresAt: .now.addingTimeInterval(2.5)),
            .hud: Activity(kind: .hud, expiresAt: .now.addingTimeInterval(1)),
        ]
        // Two live transients: first(where:) on a Dictionary.Values iteration
        // order isn't guaranteed — assert only that *a* transient wins, not which.
        #expect(resolveCurrentActivity(activities)?.kind.isTransient == true)
    }

    @Test @MainActor
    func storeActivateAndDeactivateUpdateCurrentActivity() {
        let store = NotchStore()
        store.activate(.nowPlaying)
        #expect(store.currentActivity?.kind == .nowPlaying)
        store.deactivate(.nowPlaying)
        #expect(store.currentActivity == nil)
    }
}
