import Testing
@testable import Visor

struct ActivityTests {
    @Test
    func noActivitiesResolveToNil() {
        #expect(resolveCurrentActivity([:]) == nil)
    }

    @Test
    func nowPlayingWinsWhenItIsTheOnlyActivity() {
        #expect(resolveCurrentActivity([.nowPlaying: Activity(kind: .nowPlaying)])?.kind == .nowPlaying)
    }

    @Test
    func chargingPeekOutranksNowPlaying() {
        let activities: [ActivityKind: Activity] = [
            .nowPlaying: Activity(kind: .nowPlaying),
            .charging: Activity(kind: .charging),
        ]
        #expect(resolveCurrentActivity(activities)?.kind == .charging)
    }

    @Test
    func endingTheChargingPeekFallsBackToNowPlaying() {
        var activities: [ActivityKind: Activity] = [
            .nowPlaying: Activity(kind: .nowPlaying),
            .charging: Activity(kind: .charging),
        ]
        activities.removeValue(forKey: .charging)
        #expect(resolveCurrentActivity(activities)?.kind == .nowPlaying)
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
