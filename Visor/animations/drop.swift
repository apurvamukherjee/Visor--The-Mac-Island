
import Foundation
import SwiftUI


public class VisorAnimations {
    // Visor: the notch style was always .notch on macOS 14+, so the floating
    // timing curve was unreachable.
    var animation: Animation {
        Animation.spring(.bouncy(duration: 0.4))
    }
}
