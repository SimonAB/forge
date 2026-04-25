import Foundation

/// Builds a `BriefContext` from the same sources the Forge apps use (Finder tags + EventKit/snapshot).
public struct BriefContextBuilder: Sendable {
    private let config: ForgeConfig
    private let forgeDir: String
    private let scanner: WorkspaceScanner

    public init(config: ForgeConfig, forgeDir: String, scanner: WorkspaceScanner? = nil) {
        self.config = config
        self.forgeDir = forgeDir
        self.scanner = scanner ?? WorkspaceScanner(config: config)
    }

    /// Build a context snapshot for the given horizon.
    ///
    /// - Parameters:
    ///   - days: Number of days of calendar events to include, starting today (unless calendar is unavailable).
    ///   - includeCalendar: When false, skips calendar resolution entirely.
    public func build(days: Int = 2, includeCalendar: Bool = true) async throws -> BriefContext {
        let now = Date()
        let projects = try await scanner.scanProjects()
        let board = buildBoardSnapshot(projects: projects, now: now)

        let calendar: CalendarSnapshot?
        if includeCalendar {
            calendar = try await buildCalendarSnapshot(days: days)
        } else {
            calendar = nil
        }

        return BriefContext(generatedAt: now, board: board, calendar: calendar)
    }

    private func buildBoardSnapshot(projects: [Project], now: Date) -> BoardSnapshot {
        let columns = config.board.columns.map { ColumnSnapshot(name: $0.name, tag: $0.tag) }
        let metaTags = config.board.metaTags
        let tagAliases = config.board.tagAliases

        let projectSnapshots = projects.map { project in
            let resolution = KanbanRadar.activityResolution(for: project)
            return ProjectSnapshot(
                name: project.name,
                path: project.path,
                column: project.column,
                workflowTag: project.workflowTag,
                metaTags: project.metaTags,
                assignees: project.assignees,
                radarBucket: KanbanRadar.bucket(for: project, now: now),
                daysSinceActivity: KanbanRadar.daysSinceActivity(for: project, now: now),
                activityModificationDate: resolution.modificationDate,
                activitySource: resolution.source
            )
        }

        return BoardSnapshot(columns: columns, metaTags: metaTags, tagAliases: tagAliases, projects: projectSnapshots)
    }

    private func buildCalendarSnapshot(days: Int) async throws -> CalendarSnapshot {
        let result = try await CalendarEventsResolution.resolve(
            forgeDir: forgeDir,
            config: config,
            days: days,
            customStart: nil
        )
        let source: String = {
            switch result.source {
            case .forgeAppSnapshot(let generatedAt):
                return "forge_app_snapshot:\(generatedAt.timeIntervalSince1970)"
            case .liveEventKit:
                return "live_eventkit"
            }
        }()

        let events = result.events.map {
            CalendarEventSnapshot(
                title: $0.title,
                startDate: $0.startDate,
                endDate: $0.endDate,
                isAllDay: $0.isAllDay,
                location: $0.location
            )
        }

        return CalendarSnapshot(windowStart: result.windowStart, windowEnd: result.windowEnd, source: source, events: events)
    }
}
