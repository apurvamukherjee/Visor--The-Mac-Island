/// The three screens the expanded island pages between, top to bottom.
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
    case agenda = -1
    case home = 0
    case usage = 1

    /// Swipe down: towards the agent figures at the bottom.
    var below: IslandPage {
        IslandPage(rawValue: rawValue + 1) ?? self
    }

    /// Swipe up: towards the agenda at the top.
    var above: IslandPage {
        IslandPage(rawValue: rawValue - 1) ?? self
    }
}
