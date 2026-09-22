import SwiftUI

/// The usage screen: one row per agent, reached by swiping down on the island
/// and left by swiping back up.
///
/// A screen of its own rather than a column beside the player, which is the
/// whole point of it — the music card is already tuned to the width it has,
/// and hanging a second panel off it would move numbers that took a pass to
/// settle. Nothing here is drawn while the player is.
///
/// It shares `AIUsageBadgeView`'s data and none of its code: the badge is a
/// glanceable capsule 22pt tall and this is the place you actually read the
/// figures, so they want different type, different density, and — the reason
/// this screen exists — the context bar the badge has no room for.
struct ExpandedUsageView: View {
    let usage: AIUsageSnapshot
    let claudeBudget: Int
    let codexBudget: Int

    /// Codex only appears once it has actually run. Its `threads` table is
    /// empty on a machine that has never used it, and a row reading "0" beside
    /// a live Claude figure says the tool is idle rather than absent.
    private var tools: [AIUsageTool] {
        usage.codexTokens > 0 ? AIUsageTool.allCases : [.claude]
    }

    private func budget(for tool: AIUsageTool) -> Int {
        switch tool {
        case .claude: claudeBudget
        case .codex: codexBudget
        }
    }

    /// Only Claude has one to show. Codex keeps a cumulative per-thread
    /// `tokens_used` and no window figure anywhere, so its row draws the
    /// absence rather than a number that would have to be invented.
    private func context(for tool: AIUsageTool) -> AIUsageContext? {
        tool == .claude ? usage.claudeContext : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.row) {
            ForEach(tools, id: \.rawValue) { tool in
                UsageRow(
                    tool: tool,
                    tokens: usage.tokens(for: tool),
                    budget: budget(for: tool),
                    context: context(for: tool)
                )
            }
        }
        .frame(width: IslandLayout.Column.usage, alignment: .leading)
        .foregroundStyle(.white)
    }
}

/// One agent: who it is and which model, how full its window is, how much it
/// has spent today.
private struct UsageRow: View {
    let tool: AIUsageTool
    let tokens: Int
    let budget: Int
    let context: AIUsageContext?

    private var todayPercentage: Int? {
        AIUsageFormat.percentage(tokens: tokens, budget: budget)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(tool.assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .accessibilityHidden(true)

                Text(tool.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Spacer(minLength: 0)

                if let model = context?.model {
                    Text(Self.shortModel(model))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            ContextBar(context: context)

            HStack(spacing: 4) {
                Text("today")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Text(AIUsageFormat.short(tokens))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                if let todayPercentage {
                    Text("· \(todayPercentage)% of budget")
                        .font(.system(size: 10, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(todayPercentage >= 100 ? .orange : .white.opacity(0.45))
                }
            }
        }
        .frame(height: IslandLayout.Block.usageRow, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    /// `claude-opus-5` reads as `opus-5`: the vendor is already said by the
    /// mark and the title beside it, and the column is not wide enough to say
    /// it three times.
    static func shortModel(_ model: String) -> String {
        guard model.hasPrefix("claude-") else { return model }
        return String(model.dropFirst("claude-".count))
    }
}

/// How full the window is — or, for a tool that does not report one, a plain
/// statement that it does not.
///
/// The denominator is the model's real window, never a guess: an unrecognised
/// model draws the same absence Codex does. This is the rule the daily budget
/// already follows, applied to the one other bar on the screen.
private struct ContextBar: View {
    let context: AIUsageContext?

    private static let height: CGFloat = 5

    var body: some View {
        if let context, let window = context.window {
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geometry in
                    let fraction = min(max(Double(context.tokens) / Double(window), 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule()
                            .fill(fraction >= 0.9 ? Color.orange : .white.opacity(0.75))
                            .frame(width: geometry.size.width * fraction)
                    }
                }
                .frame(height: Self.height)

                HStack(spacing: 4) {
                    Text("context")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                    Text("\(AIUsageFormat.short(context.tokens)) / \(AIUsageFormat.short(window))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                    if let percentage = context.percentage {
                        Text("\(percentage)%")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(percentage >= 90 ? .orange : .white.opacity(0.45))
                    }
                }
            }
        } else {
            Text("no context reported")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.3))
                .frame(height: Self.height + 4 + 12, alignment: .leading)
        }
    }
}
