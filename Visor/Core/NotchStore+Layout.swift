/// The island's derived geometry, split off `NotchStore` to keep that file
/// at a size somebody can still read in one go. Every member here is
/// computed from stored state, so nothing moved out of `@Observable`'s
/// reach — it is the resolution and nothing else.
@MainActor
extension NotchStore {
    /// The shape the island takes right now. Onboarding is checked first and
    /// unconditionally: it is not one more activity competing in the
    /// priority ladder, it is a different mode the island is in, the same
    /// way `state` is. The palette is the second such mode.
    var layout: IslandLayout {
        if let onboardingStep {
            return IslandLayout.onboarding(onboardingStep)
        }
        if isPaletteOpen {
            return IslandLayout.palette(rows: paletteResults.count)
        }
        let activity = IslandLayout.resolved(for: expandedKind, content: islandContent)
        switch islandPage {
        case .home:
            return activity
        case .agenda:
            return paged(IslandLayout.idle(islandContent), wings: activity)
        case .usage:
            return paged(IslandLayout.usage(rows: usageRows), wings: activity)
        }
    }

    /// Paging changes the **expanded** island and nothing else. The compact
    /// wings belong to whatever activity is running, always — they are what
    /// the island looks like at rest, so a screen you swiped to must not
    /// still be deciding their width once it has closed. Getting this wrong
    /// made the island collapse to one wing and then jump to another.
    private func paged(_ page: IslandLayout, wings: IslandLayout) -> IslandLayout {
        var resolved = page
        resolved.compactExtraWidth = wings.compactExtraWidth
        return resolved
    }

    /// Filtered exactly the way the agenda view filters, so the island can
    /// never reserve a row for an event that has already ended.
    var islandContent: IslandContent {
        let upcoming = CalendarEventMapper.upcomingCount(calendarEvents, now: .now)
        return IslandContent(
            agendaRows: min(upcoming, IslandLayout.maxEventRows),
            hasAgendaOverflow: upcoming > IslandLayout.maxEventRows,
            hasTimerPresets: timerCommands != nil,
            downloadRows: min(downloads.count, IslandLayout.maxDownloadRows),
            // Only when the greeting actually owns the wing: a greeting still
            // stored but outranked must not widen the island for a label
            // nothing is drawing.
            compactLeadingWidth: currentActivity?.kind == .greeting ? (greetingText?.labelWidth ?? 0) : 0,
            hasLyrics: isLyricsOpen
        )
    }

    /// Which screens can actually be reached right now.
    ///
    /// `.agenda` drops out whenever nothing owns the expanded island, because
    /// `.home` already *is* the agenda then — `resolveExpandedKind` returns
    /// nil and both screens draw `ExpandedIdleView`. Leaving it in the stack
    /// gave a swipe up from the player that buzzed, changed the page, and
    /// showed the identical view, which reads as the gesture having failed.
    var availablePages: [IslandPage] {
        expandedKind == nil ? [.home, .usage] : IslandPage.allCases
    }

    /// How many tool rows the usage screen will really draw.
    ///
    /// Codex is left out entirely until it has actually run: its `threads`
    /// table is empty on a machine that has never used it, and a row reading
    /// "0" next to a live Claude figure claims the tool is idle when it was
    /// never installed. The island shrinks to fit rather than holding a slot
    /// open for it.
    var usageRows: Int {
        aiUsage.codexTokens > 0 ? 2 : 1
    }
}
