import Foundation
import SwiftUI

/// A calendar entry, decoupled from EventKit so the list logic stays pure
/// and testable without an `EKEventStore`.
struct CalendarEvent: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// `EKCalendar`'s colour. `Color` is `Sendable`, so carrying it directly
    /// costs nothing a hex round-trip would have saved.
    let color: Color?
}
