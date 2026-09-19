import AppKit
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

/// The drag-out bug: the chip registered a single `public.fileURL`
/// representation, and Finder, Slack and Figma all ask for the image's
/// *content* type instead — found nothing they accepted, and refused the
/// drop. The catch stored fine and went nowhere.
@MainActor
struct ScreenshotDragTests {
    private func makeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("visor-drag-\(UUID().uuidString).png")
        // A real PNG header, so the type is resolved from content rather
        // than guessed from the extension.
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        try png.write(to: url)
        return url
    }

    @Test
    func theDraggedFileAdvertisesItsImageTypeNotJustItsURL() throws {
        let url = try makeFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = try #require(NSItemProvider(contentsOf: url))
        let types = provider.registeredTypeIdentifiers

        // The regression: this used to be exactly ["public.file-url"].
        #expect(types.contains("public.png"))
        #expect(types.contains("public.file-url"))
        #expect(types.count > 1)
    }

    /// Receivers that do want a URL must still get one.
    @Test
    func theDraggedFileStillLoadsAsAURL() throws {
        let url = try makeFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = try #require(NSItemProvider(contentsOf: url))
        #expect(provider.canLoadObject(ofClass: URL.self))
    }
}
