import Foundation

/// JSON payload from `scripts/forge-dashboard.py --json` (shared with the menubar popover).
public struct DashboardSnapshotJSON: Codable, Sendable {
    public struct World: Codable, Sendable {
        public let projects: Int
        public let openTasks: Int
        public let inbox: Int
        public let error: String?

        enum CodingKeys: String, CodingKey {
            case projects
            case openTasks = "open_tasks"
            case inbox
            case error
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            projects = try container.decode(Int.self, forKey: .projects)
            openTasks = try container.decode(Int.self, forKey: .openTasks)
            inbox = try container.decodeIfPresent(Int.self, forKey: .inbox) ?? 0
            error = try container.decodeIfPresent(String.self, forKey: .error)
        }
    }

    public struct InboxItem: Codable, Sendable, Identifiable {
        public var id: String { taskID }
        public let taskID: String
        public let title: String
        public let source: String?

        enum CodingKeys: String, CodingKey {
            case taskID = "task_id"
            case title, source
        }
    }

    public struct DueCounts: Codable, Sendable {
        public let overdue: Int
        public let today: Int
        public let upcoming: Int
    }

    public struct DueTask: Codable, Sendable, Identifiable {
        public var id: String { taskID }
        public let taskID: String
        public let due: String
        public let column: String?
        public let project: String
        public let title: String
        public let waiting: Bool

        enum CodingKeys: String, CodingKey {
            case taskID = "task_id"
            case due, column, project, title, waiting
        }
    }

    public struct ProjectHot: Codable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let column: String
        public let daysSinceActivity: Double
        public let assignees: [String]

        enum CodingKeys: String, CodingKey {
            case name, column
            case daysSinceActivity = "days_since_activity"
            case assignees
        }
    }

    public struct CalendarEvent: Codable, Sendable, Identifiable {
        public var id: String { "\(time)-\(title)" }
        public let title: String
        public let calendar: String
        public let time: String
        public let allDay: Bool

        enum CodingKeys: String, CodingKey {
            case title, calendar, time
            case allDay = "all_day"
        }
    }

    public let generatedAt: String
    public let columns: [String: Int]
    public let activeCount: Int
    public let world: World
    public let inbox: [InboxItem]
    public let inboxCount: Int
    public let calendarError: String?
    public let calendarToday: [CalendarEvent]
    public let dueOverdue: [DueTask]
    public let dueToday: [DueTask]
    public let dueUpcoming: [DueTask]
    public let dueCounts: DueCounts
    public let urgent: [ProjectHot]
    public let stuck: [ProjectHot]
    public let staleCount: Int

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case columns
        case activeCount = "active_count"
        case world
        case inbox
        case inboxCount = "inbox_count"
        case calendarError = "calendar_error"
        case calendarToday = "calendar_today"
        case dueOverdue = "due_overdue"
        case dueToday = "due_today"
        case dueUpcoming = "due_upcoming"
        case dueCounts = "due_counts"
        case urgent, stuck
        case staleCount = "stale_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        columns = try container.decode([String: Int].self, forKey: .columns)
        activeCount = try container.decode(Int.self, forKey: .activeCount)
        world = try container.decode(World.self, forKey: .world)
        inbox = try container.decodeIfPresent([InboxItem].self, forKey: .inbox) ?? []
        inboxCount = try container.decodeIfPresent(Int.self, forKey: .inboxCount) ?? world.inbox
        calendarError = try container.decodeIfPresent(String.self, forKey: .calendarError)
        calendarToday = try container.decode([CalendarEvent].self, forKey: .calendarToday)
        dueOverdue = try container.decode([DueTask].self, forKey: .dueOverdue)
        dueToday = try container.decode([DueTask].self, forKey: .dueToday)
        dueUpcoming = try container.decode([DueTask].self, forKey: .dueUpcoming)
        dueCounts = try container.decode(DueCounts.self, forKey: .dueCounts)
        urgent = try container.decode([ProjectHot].self, forKey: .urgent)
        stuck = try container.decode([ProjectHot].self, forKey: .stuck)
        staleCount = try container.decode(Int.self, forKey: .staleCount)
    }
}
