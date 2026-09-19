import Foundation
import Testing
@testable import Visor

@MainActor
struct ShelfTests {
    private func shot(_ name: String, at offset: TimeInterval = 0) -> ScreenshotCatch {
        ScreenshotCatch(
            url: URL(fileURLWithPath: "/tmp/\(name).png"),
            thumbnail: nil,
            caughtAt: Date(timeIntervalSinceReferenceDate: offset)
        )
    }

    @Test
    func addingPutsTheNewestFirstAndActivatesTheIsland() {
        let store = NotchStore()
        store.addToShelf(shot("a"))
        store.addToShelf(shot("b", at: 1))

        #expect(store.shelf.map(\.url.lastPathComponent) == ["b.png", "a.png"])
        #expect(store.currentActivity?.kind == .screenshot)
    }

    @Test
    func reAddingTheSameCatchIsNotADuplicate() {
        let store = NotchStore()
        store.addToShelf(shot("a"))
        store.addToShelf(shot("a"))

        #expect(store.shelf.count == 1)
    }

    /// Past the cap the row stops fitting the island, so the oldest goes.
    @Test
    func oldestFallsOffThePastTheCap() {
        let store = NotchStore()
        for index in 0 ... NotchStore.shelfLimit {
            store.addToShelf(shot("shot\(index)", at: TimeInterval(index)))
        }

        #expect(store.shelf.count == NotchStore.shelfLimit)
        #expect(!store.shelf.contains(shot("shot0")))
    }

    @Test
    func removingTheLastItemDeactivatesTheIsland() {
        let store = NotchStore()
        let only = shot("a")
        store.addToShelf(only)
        store.removeFromShelf(only)

        #expect(store.shelf.isEmpty)
        #expect(store.currentActivity == nil)
    }

    /// A drag provider outlives the chip that made it, so a stale removal
    /// must not take whatever replaced it.
    @Test
    func removingSomethingAlreadyGoneLeavesTheRestAlone() {
        let store = NotchStore()
        let kept = shot("kept", at: 1)
        store.addToShelf(kept)
        store.removeFromShelf(shot("stale"))

        #expect(store.shelf == [kept])
        #expect(store.currentActivity?.kind == .screenshot)
    }

    @Test
    func clearingEmptiesAndDeactivates() {
        let store = NotchStore()
        store.addToShelf(shot("a"))
        store.addToShelf(shot("b", at: 1))
        store.clearShelf()

        #expect(store.shelf.isEmpty)
        #expect(store.currentActivity == nil)
    }
}
