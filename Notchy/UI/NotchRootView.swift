import SwiftUI

struct NotchRootView: View {
    var store: NotchStore

    private var isExpanded: Bool {
        store.state == .expanded
    }

    private var currentSize: CGSize {
        isExpanded ? NotchGeometry.expandedSize : store.closedSize
    }

    var body: some View {
        NotchShape(
            topRadius: isExpanded ? NotchShape.expandedTopRadius : NotchShape.closedTopRadius,
            bottomRadius: isExpanded ? NotchShape.expandedBottomRadius : NotchShape.closedBottomRadius
        )
        .fill(.black)
        .frame(width: currentSize.width, height: currentSize.height)
        .overlay(alignment: .top) {
            if isExpanded {
                ClockPlaceholderView()
                    // Below the physical camera housing, not under it —
                    // store.closedSize.height is the real hardware safe area.
                    .padding(.top, store.closedSize.height + 4)
                    .transition(.island)
            }
        }
        .frame(width: NotchGeometry.expandedSize.width, height: NotchGeometry.expandedSize.height, alignment: .top)
    }
}
