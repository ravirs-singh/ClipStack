import AppKit
import EventKit

/// Next calendar events and today's reminders for the "Up Next" tab and the notch wing.
final class CalendarMonitor {
    static let changed = Notification.Name("ClipStackCalendarChanged")

    struct Item {
        let title: String
        let start: Date
        let end: Date
        let joinURL: URL?
        let location: String
        let isReminder: Bool
        var minutesUntil: Int { Int(start.timeIntervalSinceNow / 60) }
    }

    private(set) var events: [Item] = []
    private(set) var reminders: [Item] = []
    private(set) var authorized = false
    private let store = EKEventStore()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    /// The event to surface in the wing: starts within 10 minutes or started less than 5 minutes ago.
    var imminent: Item? {
        events.first { $0.minutesUntil <= 10 && $0.minutesUntil >= -5 }
    }

    init() {
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in self?.applyEnabled() })
        applyEnabled()
    }

    private func applyEnabled() {
        timer?.invalidate(); timer = nil
        guard Settings.calendarEnabled else { events = []; reminders = []; NotificationCenter.default.post(name: Self.changed, object: self); return }
        requestAccess { [weak self] in
            self?.refresh()
            self?.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in self?.refresh() }
        }
    }

    private func requestAccess(_ done: @escaping () -> Void) {
        let finish: (Bool) -> Void = { [weak self] ok in DispatchQueue.main.async { self?.authorized = ok; done() } }
        if #available(macOS 14, *) {
            store.requestFullAccessToEvents { ok, _ in
                self.store.requestFullAccessToReminders { _, _ in finish(ok) }
            }
        } else {
            store.requestAccess(to: .event) { ok, _ in
                self.store.requestAccess(to: .reminder) { _, _ in finish(ok) }
            }
        }
    }

    func refresh() {
        guard authorized else { return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: 24, to: now)!
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-5 * 60), end: end, calendars: nil)
        events = store.events(matching: pred)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)
            .map { Item(title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate, joinURL: Self.joinLink(in: $0),
                        location: $0.location ?? "", isReminder: false) }

        let rpred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: Calendar.current.startOfDay(for: now).addingTimeInterval(86400), calendars: nil)
        store.fetchReminders(matching: rpred) { [weak self] list in
            let items = (list ?? []).compactMap { r -> Item? in
                let due = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? now
                return Item(title: r.title ?? "Reminder", start: due, end: due, joinURL: nil, location: "", isReminder: true)
            }.sorted { $0.start < $1.start }
            DispatchQueue.main.async { self?.reminders = Array(items.prefix(5)); NotificationCenter.default.post(name: Self.changed, object: self) }
        }
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    /// Zoom / Meet / Teams / Webex / FaceTime link from the event's URL, location or notes.
    private static func joinLink(in e: EKEvent) -> URL? {
        let hay = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let hosts = ["zoom.us", "meet.google", "teams.microsoft", "webex", "facetime", "whereby", "around.co", "meet.jit.si"]
        return det?.matches(in: hay, range: NSRange(hay.startIndex..., in: hay)).compactMap(\.url)
            .first { u in hosts.contains { u.absoluteString.localizedCaseInsensitiveContains($0) } }
    }

    static func relative(_ item: Item) -> String {
        let m = item.minutesUntil
        if m < -1 { return "started" }
        if m <= 0 { return "now" }
        if m < 60 { return "in \(m) min" }
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: item.start)
    }
}
