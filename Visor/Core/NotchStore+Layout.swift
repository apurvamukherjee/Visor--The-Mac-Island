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
        // One box for every page — and the *same* box whatever is playing.
        //
        // `covering` alone made the box the max of whatever was reachable, so
        // it tracked the current activity: 421x193 with a track loaded and
        // 366x190 without, a 55pt jump the moment music started. The player
        // is the page with the most in it and the one the island always opens
        // on, so it is what every screen is measured against — the same
        // reason it already floors the paged agenda's row count.
        let box = availablePages
            .reduce(activity) { $0.covering(pageLayout(for: $1)) }
            .covering(IslandLayout.nowPlaying(islandContent))
        guard isCardStacked else { return box }
        var stacked = box
        stacked.chinReveal = IslandStackMetrics.reveal(
            forDepths: stackDepths.values.max() ?? 0
        )
        return stacked
    }

    /// Whether the island is drawing its screens as a deck rather than
    /// cross-fading them. The stack is how pages are *shown*, never a second
    /// way to reach them.
    var isCardStacked: Bool {
        pagingStyle == .cardStack
    }

    /// Each reachable page's distance from the front.
    ///
    /// `pagingStyle` itself is declared in `NotchStore.swift` beside
    /// `islandPage`, not here — this file holds derived geometry only.
    var stackDepths: [IslandPage: Int] {
        IslandStackMetrics.depths(front: islandPage, in: availablePages)
    }

    /// What one screen would need on its own, before the box is taken.
    private func pageLayout(for page: IslandPage) -> IslandLayout {
        switch page {
        case .home: IslandLayout.resolved(for: expandedKind, content: islandContent)
        case .agenda: IslandLayout.idle(agendaPageContent)
        case .usage: IslandLayout.usage(rows: usageRows)
        case .shelf: IslandLayout.shelf
        }
    }

    /// What the agenda *page* draws, which is a row shorter than the idle
    /// home screen and carries no timer presets.
    ///
    /// Both cuts buy the same thing: the player measures the box, so a page
    /// that wanted more would make the island's height track how many
    /// meetings you have. The presets are still on the home screen, which is
    /// where they were reached from anyway, and the row the agenda gives up
    /// is counted by the "+N more" line rather than lost.
    var agendaPageContent: IslandContent {
        let upcoming = CalendarEventMapper.upcomingCount(calendarEvents, now: .now)
        let rows = min(upcoming, IslandLayout.maxPagedEventRows)
        return IslandContent(
            agendaRows: rows,
            hasAgendaOverflow: upcoming > rows,
            compactLeadingWidth: islandContent.compactLeadingWidth
        )
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
            compactLeadingWidth: currentActivity?.kind == .greeting ? (greetingText?.labelWidth ?? 0) : 0
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
        // The shelf is only a screen while it has something on it. An empty
        // shelf page is a swipe that lands on nothing, and — since the box
        // covers every reachable page — it would also hold the island at the
        // shelf's height all day for a screen with no content.
        var pages: [IslandPage] = hasShelfContent ? [.shelf] : []
        pages += expandedKind == nil ? [.home] : [.agenda, .home]
        // The usage screen exists only while the reader that fills it does.
        // Paging is structural now, so the tab row would otherwise offer a
        // screen of zeroes on a machine whose owner never asked for either
        // agent's transcripts to be read. `AIUsageService` writes the flag as
        // it opens and closes the watcher, so the page and its data cannot
        // disagree.
        if isUsageTracked {
            pages.append(.usage)
        }
        return pages
    }

    /// Whether anything the shelf screen draws actually exists. The three
    /// lingering catchers sit below `.nowPlaying` in `expandedPriority` so
    /// they cannot displace the player; this is how they stay reachable.
    ///
    /// Read from `activities` rather than from `shelf`/`downloads`/
    /// `airDropTransfer` directly, so a page's availability and the ladder
    /// that ranks it cannot disagree: whoever activated the kind is the same
    /// service that filled the array, and checking the array separately
    /// invents a second source of truth for one fact.
    var hasShelfContent: Bool {
        Self.shelfKinds.contains { activities[$0] != nil }
    }

    /// The lingering catchers, in one place — they are named by
    /// `expandedPriority`'s tail and by `hasShelfContent`, and a kind added
    /// to one and not the other is a page that never appears.
    static let shelfKinds: [ActivityKind] = [.screenshot, .airDrop, .download]

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
