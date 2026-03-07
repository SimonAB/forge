@preconcurrency import EventKit
import Foundation

/// Two-way sync engine that reconciles markdown tasks with Reminders and Calendar.
public final class SyncEngine: @unchecked Sendable {

    private let config: ForgeConfig
    private let forgeDir: String
    private let markdownIO: MarkdownIO
    private let remindersBridge: RemindersBridge
    private let calendarBridge: CalendarBridge
    private let store: EKEventStore

    /// Summary of sync actions performed.
    public struct SyncReport: Sendable {
        public var remindersCreated: Int = 0
        public var remindersCompleted: Int = 0
        public var remindersMoved: Int = 0
        public var eventsCreated: Int = 0
        public var eventsUpdated: Int = 0
        public var eventsRemoved: Int = 0
        public var tasksCompleted: Int = 0
        public var tasksUpdated: Int = 0
        public var inboxItemsAdded: Int = 0
        public var rollupAreas: Int = 0
        public var rollupTasks: Int = 0
        public var errors: [String] = []
    }

    /// Initialise the sync engine.
    ///
    /// - Parameters:
    ///   - config: The loaded forge configuration.
    ///   - forgeDir: Explicit path to the Forge directory. Falls back to workspace-relative if nil.
    public init(config: ForgeConfig, forgeDir: String? = nil) {
        self.config = config
        self.forgeDir = forgeDir ?? (config.resolvedWorkspacePath as NSString).appendingPathComponent("Forge")
        self.markdownIO = MarkdownIO()
        self.store = EKEventStore()
        self.remindersBridge = RemindersBridge(
            store: store, listName: config.gtd.remindersList
        )
        self.calendarBridge = CalendarBridge(
            store: store, calendarName: config.gtd.calendarName
        )
    }

    /// A task with its source metadata for sync purposes.
    struct SourcedTask {
        let task: ForgeTask
        /// Path to the markdown file containing this task.
        let filePath: String
        /// Area-level tags from frontmatter (e.g. "work", "personal").
        let areaTags: [String]
        /// True if this task lives in an area file rather than a project TASKS.md.
        let isAreaTask: Bool
    }

    /// Perform a full two-way sync.
    public func sync() async throws -> SyncReport {
        var report = SyncReport()

        try await remindersBridge.requestAccess()
        try await calendarBridge.requestAccess()

        _ = try remindersBridge.findOrCreateList(context: nil)
        let forgeLists = remindersBridge.allForgeListCalendars()
        let calendar = try calendarBridge.findOrCreateCalendar()

        let sourced = try collectAllTasks()
        let allTasks = sourced.map(\.task)

        let reminders = try await remindersBridge.fetchReminders(from: forgeLists)
        let events = calendarBridge.fetchEvents(from: calendar)

        var remindersByID = buildReminderIndex(reminders)
        let eventsByID = buildEventIndex(events)
        let tasksByID = Dictionary(allTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sourceByID = Dictionary(sourced.map { ($0.task.id, $0) }, uniquingKeysWith: { first, _ in first })

        var seenTaskIDs = Set<String>()
        for st in sourced {
            guard seenTaskIDs.insert(st.task.id).inserted else { continue }
            let list = try remindersBridge.findOrCreateList(context: st.task.context)
            syncTaskToReminders(
                task: st.task, tags: st.areaTags,
                remindersByID: &remindersByID,
                list: list, report: &report
            )
            syncTaskToCalendar(
                task: st.task, tags: st.areaTags,
                eventsByID: eventsByID,
                calendar: calendar, report: &report
            )
        }

        try syncRemindersToMarkdown(
            reminders: reminders, tasksByID: tasksByID,
            sourceByID: sourceByID, report: &report
        )

        try syncEventsToMarkdown(
            events: events, tasksByID: tasksByID,
            sourceByID: sourceByID, report: &report
        )

        applyFinderTags(sourced: sourced)

        if !config.projectAreas.isEmpty {
            let rollup = RollupGenerator(config: config, forgeDir: forgeDir)
            if let rollupReport = try? rollup.generateAll() {
                report.rollupAreas = rollupReport.areasUpdated
                report.rollupTasks = rollupReport.tasksLinked
            }
        }

        try remindersBridge.commit()
        try calendarBridge.commit()

        return report
    }

    // MARK: - Collect Tasks

    private func collectAllTasks() throws -> [SourcedTask] {
        var result: [SourcedTask] = []

        let scanner = WorkspaceScanner(config: config)
        let projects = try scanner.scanProjects()

        for project in projects {
            let tasksPath = (project.path as NSString).appendingPathComponent("TASKS.md")
            guard FileManager.default.fileExists(atPath: tasksPath) else { continue }

            let tasks = (try? markdownIO.parseTasks(at: tasksPath, projectName: project.name)) ?? []
            for task in tasks {
                result.append(SourcedTask(
                    task: task, filePath: tasksPath,
                    areaTags: config.workspaceTags, isAreaTask: false
                ))
            }
        }

        let areaFiles = scanAreaFiles()
        for area in areaFiles {
            let content = (try? String(contentsOfFile: area.path, encoding: .utf8)) ?? ""
            let (frontmatter, body) = Frontmatter.parse(from: content)
            let tags = frontmatter?.tags ?? []
            let tasks = markdownIO.parseTasks(from: body, projectName: area.name)
            for task in tasks {
                result.append(SourcedTask(
                    task: task, filePath: area.path,
                    areaTags: tags, isAreaTask: true
                ))
            }
        }

        return result
    }

    /// Scan area markdown files in the Forge directory with their frontmatter.
    private func scanAreaFiles() -> [(path: String, name: String, frontmatter: Frontmatter?)] {
        let fm = FileManager.default
        let excluded: Set<String> = ["config.yaml", "someday-maybe.md"]
        guard let entries = try? fm.contentsOfDirectory(atPath: forgeDir) else { return [] }
        var result: [(path: String, name: String, frontmatter: Frontmatter?)] = []
        for entry in entries.sorted() where entry.hasSuffix(".md") {
            guard !excluded.contains(entry) else { continue }
            let filePath = (forgeDir as NSString).appendingPathComponent(entry)
            let content = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            let (fm, _) = Frontmatter.parse(from: content)
            let name = (entry as NSString).deletingPathExtension.capitalized
            result.append((filePath, name, fm))
        }
        return result
    }

    // MARK: - Index Building

    private func buildReminderIndex(_ reminders: [EKReminder]) -> [String: EKReminder] {
        var index: [String: EKReminder] = [:]
        for reminder in reminders {
            if let ids = remindersBridge.extractForgeID(from: reminder) {
                index[ids.taskID] = reminder
            }
        }
        return index
    }

    private func buildEventIndex(_ events: [EKEvent]) -> [String: EKEvent] {
        var index: [String: EKEvent] = [:]
        for event in events {
            if let ids = calendarBridge.extractForgeID(from: event) {
                index[ids.taskID] = event
            }
        }
        return index
    }

    // MARK: - Markdown -> Reminders

    private func syncTaskToReminders(
        task: ForgeTask,
        tags: [String],
        remindersByID: inout [String: EKReminder],
        list: EKCalendar,
        report: inout SyncReport
    ) {
        if let reminder = remindersByID[task.id] {
            if task.isCompleted && !reminder.isCompleted {
                do {
                    try remindersBridge.completeReminder(reminder)
                    report.remindersCompleted += 1
                } catch {
                    report.errors.append("Failed to complete reminder for \(task.id): \(error)")
                }
            } else if !task.isCompleted {
                if reminder.calendar?.calendarIdentifier != list.calendarIdentifier {
                    do {
                        try remindersBridge.moveReminder(reminder, to: list)
                        report.remindersMoved += 1
                    } catch {
                        report.errors.append("Failed to move reminder \(task.id) to list: \(error)")
                    }
                }
                remindersBridge.updateTags(on: reminder, tags: tags)
            }
        } else if !task.isCompleted {
            do {
                let reminder = try remindersBridge.createReminder(
                    for: task, projectName: task.projectName ?? "Unknown",
                    tags: tags, in: list
                )
                remindersByID[task.id] = reminder
                report.remindersCreated += 1
            } catch {
                report.errors.append("Failed to create reminder for \(task.id): \(error)")
            }
        }
    }

    // MARK: - Markdown -> Calendar

    private func syncTaskToCalendar(
        task: ForgeTask,
        tags: [String],
        eventsByID: [String: EKEvent],
        calendar: EKCalendar,
        report: inout SyncReport
    ) {
        if let event = eventsByID[task.id] {
            if task.isCompleted {
                do {
                    try calendarBridge.removeEvent(event)
                    report.eventsRemoved += 1
                } catch {
                    report.errors.append("Failed to remove event for \(task.id): \(error)")
                }
            } else if let dueDate = task.dueDate,
                      !Calendar.current.isDate(event.startDate, inSameDayAs: dueDate) {
                do {
                    try calendarBridge.updateEventDate(event, to: dueDate)
                    report.eventsUpdated += 1
                } catch {
                    report.errors.append("Failed to update event for \(task.id): \(error)")
                }
            }
        } else if !task.isCompleted && task.dueDate != nil {
            do {
                _ = try calendarBridge.createEvent(
                    for: task, projectName: task.projectName ?? "Unknown",
                    tags: tags, in: calendar
                )
                report.eventsCreated += 1
            } catch {
                report.errors.append("Failed to create event for \(task.id): \(error)")
            }
        }
    }

    // MARK: - Reminders -> Markdown

    private func syncRemindersToMarkdown(
        reminders: [EKReminder],
        tasksByID: [String: ForgeTask],
        sourceByID: [String: SourcedTask],
        report: inout SyncReport
    ) throws {
        for reminder in reminders {
            if let ids = remindersBridge.extractForgeID(from: reminder) {
                if let task = tasksByID[ids.taskID],
                   reminder.isCompleted && !task.isCompleted {
                    if let source = sourceByID[ids.taskID] {
                        if try markdownIO.completeTask(withID: ids.taskID, inFileAt: source.filePath) {
                            report.tasksCompleted += 1
                        }
                    }
                }
            } else if !reminder.isCompleted {
                let inboxPath = (forgeDir as NSString)
                    .appendingPathComponent("inbox.md")
                let incomingRepeat = reminder.recurrenceRules?.first.flatMap {
                    remindersBridge.repeatRule(from: $0)
                }
                let incomingDefer: Date? = reminder.startDateComponents.flatMap {
                    Calendar.current.date(from: $0)
                }
                let task = ForgeTask(
                    id: ForgeTask.newID(),
                    text: reminder.title ?? "Untitled",
                    section: .nextActions,
                    source: "reminders",
                    deferDate: incomingDefer,
                    repeatRule: incomingRepeat
                )
                try markdownIO.appendTask(task, toFileAt: inboxPath)
                report.inboxItemsAdded += 1

                reminder.notes = remindersBridge.formatNotes(
                    project: "Inbox", taskID: task.id, tags: ["work", "personal"]
                )
                try? store.save(reminder, commit: false)
            }
        }
    }

    // MARK: - Finder Tags

    /// Apply frontmatter tags as Finder tags on area markdown files.
    /// Also ensures each project directory has its kanban column tag (so Finder reflects the board).
    private func applyFinderTags(sourced: [SourcedTask]) {
        let tagStore = FinderTagStore()
        var processed = Set<String>()

        for st in sourced where st.isAreaTask {
            guard !processed.contains(st.filePath) else { continue }
            processed.insert(st.filePath)

            let desired = Set(st.areaTags)
            guard !desired.isEmpty else { continue }

            let existing = Set((try? tagStore.readTags(at: st.filePath)) ?? [])
            let toAdd = desired.subtracting(existing)

            for tag in toAdd {
                try? tagStore.addTag(tag, at: st.filePath)
            }
        }

        let areaFiles = scanAreaFiles()
        for area in areaFiles {
            guard !processed.contains(area.path) else { continue }
            guard let tags = area.frontmatter?.tags, !tags.isEmpty else { continue }

            let existing = Set((try? tagStore.readTags(at: area.path)) ?? [])
            for tag in tags where !existing.contains(tag) {
                try? tagStore.addTag(tag, at: area.path)
            }
        }

        let scanner = WorkspaceScanner(config: config, tagStore: tagStore)
        guard let projects = try? scanner.scanProjects() else { return }
        for project in projects {
            guard let columnTag = project.workflowTag else { continue }
            let existing = Set((try? tagStore.readTags(at: project.path)) ?? [])
            if !existing.contains(columnTag) {
                try? tagStore.addTag(columnTag, at: project.path)
            }
        }
    }

    // MARK: - Calendar -> Markdown

    private func syncEventsToMarkdown(
        events: [EKEvent],
        tasksByID: [String: ForgeTask],
        sourceByID: [String: SourcedTask],
        report: inout SyncReport
    ) throws {
        for event in events {
            guard let ids = calendarBridge.extractForgeID(from: event),
                  let task = tasksByID[ids.taskID] else { continue }

            guard let taskDue = task.dueDate else { continue }
            guard !Calendar.current.isDate(event.startDate, inSameDayAs: taskDue) else { continue }

            guard let source = sourceByID[ids.taskID] else { continue }
            let newDate = Calendar.current.startOfDay(for: event.startDate)
            if try markdownIO.updateTaskDueDate(withID: ids.taskID, to: newDate, inFileAt: source.filePath) {
                report.tasksUpdated += 1
            }
        }
    }
}
