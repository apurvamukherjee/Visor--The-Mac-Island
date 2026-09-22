import CoreGraphics
import Testing
@testable import Visor

/// The split decides between the shelf and sending a file to whoever is
/// nearby, so it is pinned rather than eyeballed.
@Suite("Drop zones")
struct DropZoneTests {
    private let canvasWidth: CGFloat = 400

    private func resolve(dropX: CGFloat, zonesVisible: Bool, optionHeld: Bool = false) -> DropZone {
        DropZone.resolve(
            location: CGPoint(x: dropX, y: 60),
            canvasWidth: canvasWidth,
            zonesVisible: zonesVisible,
            optionHeld: optionHeld
        )
    }

    /// The behaviour anyone who never opens the New Features tab keeps.
    @Test("With the zones off, every plain drop stashes")
    func zonesOffAlwaysStash() {
        #expect(resolve(dropX: 10, zonesVisible: false) == .stash)
        #expect(resolve(dropX: 200, zonesVisible: false) == .stash)
        #expect(resolve(dropX: 390, zonesVisible: false) == .stash)
    }

    @Test("Option still sends, zones on or off")
    func optionAlwaysSends() {
        #expect(resolve(dropX: 10, zonesVisible: false, optionHeld: true) == .airDrop)
        #expect(resolve(dropX: 10, zonesVisible: true, optionHeld: true) == .airDrop)
    }

    @Test("With the zones on, the left half stashes and the right half sends")
    func zonesSplitAtTheMiddle() {
        #expect(resolve(dropX: 0, zonesVisible: true) == .stash)
        #expect(resolve(dropX: 199, zonesVisible: true) == .stash)
        #expect(resolve(dropX: 201, zonesVisible: true) == .airDrop)
        #expect(resolve(dropX: 400, zonesVisible: true) == .airDrop)
    }

    /// Dead centre is the divider itself. It has to land somewhere, and the
    /// safe side is the one that does not send the file anywhere.
    @Test("The centre line stashes")
    func centreStashes() {
        #expect(resolve(dropX: 200, zonesVisible: true) == .stash)
    }
}
