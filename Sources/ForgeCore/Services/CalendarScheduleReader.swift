import EventKit
import Foundation

// MARK: - Summary model

/// A read-only snapshot of a Calendar event for CLI and JSON output.
public enum CalendarReaderError: Error, CustomStringConvertible {
    case accessDenied

        public var description: String {
        switch self {
        case .accessDenied:
            return "Access to Calendars was denied for this terminal. Either allow Calendars for your terminal app in System Settings → Privacy & Security → Calendars, or rely on Forge.app: keep Forge running so it can refresh \(CalendarSnapshotStore.fileName) under your Forge directory’s .cache (written after background sync)."
        }
    }
}

public struct CalendarEventSummary: Sendable, Codable, Equatable {
    public let title: String
    public let calendarTitle: String
    public let isAllDay: Bool
    public let startDate: Date
    public let endDate: Date
    public let location: String?
    /// Trimmed notes (length-capped when built from EventKit for snapshot size).
    public let notes: String?
    public let url: String?
    public let eventIdentifier: String?
    public let calendarIdentifier: String?
    public let organizerName: String?
    public let hasRecurrenceRules: Bool
    public let isDetached: Bool
    /// One of: busy, free, tentative, unavailable; omitted when unknown or not supported.
    public let availability: String?
    public let attendeeCount: Int?

    enum CodingKeys: String, CodingKey {
        case title, calendarTitle, isAllDay, startDate, endDate, location
        case notes, url, eventIdentifier, calendarIdentifier, organizerName
        case hasRecurrenceRules, isDetached, availability, attendeeCount
    }

    public init(
        title: String,
        calendarTitle: String,
        isAllDay: Bool,
        startDate: Date,
        endDate: Date,
        location: String?,
        notes: String? = nil,
        url: String? = nil,
        eventIdentifier: String? = nil,
        calendarIdentifier: String? = nil,
        organizerName: String? = nil,
        hasRecurrenceRules: Bool = false,
        isDetached: Bool = false,
        availability: String? = nil,
        attendeeCount: Int? = nil
    ) {
        self.title = title
        self.calendarTitle = calendarTitle
        self.isAllDay = isAllDay
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
        self.url = url
        self.eventIdentifier = eventIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.organizerName = organizerName
        self.hasRecurrenceRules = hasRecurrenceRules
        self.isDetached = isDetached
        self.availability = availability
        self.attendeeCount = attendeeCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        calendarTitle = try c.decode(String.self, forKey: .calendarTitle)
        isAllDay = try c.decode(Bool.self, forKey: .isAllDay)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        eventIdentifier = try c.decodeIfPresent(String.self, forKey: .eventIdentifier)
        calendarIdentifier = try c.decodeIfPresent(String.self, forKey: .calendarIdentifier)
        organizerName = try c.decodeIfPresent(String.self, forKey: .organizerName)
        hasRecurrenceRules = try c.decodeIfPresent(Bool.self, forKey: .hasRecurrenceRules) ?? false
        isDetached = try c.decodeIfPresent(Bool.self, forKey: .isDetached) ?? false
        availability = try c.decodeIfPresent(String.self, forKey: .availability)
        attendeeCount = try c.decodeIfPresent(Int.self, forKey: .attendeeCount)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(calendarTitle, forKey: .calendarTitle)
        try c.encode(isAllDay, forKey: .isAllDay)
        try c.encode(startDate, forKey: .startDate)
        try c.encode(endDate, forKey: .endDate)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(eventIdentifier, forKey: .eventIdentifier)
        try c.encodeIfPresent(calendarIdentifier, forKey: .calendarIdentifier)
        try c.encodeIfPresent(organizerName, forKey: .organizerName)
        try c.encode(hasRecurrenceRules, forKey: .hasRecurrenceRules)
        try c.encode(isDetached, forKey: .isDetached)
        try c.encodeIfPresent(availability, forKey: .availability)
        try c.encodeIfPresent(attendeeCount, forKey: .attendeeCount)
    }
}

// MARK: - Formatting (testable)

/// Date windows, grouping, and string rendering for calendar output.
public enum CalendarScheduleFormatting {
    /// Inclusive start (start of first day) and exclusive end (start of day after last day), matching `EKEventStore` predicates.
    public static func dateWindow(anchor: Date, days: Int, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: anchor)
        let end = calendar.date(byAdding: .day, value: max(1, days), to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    /// Groups events by the start of the calendar day in the given time zone (default: current).
    public static func groupByDay(
        _ events: [CalendarEventSummary],
        calendar: Calendar = .current
    ) -> [(dayStart: Date, events: [CalendarEventSummary])] {
        let sorted = events.sorted { $0.startDate < $1.startDate }
        var buckets: [Date: [CalendarEventSummary]] = [:]
        for ev in sorted {
            let day = calendar.startOfDay(for: ev.startDate)
            buckets[day, default: []].append(ev)
        }
        return buckets.keys.sorted().map { ($0, buckets[$0] ?? []) }
    }

    /// One line for terminal / brief output (no ANSI codes).
    public static func compactLine(_ event: CalendarEventSummary, timeFormatter: DateFormatter, dateFormatter: DateFormatter) -> String {
        let calLabel = event.calendarTitle
        if event.isAllDay {
            let day = dateFormatter.string(from: event.startDate)
            let loc = event.location.map { " · \($0)" } ?? ""
            return "All day: \(event.title) (\(calLabel))\(loc) — \(day)"
        }
        let start = timeFormatter.string(from: event.startDate)
        let end = timeFormatter.string(from: event.endDate)
        let loc = event.location.map { " · \($0)" } ?? ""
        return "\(start)–\(end) \(event.title) (\(calLabel))\(loc)"
    }
}

// MARK: - Reader

/// Read-only access to macOS Calendar via EventKit (no writes).
public final class CalendarScheduleReader: @unchecked Sendable {
    private let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    /// Request full Calendar access (macOS 14+). Must succeed before fetching.
    public func requestAccess() async throws {
        let granted = try await store.requestFullAccessToEvents()
        if !granted {
            throw CalendarReaderError.accessDenied
        }

    }

    /// Fetch events overlapping `[start, end)` from event calendars, optionally filtered by calendar title.
    /// When `calendarTitleAllowlist` is empty, all event calendars are included.
    public func fetchEvents(from start: Date, to end: Date, calendarTitleAllowlist: [String]) -> [CalendarEventSummary] {
        let allEventCalendars = store.calendars(for: .event)
        let calendars: [EKCalendar]
        let trimmed = calendarTitleAllowlist.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if trimmed.isEmpty {
            calendars = allEventCalendars
        } else {
            let allow = Set(trimmed)
            calendars = allEventCalendars.filter { allow.contains($0.title) }
        }

        guard !calendars.isEmpty else {
            return []
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let raw = store.events(matching: predicate)
        return raw
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .map { ev in
                let title: String = {
                    guard let t = ev.title, !t.isEmpty else { return "(No title)" }
                    return t
                }()
                let loc = ev.location.flatMap { $0.isEmpty ? nil : $0 }
                let org = ev.organizer?.name.flatMap { $0.isEmpty ? nil : $0 }
                let attendees = ev.attendees
                let count = attendees.map(\.count)
                return CalendarEventSummary(
                    title: title,
                    calendarTitle: ev.calendar?.title ?? "?",
                    isAllDay: ev.isAllDay,
                    startDate: ev.startDate,
                    endDate: ev.endDate,
                    location: loc,
                    notes: Self.truncate(ev.notes, limit: 4000),
                    url: ev.url?.absoluteString,
                    eventIdentifier: ev.eventIdentifier,
                    calendarIdentifier: ev.calendar?.calendarIdentifier,
                    organizerName: org,
                    hasRecurrenceRules: ev.hasRecurrenceRules,
                    isDetached: ev.isDetached,
                    availability: Self.availabilityLabel(ev.availability),
                    attendeeCount: count
                )
            }
    }

    private static func truncate(_ text: String?, limit: Int) -> String? {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.count > limit {
            let end = text.index(text.startIndex, offsetBy: limit)
            text = String(text[..<end]) + "…"
        }
        return text
    }

    private static func availabilityLabel(_ value: EKEventAvailability) -> String? {
        switch value {
        case .busy: return "busy"
        case .free: return "free"
        case .tentative: return "tentative"
        case .unavailable: return "unavailable"
        case .notSupported: return nil
        @unknown default: return nil
        }
    }
}
