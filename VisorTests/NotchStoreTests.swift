import CoreGraphics
import Testing
@testable import Visor

@MainActor
struct NotchStoreTests {
    @Test
    func startsClosed() {
        let store = NotchStore()
        #expect(store.state == .closed)
    }

    @Test
    func stateIsWritable() {
        let store = NotchStore()
        store.state = .expanded
        #expect(store.state == .expanded)
    }

    @Test
    func closedSizeIsWritable() {
        let store = NotchStore()
        let size = CGSize(width: 180, height: 30)
        store.closedSize = size
        #expect(store.closedSize == size)
    }
}
