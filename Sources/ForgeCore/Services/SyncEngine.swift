@preconcurrency import EventKit
import Foundation

/// Two-way sync engine that reconciles markdown tasks with Reminders and Calendar.
public final class SyncEngine: @unchecked Sendable {

    private let config: ForgeConfig
    private let forgeDir: String
    /// Root directory for task files (inbox, area .md). When nil, forgeDir is used (backwards compatibility).
    private let taskFilesRoot: String
    private let markdownIO: MarkdownIO
    private let remindersBridge: RemindersBridge
    private let calendarBridge: CalendarBridge
    private let store: EKEventStore

    /// Summary of sync actions performed.
    public struct SyncReport: Sendable {
        public var remindersCreated: Int = 0
        public var remindersCompleted: Int = 0
        public var remindersMoved: Int = 0
        public var remindersDeduplicated: Int = 0
        public var remindersMergedByContent: Int = 0
        public var tasksMergedInMarkdown: Int = 0
        public var eventsCreated: Int = 0
        public var eventsUpdated: Int = 0
        public var eventsRemoved: Int = 0
        public var eventsDeduplicated: Int = 0
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
    ///   - taskFilesRoot: Root for inbox and area markdown files. When nil, forgeDir is used.
    public init(config: ForgeConfig, forgeDir: String? = nil, taskFilesRoot: String? = nil) {
        self.config = config
        self.forgeDir = forgeDir ?? (config.resolvedWorkspacePath as NSString).appendingPathComponent("Forge")
        self.taskFilesRoot = taskFilesRoot ?? self.forgeDir
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
    ///
    /// **Deduplication order:** Reminders are deduplicated first by Forge ID (same task synced to
    /// multiple lists), then by content (same logical task with different IDs; one is kept and
    /// non-canonical markdown tasks are removed). Events are deduplicated only by Forge ID.
    /// All downstream steps (indices, push to Reminders/Calendar, pull to markdown) use these
    /// deduplicated lists so we never push or pull duplicates.
    public func sync() async throws -> SyncReport {
        var report = SyncReport()
        var importedInboxSignatures: [ReminderContentSignature: String] = [:]

        try? FileManager.default.createDirectory(atPath: taskFilesRoot, withIntermediateDirectories: true)

        try await remindersBridge.requestAccess()
        try await calendarBridge.requestAccess()

        _ = try remindersBridge.findOrCreateList(context: nil)
        let forgeLists = remindersBridge.allForgeListCalendars()
        let calendar = try calendarBridge.findOrCreateCalendar()

        let areaFiles = scanAreaFiles()
        let sourced = try await collectAllTasks(areaFiles: areaFiles)
        let allTasks = sourced.map(\.task)

        let reminders = try await remindersBridge.fetchReminders(from: forgeLists)
        let events = await calendarBridge.fetchEvents(from: calendar)

        let tasksByID = Dictionary(allTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sourceByID = Dictionary(sourced.map { ($0.task.id, $0) }, uniquingKeysWith: { first, _ in first })

        var remindersAfterDedup = reminders
        remindersAfterDedup = try deduplicateRemindersByForgeID(
            remindersAfterDedup, sourceByID: sourceByID, report: &report
        )
        remindersAfterDedup = try deduplicateRemindersByContent(
            remindersAfterDedup, tasksByID: tasksByID, sourceByID: sourceByID, report: &report
        )

        var eventsAfterDedup = events
        eventsAfterDedup = deduplicateEventsByForgeID(eventsAfterDedup, sourceByID: sourceByID, report: &report)

        var remindersByID = buildReminderIndex(remindersAfterDedup)
        let eventsByID = buildEventIndex(eventsAfterDedup)

        // When the same task ID appears more than once in markdown, only sync the first to avoid duplicate reminders/events.
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
            reminders: remindersAfterDedup, tasksByID: tasksByID,
            sourceByID: sourceByID, report: &report,
            importedInboxSignatures: &importedInboxSignatures
        )

        try syncEventsToMarkdown(
            events: eventsAfterDedup, tasksByID: tasksByID,
            sourceByID: sourceByID, report: &report
        )

        await applyFinderTags(sourced: sourced, areaFiles: areaFiles)

        if !config.projectAreas.isEmpty {
            let rollup = RollupGenerator(config: config, forgeDir: forgeDir, taskFilesRoot: taskFilesRoot)
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

    /// Recursively find all TASKS.md files under each project root (not only direct children).
    /// This ensures nested project folders are included regardless of Finder tags.
    private func findAllProjectTaskFiles() -> [(path: String, projectName: String)] {
        var result: [(path: String, projectName: String)] = []
        for root in config.resolvedProjectRoots {
            let taskFiles = TaskFileFinder.findAll(under: root)
            for tf in taskFiles {
                result.append((path: tf.path, projectName: tf.label))
            }
        }
        return result
    }

    private func collectAllTasks(areaFiles: [(path: String, name: String, frontmatter: Frontmatter?, body: String)]) async throws -> [SourcedTask] {
        var result: [SourcedTask] = []

        let projectTaskFiles = findAllProjectTaskFiles()
        for (tasksPath, projectName) in projectTaskFiles {
            let tasks = (try? markdownIO.parseTasksAtPathAndPersistIds(at: tasksPath, projectName: projectName)) ?? []
            for task in tasks {
                result.append(SourcedTask(
                    task: task, filePath: tasksPath,
                    areaTags: config.workspaceTags, isAreaTask: false
                ))
            }
        }

        for area in areaFiles {
            let tags = area.frontmatter?.tags ?? []
            let (tasks, updatedBody) = markdownIO.parseTasksReturningUpdatedBody(from: area.body, projectName: area.name)
            if let updated = updatedBody {
                let output = MarkdownIO.reassemble(frontmatter: area.frontmatter?.touchingModified(), body: updated)
                try? output.write(toFile: area.path, atomically: true, encoding: .utf8)
            }
            for task in tasks {
                result.append(SourcedTask(
                    task: task, filePath: area.path,
                    areaTags: tags, isAreaTask: true
                ))
            }
        }

        return result
    }

    /// Scan area markdown files in the task files directory with their frontmatter and body (for task parsing).
    private func scanAreaFiles() -> [(path: String, name: String, frontmatter: Frontmatter?, body: String)] {
        let fm = FileManager.default
        let excluded: Set<String> = ["config.yaml", "someday-maybe.md", "inbox.md"]
        guard let entries = try? fm.contentsOfDirectory(atPath: taskFilesRoot) else { return [] }
        var result: [(path: String, name: String, frontmatter: Frontmatter?, body: String)] = []
        for entry in entries.sorted() where entry.hasSuffix(".md") {
            guard !excluded.contains(entry) else { continue }
            let filePath = (taskFilesRoot as NSString).appendingPathComponent(entry)
            let content = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            let (fmParsed, body) = Frontmatter.parse(from: content)
            let name = (entry as NSString).deletingPathExtension.capitalized
            result.append((filePath, name, fmParsed, body))
        }
        return result
    }

    // MARK: - Index Building

    private static func dayString(_ date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Content signature for grouping reminders that are the same logical task (for content-based deduplication).
    private struct ReminderContentSignature: Hashable {
        let normalisedTitle: String
        let listIdentifier: String
        let dueDay: String?
        let deferDay: String?
        let recurrenceString: String
    }

    private func reminderContentSignature(_ reminder: EKReminder) -> ReminderContentSignature {
        let title = (reminder.title ?? "")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "  ", with: " ")
        let listId = reminder.calendar?.calendarIdentifier ?? ""
        let dueDay: String? = reminder.dueDateComponents.flatMap { comp in
            guard let d = Calendar.current.date(from: comp) else { return nil }
            return Self.dayString(d)
        }
        let deferDay: String? = reminder.startDateComponents.flatMap { comp in
            guard let d = Calendar.current.date(from: comp) else { return nil }
            return Self.dayString(d)
        }
        let recurrenceString: String
        if let rule = reminder.recurrenceRules?.first {
            recurrenceString = "\(rule.frequency.rawValue)-\(rule.interval)"
        } else {
            recurrenceString = ""
        }
        return ReminderContentSignature(
            normalisedTitle: title,
            listIdentifier: listId,
            dueDay: dueDay,
            deferDay: deferDay,
            recurrenceString: recurrenceString
        )
    }

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

    /// Deduplicate reminders that share the same forge ID; keep one per (project, taskID), remove the rest.
    private func deduplicateRemindersByForgeID(
        _ reminders: [EKReminder],
        sourceByID: [String: SourcedTask],
        report: inout SyncReport
    ) throws -> [EKReminder] {
        var withoutID: [EKReminder] = []
        var byKey: [String: [EKReminder]] = [:]
        for r in reminders {
            if let ids = remindersBridge.extractForgeID(from: r) {
                let key = "\(ids.project):\(ids.taskID)"
                byKey[key, default: []].append(r)
            } else {
                withoutID.append(r)
            }
        }
        var result: [EKReminder] = []
        result.append(contentsOf: withoutID)
        for (_, group) in byKey {
            if group.count == 1 {
                result.append(group[0])
                continue
            }
            let taskID = remindersBridge.extractForgeID(from: group[0])!.taskID
            let preferredListId: String? = sourceByID[taskID].flatMap { st in
                (try? remindersBridge.findOrCreateList(context: st.task.context))?.calendarIdentifier
            }
            let sorted = group.sorted { r1, r2 in
                let m1 = r1.calendar?.calendarIdentifier == preferredListId
                let m2 = r2.calendar?.calendarIdentifier == preferredListId
                if m1 != m2 { return m1 }
                return false
            }
            result.append(sorted[0])
            for i in 1..<sorted.count {
                try remindersBridge.removeReminder(sorted[i])
                report.remindersDeduplicated += 1
            }
        }
        return result
    }

    /// Deduplicate reminders that have the same content but different forge IDs.
    private func deduplicateRemindersByContent(
        _ reminders: [EKReminder],
        tasksByID: [String: ForgeTask],
        sourceByID: [String: SourcedTask],
        report: inout SyncReport
    ) throws -> [EKReminder] {
        var bySig: [ReminderContentSignature: [EKReminder]] = [:]
        for r in reminders {
            bySig[reminderContentSignature(r), default: []].append(r)
        }
        var result: [EKReminder] = []
        for (_, group) in bySig {
            if group.count == 1 {
                result.append(group[0])
                continue
            }
            let taskIDsInGroup = group.compactMap { remindersBridge.extractForgeID(from: $0)?.taskID }
            let canonicalID: String? = taskIDsInGroup.isEmpty ? nil
                : (taskIDsInGroup.filter { tasksByID[$0] != nil }.sorted().first
                    ?? taskIDsInGroup.min()
                    ?? taskIDsInGroup.first)
            guard let canonicalID = canonicalID else {
                result.append(group[0])
                for i in 1..<group.count {
                    try? remindersBridge.removeReminder(group[i])
                    report.remindersMergedByContent += 1
                }
                continue
            }
            let projectName: String = {
                if let ids = remindersBridge.extractForgeID(from: group[0]) { return ids.project }
                let listTitle = group[0].calendar?.title ?? ""
                let prefix = "\(config.gtd.remindersList) • "
                if listTitle.hasPrefix(prefix) {
                    return String(listTitle.dropFirst(prefix.count))
                }
                return "Inbox"
            }()
            let keeperIndex = group.firstIndex(where: { remindersBridge.extractForgeID(from: $0)?.taskID == canonicalID }) ?? 0
            let keeper = group[keeperIndex]
            let tags = remindersBridge.extractTags(from: keeper)
            keeper.notes = remindersBridge.formatNotes(project: projectName, taskID: canonicalID, tags: tags)
            try? store.save(keeper, commit: false)

            for (idx, r) in group.enumerated() {
                if idx == keeperIndex { continue }
                let rid = remindersBridge.extractForgeID(from: r)?.taskID
                try remindersBridge.removeReminder(r)
                report.remindersMergedByContent += 1
                if let rid = rid, rid != canonicalID, let source = sourceByID[rid] {
                    if try markdownIO.removeTask(withID: rid, inFileAt: source.filePath) {
                        report.tasksMergedInMarkdown += 1
                    }
                }
            }
            result.append(keeper)
        }
        return result
    }

    /// Deduplicate events that share the same forge ID; keep one per (project, taskID), remove the rest.
    private func deduplicateEventsByForgeID(
        _ events: [EKEvent],
        sourceByID: [String: SourcedTask],
        report: inout SyncReport
    ) -> [EKEvent] {
        var withoutID: [EKEvent] = []
        var byKey: [String: [EKEvent]] = [:]
        for e in events {
            if let ids = calendarBridge.extractForgeID(from: e) {
                let key = "\(ids.project):\(ids.taskID)"
                byKey[key, default: []].append(e)
            } else {
                withoutID.append(e)
            }
        }
        var result: [EKEvent] = []
        result.append(contentsOf: withoutID)
        for (_, group) in byKey {
            if group.count == 1 {
                result.append(group[0])
                continue
            }
            let taskID = calendarBridge.extractForgeID(from: group[0])!.taskID
            let preferredStart = sourceByID[taskID]?.task.dueDate
            let sorted = group.sorted { e1, e2 in
                guard let pref = preferredStart else { return false }
                let m1 = Calendar.current.isDate(e1.startDate, inSameDayAs: pref)
                let m2 = Calendar.current.isDate(e2.startDate, inSameDayAs: pref)
                if m1 != m2 { return m1 }
                return false
            }
            result.append(sorted[0])
            for i in 1..<sorted.count {
                try? calendarBridge.removeEvent(sorted[i])
                report.eventsDeduplicated += 1
            }
        }
        return result
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
        report: inout SyncReport,
        importedInboxSignatures: inout [ReminderContentSignature: String]
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
                let sig = reminderContentSignature(reminder)
                if let existingTaskID = importedInboxSignatures[sig] {
                    reminder.notes = remindersBridge.formatNotes(
                        project: "Inbox", taskID: existingTaskID, tags: ["work", "personal"]
                    )
                    try? store.save(reminder, commit: false)
                    continue
                }
                let inboxPath = (taskFilesRoot as NSString)
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
                importedInboxSignatures[sig] = task.id

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
    private func applyFinderTags(sourced: [SourcedTask], areaFiles: [(path: String, name: String, frontmatter: Frontmatter?, body: String)]) async {
        let tagStore = FinderTagStore()
        var processed = Set<String>()

        for st in sourced where st.isAreaTask {
            guard !processed.contains(st.filePath) else { continue }
            processed.insert(st.filePath)

            let desired = Set(st.areaTags)
            guard !desired.isEmpty else { continue }

            let existing = Set(await tagStore.readTagsIfAvailable(at: st.filePath) ?? [])
            let toAdd = desired.subtracting(existing)

            for tag in toAdd {
                try? tagStore.addTag(tag, at: st.filePath)
            }
        }

        for area in areaFiles {
            guard !processed.contains(area.path) else { continue }
            guard let tags = area.frontmatter?.tags, !tags.isEmpty else { continue }

            let existing = Set(await tagStore.readTagsIfAvailable(at: area.path) ?? [])
            for tag in tags where !existing.contains(tag) {
                try? tagStore.addTag(tag, at: area.path)
            }
        }

        let scanner = WorkspaceScanner(config: config, tagStore: tagStore)
        guard let projects = try? await scanner.scanProjects() else { return }
        for project in projects {
            guard let columnTag = project.workflowTag else { continue }
            let existing = Set(await tagStore.readTagsIfAvailable(at: project.path) ?? [])
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
