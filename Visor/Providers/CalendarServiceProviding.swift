//
//  CalendarServiceProvider.swift
//  Calendr
//
//  Created by Apurva on 31/12/20.
//  
//  Modified by Apurva on 08/06/25
//

import Foundation
@preconcurrency import EventKit

class CalendarService {
    private let store = EKEventStore()
    
    @MainActor
    func requestAccess(to type: EKEntityType) async throws -> Bool {
        switch type {
        case .event:
            return try await store.requestFullAccessToEvents()
        case .reminder:
            return try await store.requestFullAccessToReminders()
        @unknown default:
            return false
        }
    }
    
    private func hasAccess(to entityType: EKEntityType) -> Bool {
        EKEventStore.authorizationStatus(for: entityType) == .fullAccess
    }
    
    func calendars() async -> [CalendarModel] {
        var calendars: [EKCalendar] = []
        
        for type in [EKEntityType.event, .reminder] where hasAccess(to: type) {
            calendars.append(contentsOf: store.calendars(for: type))
        }
        
        return calendars.map { CalendarModel(from: $0) }
    }
    
    func events(from start: Date, to end: Date, calendars ids: [String]) async -> [EventModel] {
        let allCalendars = await self.calendars()
        let filteredCalendars = allCalendars.filter { ids.isEmpty || ids.contains($0.id) }
        let ekCalendars = filteredCalendars.compactMap { calendarModel in
            store.calendars(for: .event).first { $0.calendarIdentifier == calendarModel.id } ??
            store.calendars(for: .reminder).first { $0.calendarIdentifier == calendarModel.id }
        }
        
        var events: [EventModel] = []
        
        // Fetch regular events
        if hasAccess(to: .event) {
            let eventCalendars = ekCalendars.filter { store.calendars(for: .event).contains($0) }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: eventCalendars)
            let ekEvents = store.events(matching: predicate)
            events.append(contentsOf: ekEvents.compactMap { EventModel(from: $0) })
        }
        
        // Fetch reminders
        if hasAccess(to: .reminder) {
            let reminderCalendars = ekCalendars.filter { store.calendars(for: .reminder).contains($0) }
            events.append(contentsOf: await fetchReminders(from: start, to: end, calendars: reminderCalendars))
        }
        
        return events.sorted { $0.start < $1.start }
    }
    
    private func fetchReminders(from start: Date, to end: Date, calendars: [EKCalendar]) async -> [EventModel] {
        return await withCheckedContinuation { continuation in
            // Create predicate for reminders with due dates in the specified range
            let predicate = store.predicateForReminders(in: calendars)
            
            store.fetchReminders(matching: predicate) { reminders in
                
                let filteredReminders = (reminders ?? []).filter { reminder in
                    // Check if reminder has a due date within our range
                    guard let dueDate = reminder.dueDateComponents?.date else {
                        return false
                    }
                    
                    return dueDate >= start && dueDate <= end
                }
                
                // Convert to EventModel
                let eventModels = filteredReminders.compactMap { reminder in
                    EventModel(from: reminder)
                }
                
                continuation.resume(returning: eventModels)
            }
        }
    }
    
    func setReminderCompleted(reminderID: String, completed: Bool) async {
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return }
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
        } catch {
            print("Failed to update reminder completion: \(error)")
        }
    }
}

// MARK: - Model Extensions

extension CalendarModel {
    init(from calendar: EKCalendar) {
        self.init(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            color: calendar.color,
            isReminder: calendar.allowedEntityTypes.contains(.reminder)
        )
    }
}

extension EventModel {
    init?(from event: EKEvent) {
        guard let calendar = event.calendar else { return nil }
        
        self.init(
            id: event.calendarItemIdentifier,
            start: event.startDate,
            end: event.endDate,
            title: event.title ?? "",
            location: event.location,
            isAllDay: event.shouldBeAllDay,
            type: .event,
            calendar: .init(from: calendar),
            hasRecurrenceRules: event.hasRecurrenceRules || event.isDetached
        )
    }
    
    init?(from reminder: EKReminder) {
        guard let calendar = reminder.calendar,
              let dueDateComponents = reminder.dueDateComponents,
              let date = Calendar.current.date(from: dueDateComponents)
        else { return nil }
        
        self.init(
            id: reminder.calendarItemIdentifier,
            start: date,
            end: Calendar.current.endOfDay(for: date),
            title: reminder.title ?? "",
            location: reminder.location,
            isAllDay: dueDateComponents.hour == nil,
            type: .reminder(completed: reminder.isCompleted),
            calendar: .init(from: calendar),
            hasRecurrenceRules: reminder.hasRecurrenceRules
        )
    }
}

private extension EKEvent {
    var shouldBeAllDay: Bool {
        guard !isAllDay else { return true }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: startDate)
        let endOfDay = calendar.dateInterval(of: .day, for: endDate)?.end
        return startDate == startOfDay && endDate == endOfDay
    }
}

private extension Calendar {
    func endOfDay(for date: Date) -> Date {
        dateInterval(of: .day, for: date)?.end ?? date
    }
}
