import SwiftUI

/// Personal touch shown in the idle-expanded view when nothing's playing.
/// The glow only pulses while this view exists in the hierarchy — expanded
/// (hovering) and idle — so it never animates off-screen or while closed.
struct SignatureGlow: View {
    @State private var isGlowing = false

    private static let maroon = Color(red: 0.5, green: 0, blue: 0)

    var body: some View {
        Text("By Apurva")
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .foregroundStyle(Self.maroon)
            .shadow(color: Self.maroon, radius: isGlowing ? 14 : 4)
            .onAppear {
                withAnimation(Motion.resolved(Motion.pulse)) {
                    isGlowing = true
                }
            }
    }
}
