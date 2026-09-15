import Foundation
import Testing
@testable import Notchy

struct CalendarEventMapperTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func event(
        id: String,
        startOffset: TimeInterval,
        duration: TimeInterval = 3600,
        isAllDay: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: "Event \(id)",
            start: now.addingTimeInterval(startOffset),
            end: now.addingTimeInterval(startOffset + duration),
            isAllDay: isAllDay,
            color: nil
        )
    }

    @Test
    func upcomingDropsEventsThatHaveAlreadyEnded() {
        let events = [
            Self.event(id: "past", startOffset: -7200),
            Self.event(id: "future", startOffset: 3600),
        ]
        let result = CalendarEventMapper.upcoming(events, now: Self.now, limit: 10)
        #expect(result.map(\.id) == ["future"])
    }

    @Test
    func upcomingKeepsAnEventThatIsCurrentlyInProgress() {
        // Started an hour ago, ends an hour from now — still relevant.
        let events = [Self.event(id: "ongoing", startOffset: -3600, duration: 7200)]
        let result = CalendarEventMapper.upcoming(events, now: Self.now, limit: 10)
        #expect(result.map(\.id) == ["ongoing"])
    }

    @Test
    func upcomingSortsByStartAndAppliesTheLimit() {
        let events = [
            Self.event(id: "third", startOffset: 10800),
            Self.event(id: "first", startOffset: 600),
            Self.event(id: "second", startOffset: 3600),
        ]
        let result = CalendarEventMapper.upcoming(events, now: Self.now, limit: 2)
        #expect(result.map(\.id) == ["first", "second"])
    }

    @Test
    func upcomingKeepsAllDayEventsForTheWholeDay() {
        let events = [Self.event(id: "allday", startOffset: -3600, duration: 86400, isAllDay: true)]
        let result = CalendarEventMapper.upcoming(events, now: Self.now, limit: 10)
        #expect(result.map(\.id) == ["allday"])
    }
}
