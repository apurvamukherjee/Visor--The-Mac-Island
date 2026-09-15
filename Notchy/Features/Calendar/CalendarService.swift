import AppKit
import EventKit

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
        store.setCalendarEvents([])
    }

    private func requestAccessAndRefresh() async {
        switch EKEventStore.authorizationStatus(for: .event) {
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
            store.setCalendarEvents([])
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
        store.setCalendarEvents(events)
    }

    private static func convert(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            colorHex: event.calendar?.color.flatMap(hex)
        )
    }

    private static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
