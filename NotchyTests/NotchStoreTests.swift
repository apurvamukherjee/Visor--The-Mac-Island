import CoreGraphics
import Testing
@testable import Notchy

@MainActor
struct NotchStoreTests {
    @Test
    func startsClosed() {
        let store = NotchStore()
        #expect(store.state == .closed)
    }

    @Test
    func setStateUpdatesState() {
        let store = NotchStore()
        store.setState(.expanded)
        #expect(store.state == .expanded)
    }

    @Test
    func setClosedSizeUpdatesClosedSize() {
        let store = NotchStore()
        let size = CGSize(width: 180, height: 30)
        store.setClosedSize(size)
        #expect(store.closedSize == size)
    }
}
