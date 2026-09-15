import EventKit
import SwiftUI

@MainActor
final class CalendarService: NotchService {
    private let store: NotchStore
    private let eventStore = EKEventStore()
    private var observer: NSObjectProtocol?
    private var hasAccess = false

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        Task { await requestAccessAndRefresh() }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        store.calendarEvents = []
    }

    private func requestAccessAndRefresh() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        // A grant that keeps reverting to notDetermined means the app's code
        // signature changed, not that the user revoked it — see
        // scripts/make-signing-cert.sh.
        Log.calendar.info("Calendar authorization status: \(status.rawValue)")
        switch status {
        case .fullAccess:
            hasAccess = true
        case .notDetermined:
            do {
                hasAccess = try await eventStore.requestFullAccessToEvents()
            } catch {
                Log.calendar.error("Calendar access request failed: \(error.localizedDescription)")
                hasAccess = false
            }
        case .denied, .restricted, .writeOnly:
            // Write-only can't read events, so it's a denial for our purposes.
            Log.calendar.info("Calendar access unavailable; the agenda stays empty.")
            hasAccess = false
        @unknown default:
            hasAccess = false
        }
        refresh()
    }

    private func refresh() {
        guard hasAccess else {
            store.calendarEvents = []
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            Log.calendar.error("Could not compute today's end date.")
            return
        }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate).map(Self.convert)
        store.calendarEvents = events
    }

    private static func convert(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            color: event.calendar?.color.map(Color.init(nsColor:))
        )
    }
}
