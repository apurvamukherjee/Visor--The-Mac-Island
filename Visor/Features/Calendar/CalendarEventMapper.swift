import Foundation

enum CalendarEventMapper {
    /// Events still worth showing, soonest first. An event counts as
    /// upcoming until it has actually *ended*, so something in progress
    /// right now doesn't vanish from the agenda halfway through.
    /// How many events are still worth showing at all. The agenda sizes
    /// itself from this and counts its "+N more" against it; counting raw
    /// `events` instead is what printed "2 more events" over an empty
    /// agenda, on a day whose only two events had already ended.
    static func upcomingCount(_ events: [CalendarEvent], now: Date) -> Int {
        events.lazy.filter { $0.end > now }.count
    }

    static func upcoming(_ events: [CalendarEvent], now: Date, limit: Int) -> [CalendarEvent] {
        Array(
            events
                .filter { $0.end > now }
                .sorted { $0.start < $1.start }
                .prefix(limit)
        )
    }
}
