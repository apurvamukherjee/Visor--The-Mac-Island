import CoreGraphics
import Observation

enum NotchState: Equatable, Sendable {
    case closed
    case expanded
    case compact
}

@Observable
@MainActor
final class NotchStore {
    private(set) var state: NotchState = .closed
    private(set) var closedSize: CGSize = .zero

    func setState(_ newState: NotchState) {
        state = newState
    }

    func setClosedSize(_ size: CGSize) {
        closedSize = size
    }
}
