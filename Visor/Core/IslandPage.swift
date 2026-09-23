/// The screens the expanded island pages between, top to bottom.
///
/// The raw values are positions on that axis rather than labels, which is
/// what makes stepping and clamping fall out of the type instead of being
/// written again at each call site: a step past either end returns the same
/// page, so the ends hold without a bounds check anywhere.
///
/// The player sits in the middle on purpose. It is the only one of the three
/// with controls on it, and the two either side are quick looks — putting the
/// thing you operate at the resting position means the common case needs no
/// swipe at all.
enum IslandPage: Int, CaseIterable, Sendable {
    /// The catch shelf: screenshots, stashed files, a running AirDrop or
    /// download. Its own screen rather than something that takes over the
    /// home page, which is what it did while `.screenshot` outranked
    /// `.nowPlaying` — a catch replaced the player and no swipe could get
    /// it back. Furthest from the player because it is the least urgent of
    /// the four: the files are not going anywhere. Present only when there
    /// is something on it (see `availablePages`).
    case shelf = -2
    case agenda = -1
    case home = 0
    case usage = 1

    /// One step along the stack — negative towards the agenda, positive
    /// towards the agent figures — clamped at whichever end it reaches.
    ///
    /// `available` is the stack *as it stands*, which is not always all three:
    /// a screen that would draw exactly what its neighbour draws is left out
    /// of it, and stepping then moves straight past the gap rather than
    /// landing on a page that changes nothing. A page no longer in the stack
    /// steps home rather than getting stuck on itself.
    func stepped(by delta: Int, in available: [IslandPage]) -> IslandPage {
        let stack = available.sorted { $0.rawValue < $1.rawValue }
        guard let index = stack.firstIndex(of: self) else { return .home }
        return stack[min(max(index + delta, 0), stack.count - 1)]
    }

    /// One step with no ends — past the last page is the first again.
    ///
    /// The deliberate sibling of `stepped`, not a replacement for it. A
    /// stack you can see the edges of wants to clamp; a stack drawn as a
    /// deck, where the page behind the last one is visibly the first, wants
    /// to wrap, and a gesture that dies at an end you can *see* continuing
    /// reads as broken. Which one a swipe reaches is `PagingStyle`'s call.
    ///
    /// Negative-safe: Swift's `%` keeps the sign of the dividend, so a
    /// backward wrap needs the extra `+ count` before the second modulo.
    func cycled(by delta: Int, in available: [IslandPage]) -> IslandPage {
        let stack = available.sorted { $0.rawValue < $1.rawValue }
        guard !stack.isEmpty else { return self }
        guard let index = stack.firstIndex(of: self) else { return .home }
        let count = stack.count
        return stack[((index + delta) % count + count) % count]
    }
}
