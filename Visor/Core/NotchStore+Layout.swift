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
        guard NewFeatures.islandPaging.isEnabled() else { return activity }
        // One box, held by every screen the swipe can reach, so turning a
        // page cross-fades content inside a shape that does not move. Sizing
        // each page for itself made the notch grow and shrink under a gesture
        // that only ever meant "show me the next thing".
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

    /// Whether the island is drawing its screens as a deck. Paging has to be
    /// on for it to mean anything — the stack is how pages are *shown*, not
    /// a second way to reach them.
    var isCardStacked: Bool {
        NewFeatures.islandPaging.isEnabled() && pagingStyle == .cardStack
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
