import Foundation

/// JSON file under `<forgeDir>/.cache/calendar-snapshot.json`, written by **Forge.app** after background sync
/// so the `forge` CLI can show Calendar data without requiring Calendars permission for the terminal.
public enum CalendarSnapshotStore {
    public static let fileName = "calendar-snapshot.json"

    /// Bumped when the JSON shape of `Payload` or `CalendarEventSummary` changes in a material way.
    public static let currentSchemaVersion = 2

    /// How long a snapshot remains acceptable for the CLI before falling back to live EventKit (if Forge.app has not refreshed).
    public static let defaultMaxAge: TimeInterval = 900

    public static func cachePath(forgeDir: String) -> String {
        (forgeDir as NSString).appendingPathComponent(".cache/\(fileName)")
    }

    /// Events grouped by calendar day (start-of-day), for readable cache inspection and tools that prefer day buckets.
    public struct CalendarSnapshotDay: Codable, Sendable, Equatable {
        public let dayStart: Date
        public let events: [CalendarEventSummary]

        public init(dayStart: Date, events: [CalendarEventSummary]) {
            self.dayStart = dayStart
            self.events = events
        }
    }

    /// Builds day buckets using the same rules as `CalendarScheduleFormatting.groupByDay`.
    public static func groupedDays(
        from events: [CalendarEventSummary],
        calendar: Calendar = .current
    ) -> [CalendarSnapshotDay] {
        CalendarScheduleFormatting.groupByDay(events, calendar: calendar).map {
            CalendarSnapshotDay(dayStart: $0.dayStart, events: $0.events)
        }
    }

    public struct Payload: Codable, Sendable, Equatable {
        public let schemaVersion: Int
        public let generatedAt: Date
        public let windowStart: Date
        public let windowEnd: Date
        public let horizonDays: Int
        public let calendarInclude: [String]
        /// Time zone identifier captured when the snapshot was written (e.g. `Europe/London`).
        public let timeZoneIdentifier: String
        public let events: [CalendarEventSummary]
        public let groupedByDay: [CalendarSnapshotDay]
        public let writer: String

        enum CodingKeys: String, CodingKey {
            case schemaVersion, generatedAt, windowStart, windowEnd, horizonDays, calendarInclude
            case timeZoneIdentifier, events, groupedByDay, writer
        }

        public init(
            generatedAt: Date,
            windowStart: Date,
            windowEnd: Date,
            horizonDays: Int,
            calendarInclude: [String],
            events: [CalendarEventSummary],
            writer: String = "Forge.app",
            schemaVersion: Int = CalendarSnapshotStore.currentSchemaVersion,
            timeZoneIdentifier: String = TimeZone.current.identifier,
            groupedByDay: [CalendarSnapshotDay]? = nil,
            calendarForGrouping: Calendar = .current
        ) {
            self.schemaVersion = schemaVersion
            self.generatedAt = generatedAt
            self.windowStart = windowStart
            self.windowEnd = windowEnd
            self.horizonDays = horizonDays
            self.calendarInclude = calendarInclude
            self.timeZoneIdentifier = timeZoneIdentifier
            self.events = events
            self.groupedByDay = groupedByDay ?? CalendarSnapshotStore.groupedDays(from: events, calendar: calendarForGrouping)
            self.writer = writer
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            generatedAt = try c.decode(Date.self, forKey: .generatedAt)
            windowStart = try c.decode(Date.self, forKey: .windowStart)
            windowEnd = try c.decode(Date.self, forKey: .windowEnd)
            horizonDays = try c.decode(Int.self, forKey: .horizonDays)
            calendarInclude = try c.decode([String].self, forKey: .calendarInclude)
            timeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .timeZoneIdentifier) ?? TimeZone.current.identifier
            events = try c.decode([CalendarEventSummary].self, forKey: .events)
            if let grouped = try c.decodeIfPresent([CalendarSnapshotDay].self, forKey: .groupedByDay), !grouped.isEmpty {
                groupedByDay = grouped
            } else {
                groupedByDay = CalendarSnapshotStore.groupedDays(from: events)
            }
            writer = try c.decodeIfPresent(String.self, forKey: .writer) ?? "Forge.app"
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(schemaVersion, forKey: .schemaVersion)
            try c.encode(generatedAt, forKey: .generatedAt)
            try c.encode(windowStart, forKey: .windowStart)
            try c.encode(windowEnd, forKey: .windowEnd)
            try c.encode(horizonDays, forKey: .horizonDays)
            try c.encode(calendarInclude, forKey: .calendarInclude)
            try c.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
            try c.encode(events, forKey: .events)
            try c.encode(groupedByDay, forKey: .groupedByDay)
            try c.encode(writer, forKey: .writer)
        }
    }

    /// Writes atomically; creates `.cache` if needed.
    public static func write(forgeDir: String, payload: Payload) throws {
        let cacheDir = (forgeDir as NSString).appendingPathComponent(".cache")
        try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let path = cachePath(forgeDir: forgeDir)
        let tmp = path + ".tmp"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: URL(fileURLWithPath: tmp), options: .atomic)
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
        try FileManager.default.moveItem(atPath: tmp, toPath: path)
    }

    public static func read(forgeDir: String) throws -> Payload? {
        let path = cachePath(forgeDir: forgeDir)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Payload.self, from: data)
    }

    /// Returns a payload if it can satisfy a **default-anchor** (`Date()`), no-custom-`--start` request without live EventKit.
    public static func loadIfEligible(
        forgeDir: String,
        config: ForgeConfig,
        requestedDays: Int,
        hasCustomStart: Bool,
        maxAge: TimeInterval = defaultMaxAge,
        calendar: Calendar = .current
    ) throws -> Payload? {
        guard !hasCustomStart else { return nil }
        guard requestedDays >= 1 else { return nil }
        guard let payload = try read(forgeDir: forgeDir) else { return nil }
        if Date().timeIntervalSince(payload.generatedAt) > maxAge { return nil }
        if payload.horizonDays < requestedDays { return nil }
        let configSet = Set(config.gtd.calendarInclude.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let payloadSet = Set(payload.calendarInclude.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        if configSet != payloadSet { return nil }
        guard calendar.isDate(payload.generatedAt, inSameDayAs: Date()) else { return nil }
        return payload
    }

    /// Events from a snapshot overlapping `[windowStart, windowEnd)` (exclusive end for predicate parity).
    public static func filterEvents(
        _ events: [CalendarEventSummary],
        windowStart: Date,
        windowEnd: Date
    ) -> [CalendarEventSummary] {
        events.filter { ev in
            ev.startDate < windowEnd && ev.endDate > windowStart
        }
        .sorted { $0.startDate < $1.startDate }
    }
}

// MARK: - CLI resolution (snapshot first, then EventKit)

/// Fetches calendar events for the CLI, preferring a **Forge.app** snapshot when valid.
public enum CalendarEventsResolution {
    public struct Result: Sendable {
        public let events: [CalendarEventSummary]
        public let windowStart: Date
        public let windowEnd: Date
        public let source: Source
    }

    public enum Source: Equatable, Sendable {
        case forgeAppSnapshot(generatedAt: Date)
        case liveEventKit
    }

    /// Resolves events: uses `Forge.app` snapshot when eligible; otherwise `EventKit` (terminal must have Calendars permission).
    public static func resolve(
        forgeDir: String,
        config: ForgeConfig,
        days: Int,
        customStart: Date?,
        maxSnapshotAge: TimeInterval = CalendarSnapshotStore.defaultMaxAge,
        calendar: Calendar = .current
    ) async throws -> Result {
        let hasCustomStart = customStart != nil
        let anchor = customStart ?? Date()
        let (windowStart, windowEnd) = CalendarScheduleFormatting.dateWindow(anchor: anchor, days: days, calendar: calendar)

        if let payload = try CalendarSnapshotStore.loadIfEligible(
            forgeDir: forgeDir,
            config: config,
            requestedDays: days,
            hasCustomStart: hasCustomStart,
            maxAge: maxSnapshotAge,
            calendar: calendar
        ) {
            let filtered = CalendarSnapshotStore.filterEvents(payload.events, windowStart: windowStart, windowEnd: windowEnd)
            return Result(
                events: filtered,
                windowStart: windowStart,
                windowEnd: windowEnd,
                source: .forgeAppSnapshot(generatedAt: payload.generatedAt)
            )
        }

        let reader = CalendarScheduleReader()
        try await reader.requestAccess()
        let events = reader.fetchEvents(from: windowStart, to: windowEnd, calendarTitleAllowlist: config.gtd.calendarInclude)
        return Result(events: events, windowStart: windowStart, windowEnd: windowEnd, source: .liveEventKit)
    }
}
