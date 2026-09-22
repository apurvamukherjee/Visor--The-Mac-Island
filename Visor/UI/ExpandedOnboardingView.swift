import SwiftUI

/// The three-step welcome flow. Sized once for all three steps (see
/// `IslandLayout.onboarding`), so only the content inside the box changes —
/// the island itself holds still while the user reads.
struct ExpandedOnboardingView: View {
    let step: OnboardingStep
    let commands: NotchStore.OnboardingCommands?

    @State private var iconScale: CGFloat = 0.6
    /// 0 → 1 as the wordmark wipes on. A transform on a mask, not a width:
    /// a one-shot reveal still has no business re-running layout.
    @State private var wordmarkReveal: CGFloat = 0

    var body: some View {
        VStack(spacing: IslandSpacing.block) {
            copy
            dots
            buttons
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
    }

    private var copy: some View {
        VStack(spacing: 6) {
            // The first step gets a wordmark that writes itself on. The
            // reference played a Lottie file here; the whole animation was a
            // gradient-filled script face behind a trim path, which is a
            // masked wipe over `Text` — so the dependency bought one view.
            // The later steps keep their SF Symbol: the animation is the
            // greeting, not a decoration to repeat three times.
            if step == .welcome {
                wordmark
            } else {
                Image(systemName: step.glyph)
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
                    .scaleEffect(iconScale)
                    .onAppear { animateIconIn() }
                    .onChange(of: step) { animateIconIn() }
            }
            Text(step.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(step.body)
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(step)
        .transition(.island)
    }

    /// A lightweight progress read — three steps is short enough that a
    /// counter would be more chrome than the flow is worth.
    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingStep.allCases, id: \.self) { candidate in
                Capsule()
                    .fill(.white.opacity(candidate == step ? 0.9 : 0.25))
                    .frame(width: candidate == step ? 14 : 5, height: 5)
            }
        }
        .animation(Motion.resolved(Motion.layout), value: step)
    }

    private var buttons: some View {
        VStack(spacing: 6) {
            Button(step.primaryButtonTitle) {
                commands?.advance()
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())

            if let secondaryTitle = step.secondaryButtonTitle, let url = step.secondaryURL {
                Button(secondaryTitle) {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(OnboardingLinkButtonStyle())
            }
        }
        .id(step)
        .transition(.island)
    }

    /// Snell Roundhand ships with macOS; `.custom` falls back to the system
    /// face if that ever stops being true, which costs the flourish and
    /// nothing else.
    private var wordmark: some View {
        Text(verbatim: "Welcome")
            .font(.custom("Snell Roundhand", size: 34).weight(.bold))
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, .white.opacity(0.55)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 170, height: 44)
            .mask(alignment: .leading) {
                Rectangle().scaleEffect(x: wordmarkReveal, anchor: .leading)
            }
            .onAppear {
                guard !Motion.reduceMotion else {
                    wordmarkReveal = 1
                    return
                }
                wordmarkReveal = 0
                withAnimation(.easeOut(duration: 0.9)) { wordmarkReveal = 1 }
            }
    }

    private func animateIconIn() {
        iconScale = 0.6
        withAnimation(Motion.resolved(Motion.onboardingIconIn)) {
            iconScale = 1
        }
    }
}

/// A filled white capsule with bold black text — the iOS "primary action on
/// a dark sheet" look — with the reference flow's own press feedback
/// (scale to 0.94, fade to 0.7) ported over rather than re-derived.
private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(.white, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Motion.onboardingPress, value: configuration.isPressed)
    }
}

private struct OnboardingLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.4 : 0.6))
            .animation(Motion.onboardingPress, value: configuration.isPressed)
    }
}
