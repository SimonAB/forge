import Foundation

/// A snapshot of the board and (optionally) calendar events, suitable for producing a brief.
///
/// This is intentionally serialisable and provider-agnostic so it can be passed to a local model,
/// a remote provider, or an external agent backend.
public struct BriefContext: Codable, Sendable {
    public let generatedAt: Date
    public let board: BoardSnapshot
    public let calendar: CalendarSnapshot?

    public init(generatedAt: Date, board: BoardSnapshot, calendar: CalendarSnapshot?) {
        self.generatedAt = generatedAt
        self.board = board
        self.calendar = calendar
    }
}

/// Board data as seen by the app at a point in time.
public struct BoardSnapshot: Codable, Sendable {
    public let columns: [ColumnSnapshot]
    public let metaTags: [String]
    public let tagAliases: [String: String]
    public let projects: [ProjectSnapshot]

    public init(columns: [ColumnSnapshot], metaTags: [String], tagAliases: [String: String], projects: [ProjectSnapshot]) {
        self.columns = columns
        self.metaTags = metaTags
        self.tagAliases = tagAliases
        self.projects = projects
    }
}

/// A workflow column (name + tag) from configuration.
public struct ColumnSnapshot: Codable, Sendable {
    public let name: String
    public let tag: String

    public init(name: String, tag: String) {
        self.name = name
        self.tag = tag
    }
}

/// A single project directory as classified by Forge plus radar signals.
public struct ProjectSnapshot: Codable, Sendable {
    public let name: String
    public let path: String
    public let column: String?
    public let workflowTag: String?
    public let metaTags: [String]
    public let assignees: [String]

    public let radarBucket: KanbanRadarBucket
    public let daysSinceActivity: Double
    public let activityModificationDate: Date
    public let activitySource: String

    public init(
        name: String,
        path: String,
        column: String?,
        workflowTag: String?,
        metaTags: [String],
        assignees: [String],
        radarBucket: KanbanRadarBucket,
        daysSinceActivity: Double,
        activityModificationDate: Date,
        activitySource: String
    ) {
        self.name = name
        self.path = path
        self.column = column
        self.workflowTag = workflowTag
        self.metaTags = metaTags
        self.assignees = assignees
        self.radarBucket = radarBucket
        self.daysSinceActivity = daysSinceActivity
        self.activityModificationDate = activityModificationDate
        self.activitySource = activitySource
    }
}

/// Calendar events in a fixed window.
public struct CalendarSnapshot: Codable, Sendable {
    public let windowStart: Date
    public let windowEnd: Date
    public let source: String
    public let events: [CalendarEventSnapshot]

    public init(windowStart: Date, windowEnd: Date, source: String, events: [CalendarEventSnapshot]) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.source = source
        self.events = events
    }
}

/// A simplified calendar event record for brief generation.
public struct CalendarEventSnapshot: Codable, Sendable {
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let location: String?

    public init(title: String, startDate: Date, endDate: Date, isAllDay: Bool, location: String?) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
    }
}
