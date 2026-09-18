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
            .charging: Activity(kind: .charging)
        ]
        #expect(resolveCurrentActivity(activities)?.kind == .charging)
    }

    @Test
    func endingTheChargingPeekFallsBackToNowPlaying() {
        var activities: [ActivityKind: Activity] = [
            .nowPlaying: Activity(kind: .nowPlaying),
            .charging: Activity(kind: .charging)
        ]
        activities.removeValue(forKey: .charging)
        #expect(resolveCurrentActivity(activities)?.kind == .nowPlaying)
    }

    @Test
    func screenshotOutranksEverything() {
        let activities: [ActivityKind: Activity] = [
            .nowPlaying: Activity(kind: .nowPlaying),
            .charging: Activity(kind: .charging),
            .screenshot: Activity(kind: .screenshot)
        ]
        #expect(resolveCurrentActivity(activities)?.kind == .screenshot)
    }

    @Test
    func dismissingAScreenshotFallsBackToTheChargingPeek() {
        var activities: [ActivityKind: Activity] = [
            .nowPlaying: Activity(kind: .nowPlaying),
            .charging: Activity(kind: .charging),
            .screenshot: Activity(kind: .screenshot)
        ]
        activities.removeValue(forKey: .screenshot)
        #expect(resolveCurrentActivity(activities)?.kind == .charging)
    }

    @Test
    func waveOutranksChargingAndNowPlayingButNotScreenshot() {
        let activities: [ActivityKind: Activity] = [
            .nowPlaying: Activity(kind: .nowPlaying),
            .charging: Activity(kind: .charging),
            .wave: Activity(kind: .wave)
        ]
        #expect(resolveCurrentActivity(activities)?.kind == .wave)
        #expect(
            resolveCurrentActivity(activities.merging([.screenshot: Activity(kind: .screenshot)]) { _, new in new })?
                .kind == .screenshot
        )
    }

    @Test
    func greetingIsTheLowestPriorityActivity() {
        let activities: [ActivityKind: Activity] = [
            .greeting: Activity(kind: .greeting),
            .nowPlaying: Activity(kind: .nowPlaying)
        ]
        #expect(resolveCurrentActivity(activities)?.kind == .nowPlaying)
        #expect(resolveCurrentActivity([.greeting: Activity(kind: .greeting)])?.kind == .greeting)
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
