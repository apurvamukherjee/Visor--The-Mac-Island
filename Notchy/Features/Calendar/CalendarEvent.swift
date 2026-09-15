import Foundation

/// A calendar entry, decoupled from EventKit so the list logic stays pure
/// and testable without an `EKEventStore`.
struct CalendarEvent: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// `EKCalendar`'s colour, as a hex string — keeps this model free of
    /// AppKit/SwiftUI so it can live in tests and services alike.
    let colorHex: String?
}
