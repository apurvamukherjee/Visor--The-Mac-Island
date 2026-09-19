import Testing
@testable import Visor

/// The expanded island answers a different question from the wings: a peek
/// that outranks music in the compact state must never replace the music
/// card when the user hovers.
struct ExpandedResolutionTests {
    private func activities(_ kinds: [ActivityKind]) -> [ActivityKind: Activity] {
        Dictionary(uniqueKeysWithValues: kinds.map { ($0, Activity(kind: $0)) })
    }

    @Test
    func nothingActiveMeansTheIdleAgenda() {
        #expect(resolveExpandedKind([:]) == nil)
    }

    @Test
    func compactOnlyPeeksNeverOwnTheExpandedIsland() {
        for kind in [ActivityKind.charging, .wave, .greeting] {
            #expect(resolveExpandedKind(activities([kind])) == nil)
        }
    }

    /// The regression this guards: a charging peek outranks `.nowPlaying`
    /// in the wings, so resolving the expanded view through the *compact*
    /// order would blank the music card every time the charger went in.
    @Test
    func chargingPeekLeavesTheMusicCardAlone() {
        let active = activities([.nowPlaying, .charging])
        #expect(resolveCurrentActivity(active)?.kind == .charging)
        #expect(resolveExpandedKind(active) == .nowPlaying)
    }

    @Test
    func alertsTakeTheIslandFromMusicButTheShelfOutranksThem() {
        #expect(resolveExpandedKind(activities([.nowPlaying, .network])) == .network)
        #expect(resolveExpandedKind(activities([.nowPlaying, .batteryAlert])) == .batteryAlert)
        #expect(resolveExpandedKind(activities([.network, .batteryAlert, .screenshot])) == .screenshot)
    }

    /// A timer runs for minutes, so it sits *below* music — otherwise it
    /// would hide the card for the whole countdown.
    @Test
    func timerYieldsToMusicButBeatsTheIdleAgenda() {
        #expect(resolveExpandedKind(activities([.nowPlaying, .timer])) == .nowPlaying)
        #expect(resolveExpandedKind(activities([.timer])) == .timer)
    }

    /// Anything that can own the expanded island must resolve to a layout
    /// of its own. Falling through to the idle agenda would size the island
    /// for a calendar and then fill it with something else.
    @Test
    func everyExpandedOwnerResolvesToItsOwnLayout() {
        for kind in ActivityKind.allCases where resolveExpandedKind(activities([kind])) != nil {
            #expect(IslandLayout.resolved(for: kind, content: .empty) != IslandLayout.idle(.empty))
        }
    }
}
