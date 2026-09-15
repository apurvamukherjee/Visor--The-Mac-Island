import Foundation

enum CalendarEventMapper {
    /// Events still worth showing, soonest first. An event counts as
    /// upcoming until it has actually *ended*, so something in progress
    /// right now doesn't vanish from the agenda halfway through.
    static func upcoming(_ events: [CalendarEvent], now: Date, limit: Int) -> [CalendarEvent] {
        events
            .filter { $0.end > now }
            .sorted { $0.start < $1.start }
            .prefix(limit)
            .map(\.self)
    }

    static func overflowCount(total: Int, shown: Int) -> Int {
        max(0, total - shown)
    }
}
