import SwiftUI

/// The usage badge that sits beside the notch: one small mark per tool with
/// today's tokens next to it.
///
/// Deliberately not part of `NotchShape`. The island's sizes are tight deltas
/// from the measured cutout — the greeting once drew half-behind the camera
/// housing for exactly that reason — so a permanent extra element inside the
/// wings would have to be budgeted for in `IslandLayout` and would move
/// something already tuned. This draws in its own window instead and cannot
/// disturb the island's geometry at all.
struct AIUsageBadgeView: View {
    let usage: AIUsageSnapshot
    let claudeBudget: Int
    let codexBudget: Int
    /// False collapses the badge to nothing. The window stays up; only its
    /// content goes, so appearing and disappearing is a fade rather than a
    /// window order.
    var isPresented = true

    private func budget(for tool: AIUsageTool) -> Int {
        switch tool {
        case .claude: claudeBudget
        case .codex: codexBudget
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AIUsageTool.allCases, id: \.rawValue) { tool in
                AIUsageChip(
                    tool: tool,
                    tokens: usage.tokens(for: tool),
                    budget: budget(for: tool)
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.black.opacity(0.82), in: Capsule())
        .opacity(isPresented ? 1 : 0)
        .scaleEffect(isPresented ? 1 : 0.9, anchor: .center)
        .animation(Motion.resolved(isPresented ? Motion.open : Motion.close), value: isPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// One tool's mark, count, and — only when a budget is set — how far through
/// it you are.
private struct AIUsageChip: View {
    let tool: AIUsageTool
    let tokens: Int
    let budget: Int

    private var percentage: Int? {
        AIUsageFormat.percentage(tokens: tokens, budget: budget)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(tool.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 11, height: 11)
                .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
                .accessibilityLabel(tool.title)

            Text(AIUsageFormat.short(tokens))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            if let percentage {
                Text("\(percentage)%")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    // Over budget reads differently from under it, and a
                    // colour is the only room the badge has to say so.
                    .foregroundStyle(percentage >= 100 ? .orange : .white.opacity(0.55))
            }
        }
    }
}
