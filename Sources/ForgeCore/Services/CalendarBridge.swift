@preconcurrency import EventKit
import Foundation

/// Two-way bridge between ForgeTask due dates and EKEvent using EventKit.
public final class CalendarBridge: @unchecked Sendable {

    private let store: EKEventStore
    private let calendarName: String

    public init(store: EKEventStore = EKEventStore(), calendarName: String = "Forge") {
        self.store = store
        self.calendarName = calendarName
    }

    /// Request full access to Calendar. Must be called before any read/write operations.
    public func requestAccess() async throws {
        try await store.requestFullAccessToEvents()
    }

    // MARK: - Calendar Management

    /// Find or create the Forge calendar on the iCloud account.
    public func findOrCreateCalendar() throws -> EKCalendar {
        let calendars = store.calendars(for: .event)

        if let existing = calendars.first(where: { $0.title == calendarName }) {
            return existing
        }

        guard let source = store.defaultCalendarForNewEvents?.source else {
            throw BridgeError.noSource
        }

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarName
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    // MARK: - Reading

    /// Fetch all Forge events within a date range (default: -30 days to +365 days).
    public func fetchEvents(
        from calendar: EKCalendar,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) -> [EKEvent] {
        let start = startDate ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let end = endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: Date())!

        let predicate = store.predicateForEvents(
            withStart: start, end: end, calendars: [calendar]
        )
        return store.events(matching: predicate)
    }

    /// Async version: fetch events without blocking the calling thread.
    public func fetchEvents(
        from calendar: EKCalendar,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async -> [EKEvent] {
        let start = startDate ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let end = endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: Date())!
        let predicate = store.predicateForEvents(
            withStart: start, end: end, calendars: [calendar]
        )
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [store] in
                let events = store.events(matching: predicate)
                continuation.resume(returning: events)
            }
        }
    }

    /// Extract the forge task ID from an event's notes field.
    public func extractForgeID(from event: EKEvent) -> (project: String, taskID: String)? {
        guard let notes = event.notes, notes.contains("forge:") else { return nil }

        let lines = notes.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("forge:") else { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 2)
            guard parts.count == 3 else { continue }
            return (project: String(parts[1]), taskID: String(parts[2]))
        }
        return nil
    }

    // MARK: - Writing

    /// Create an all-day calendar event for a task with a due date.
    /// Area tags are included in the event title and notes.
    public func createEvent(
        for task: ForgeTask, projectName: String,
        tags: [String] = [], in calendar: EKCalendar
    ) throws -> EKEvent? {
        guard let dueDate = task.dueDate else { return nil }

        let tagPrefix = tags.isEmpty ? "" : "[\(tags.joined(separator: "/"))] "
        let event = EKEvent(eventStore: store)
        event.title = "\(tagPrefix)[\(projectName)] \(task.text)"
        event.calendar = calendar
        event.isAllDay = true
        event.startDate = dueDate
        event.endDate = dueDate

        var notes = "forge:\(projectName):\(task.id)"
        if !tags.isEmpty {
            notes += "\ntags: \(tags.joined(separator: ", "))"
        }
        event.notes = notes

        try store.save(event, span: .thisEvent, commit: false)
        return event
    }

    /// Update an event's date.
    public func updateEventDate(_ event: EKEvent, to date: Date) throws {
        event.startDate = date
        event.endDate = date
        try store.save(event, span: .thisEvent, commit: false)
    }

    /// Remove an event (e.g. when a task is completed).
    public func removeEvent(_ event: EKEvent) throws {
        try store.remove(event, span: .thisEvent, commit: false)
    }

    /// Commit all pending changes.
    public func commit() throws {
        try store.commit()
    }

    // MARK: - Errors

    public enum BridgeError: Error, CustomStringConvertible {
        case noSource

        public var description: String {
            "No iCloud or local source found for Calendar."
        }
    }
}
