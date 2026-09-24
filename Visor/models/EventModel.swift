//
//  EventModel.swift
//  Calendr
//
//

import Foundation

struct EventModel: Equatable, Identifiable {
    let id: String
    let start: Date
    let end: Date
    let title: String
    let location: String?
    let isAllDay: Bool
    let type: EventType
    let calendar: CalendarModel
    let hasRecurrenceRules: Bool
}

enum EventType: Equatable {
    case event
    case reminder(completed: Bool)
}

enum EventStatus: Equatable {
    case upcoming
    case inProgress
    case ended
}

extension EventType {
    var isReminder: Bool { if case .reminder = self { return true } else { return false } }
}

extension EventModel {
    
    var eventStatus: EventStatus {
        if start > Date() {
            return .upcoming
        } else if end > Date() {
            return .inProgress
        } else {
            return .ended
        }
    }

    func calendarAppURL() -> URL? {

        guard let id = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        guard !type.isReminder else {
            return URL(string: "x-apple-reminderkit://remcdreminder/\(id)")
        }

        let date: String
        if hasRecurrenceRules {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if !isAllDay {
                formatter.timeZone = .init(secondsFromGMT: 0)
            }
            if let formattedDate = formatter.string(for: start) {
                date = "/\(formattedDate)"
            } else {
                return nil
            }
        } else {
            date =  ""
        }
        return URL(string: "ical://ekevent\(date)/\(id)?method=show&options=more")
    }
}
