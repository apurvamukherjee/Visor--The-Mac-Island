import Foundation
import Testing
@testable import Visor

/// The stack has no ends. `stepped` still does — both live, and which one a
/// swipe reaches is the paging style's business, not this type's.
@Suite("Island page cycling")
struct IslandPageCycleTests {
    private let all: [IslandPage] = [.agenda, .home, .usage]

    @Test("Down from the last page wraps to the first")
    func wrapsForward() {
        #expect(IslandPage.usage.cycled(by: 1, in: all) == .agenda)
        #expect(IslandPage.agenda.cycled(by: 1, in: all) == .home)
        #expect(IslandPage.home.cycled(by: 1, in: all) == .usage)
    }

    @Test("Up from the first page wraps to the last")
    func wrapsBackward() {
        #expect(IslandPage.agenda.cycled(by: -1, in: all) == .usage)
        #expect(IslandPage.usage.cycled(by: -1, in: all) == .home)
        #expect(IslandPage.home.cycled(by: -1, in: all) == .agenda)
    }

    /// The idle island drops `.agenda` — `.home` already draws it. Two pages
    /// cycle by alternating, and both directions agree, which is the one
    /// case where wrapping and clamping visibly differ by nothing.
    @Test("Two reachable pages alternate in both directions")
    func twoPagesAlternate() {
        let two: [IslandPage] = [.home, .usage]

        #expect(IslandPage.home.cycled(by: 1, in: two) == .usage)
        #expect(IslandPage.usage.cycled(by: 1, in: two) == .home)
        #expect(IslandPage.home.cycled(by: -1, in: two) == .usage)
        #expect(IslandPage.usage.cycled(by: -1, in: two) == .home)
    }

    @Test("A page no longer in the stack cycles home")
    func absentPageGoesHome() {
        #expect(IslandPage.agenda.cycled(by: 1, in: [.home, .usage]) == .home)
    }

    @Test("An empty stack cannot move")
    func emptyStackHolds() {
        #expect(IslandPage.home.cycled(by: 1, in: []) == .home)
    }

    /// The off path. With the stack unselected a swipe still clamps, so
    /// these are the assertions that fail if cycling leaks into `stepped`.
    @Test("Stepping still clamps at both ends")
    func steppingStillClamps() {
        #expect(IslandPage.usage.stepped(by: 1, in: all) == .usage)
        #expect(IslandPage.agenda.stepped(by: -1, in: all) == .agenda)
    }

    @Test("Every page has its own tint")
    func tintsAreDistinct() {
        let tints = IslandPage.allCases.map(\.tint)
        #expect(Set(tints.map(\.description)).count == tints.count)
    }
}
