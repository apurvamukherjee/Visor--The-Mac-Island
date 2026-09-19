import Foundation

/// One outgoing AirDrop send.
///
/// There is no progress figure and deliberately so. `NSSharingService` tells
/// us when a send finishes and whether it worked, and nothing in between —
/// the reference implementation this was ported from carried a `progress`
/// field that nothing ever wrote a real value into, so the ring it drew was
/// decorative. An indeterminate state that is honest beats a bar that lies.
struct AirDropTransfer: Equatable, Identifiable, Sendable {
    enum Status: Equatable, Sendable {
        case sending
        case completed
        case failed(String)
    }

    let id: UUID
    let fileNames: [String]
    var status: Status

    var title: String {
        if fileNames.count == 1, let first = fileNames.first {
            return first
        }
        return "\(fileNames.count) items"
    }
}
