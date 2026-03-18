@preconcurrency import EventKit
import Foundation

/// Two-way sync engine that reconciles markdown tasks with Reminders.
public final class SyncEngine: @unchecked Sendable {

    private let config: ForgeConfig
    private let forgeDir: String
    /// Root directory for task files (inbox, area .md). When nil, forgeDir is used (backwards compatibility).
    private let taskFilesRoot: String
    private let options: Options
    private let markdownIO: MarkdownIO
    private let remindersBridge: RemindersBridge
    private let store: EKEventStore

    /// Index of project task files used to avoid repeatedly walking large directory trees.
    private let taskIndex: TaskIndex
    private let taskDatabase: TaskFileDatabase?

    private struct ParsedReminderDue {
        let date: Date
        let hasTime: Bool
    }

    private func computeTaskChangeState(sourced: [SourcedTask]) throws -> (changedAtByID: [String: Date], changedSinceLastSync: Set<String>) {
        guard config.dueConflictPolicy == .newest, let db = taskDatabase else {
            return ([:], [])
        }

        let now = Date().timeIntervalSinceReferenceDate
        let fm = FileManager.default

        var taskIDs: [String] = []
        taskIDs.reserveCapacity(sourced.count)
        for st in sourced {
            taskIDs.append(st.task.id)
        }

        let existing = try db.taskFingerprints(for: taskIDs)

        var updates: [TaskFileDatabase.TaskFingerprintRecord] = []
        updates.reserveCapacity(sourced.count)

        var changedAtByID: [String: Date] = [:]
        changedAtByID.reserveCapacity(sourced.count)
        var changedSinceLastSync = Set<String>()

        for st in sourced {
            let task = st.task
            let fingerprint = Self.taskFingerprint(for: task)

            let baselineMtime: TimeInterval = {
                let attrs = try? fm.attributesOfItem(atPath: st.filePath)
                if let d = attrs?[.modificationDate] as? Date {
                    return d.timeIntervalSinceReferenceDate
                }
                return now
            }()

            if let ex = existing[task.id] {
                if ex.fingerprint == fingerprint {
                    updates.append(.init(taskID: task.id, fingerprint: fingerprint, lastChangedAt: ex.lastChangedAt))
                    changedAtByID[task.id] = Date(timeIntervalSinceReferenceDate: ex.lastChangedAt)
                } else {
                    updates.append(.init(taskID: task.id, fingerprint: fingerprint, lastChangedAt: now))
                    changedAtByID[task.id] = Date(timeIntervalSinceReferenceDate: now)
                    changedSinceLastSync.insert(task.id)
                }
            } else {
                updates.append(.init(taskID: task.id, fingerprint: fingerprint, lastChangedAt: baselineMtime))
                changedAtByID[task.id] = Date(timeIntervalSinceReferenceDate: baselineMtime)
            }
        }

        try db.upsertTaskFingerprints(updates)
        return (changedAtByID, changedSinceLastSync)
    }

    private static func taskFingerprint(for task: ForgeTask) -> String {
        let dueString: String
        if let due = task.dueDate {
            if task.dueHasTime {
                dueString = ISO8601DateFormatter().string(from: due)
            } else {
                let cal = Calendar.current
                let y = cal.component(.year, from: due)
                let m = cal.component(.month, from: due)
                let d = cal.component(.day, from: due)
                dueString = String(format: "%04d-%02d-%02d", y, m, d)
            }
        } else {
            dueString = ""
        }
        return "due=\(dueString)|hasTime=\(task.dueHasTime ? "1" : "0")"
    }

    private func parseReminderDue(_ reminder: EKReminder) -> ParsedReminderDue? {
        guard let comp = reminder.dueDateComponents,
              let d = Calendar.current.date(from: comp) else { return nil }
        let hasTime = (comp.hour != nil || comp.minute != nil)
        return ParsedReminderDue(date: d, hasTime: hasTime)
    }

    /// Summary of sync actions performed.
    public struct SyncReport: Sendable {
        public var remindersCreated: Int = 0
        public var remindersCompleted: Int = 0
        public var remindersLinkedByContent: Int = 0
        public var remindersMoved: Int = 0
        public var remindersDueUpdated: Int = 0
        public var remindersDueUpdatedTaskIDs: [String] = []
        public var remindersDueUpdatedDetails: [String] = []
        public var remindersDeduplicated: Int = 0
        public var remindersMergedByContent: Int = 0
        public var tasksMergedInMarkdown: Int = 0
        public var tasksCompleted: Int = 0
        public var tasksUpdated: Int = 0
        public var inboxItemsAdded: Int = 0
        public var rollupAreas: Int = 0
        public var rollupTasks: Int = 0
        public var errors: [String] = []
    }

    /// Controls which optional operations run during sync.
    public struct Options: Sendable {
        public var enableLinting: Bool
        public var enableDueSummary: Bool
        public var enableRollups: Bool
        public var enableFinderTags: Bool

        public init(
            enableLinting: Bool = true,
            enableDueSummary: Bool = true,
            enableRollups: Bool = true,
            enableFinderTags: Bool = true
        ) {
            self.enableLinting = enableLinting
            self.enableDueSummary = enableDueSummary
            self.enableRollups = enableRollups
            self.enableFinderTags = enableFinderTags
        }

        /// Full sync used by command-line tools and interactive flows.
        public static let full = Options()

        /// Lighter-weight sync for background timers where responsiveness matters more than
        /// always regenerating derived artefacts.
        public static let background = Options(
            enableLinting: false,
            enableDueSummary: true,
            enableRollups: false,
            enableFinderTags: false
        )
    }

    /// Initialise the sync engine.
    ///
    /// - Parameters:
    ///   - config: The loaded forge configuration.
    ///   - forgeDir: Explicit path to the Forge directory. Falls back to workspace-relative if nil.
    ///   - taskFilesRoot: Root for inbox and area markdown files. When nil, forgeDir is used.
    public init(
        config: ForgeConfig,
        forgeDir: String? = nil,
        taskFilesRoot: String? = nil,
        options: Options = .full,
        taskIndex: TaskIndex,
        taskDatabase: TaskFileDatabase? = nil
    ) {
        self.config = config
        self.forgeDir = forgeDir ?? (config.resolvedWorkspacePath as NSString).appendingPathComponent("Forge")
        self.taskFilesRoot = taskFilesRoot ?? self.forgeDir
        self.options = options
        self.markdownIO = MarkdownIO()
        self.store = EKEventStore()
        self.remindersBridge = RemindersBridge(
            store: store, listName: config.gtd.remindersList
        )
        self.taskIndex = taskIndex
        self.taskDatabase = taskDatabase
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
    /// non-canonical markdown tasks are removed). All downstream steps (indices, push to Reminders,
    /// pull to markdown) use these deduplicated lists so we never push or pull duplicates.
    public func sync() async throws -> SyncReport {
        var report = SyncReport()
        var importedInboxSignatures: [ReminderContentSignature: String] = [:]

        try? FileManager.default.createDirectory(atPath: taskFilesRoot, withIntermediateDirectories: true)

        try await remindersBridge.requestAccess()

        _ = try remindersBridge.findOrCreateList(context: nil)
        let forgeLists = remindersBridge.allForgeListCalendars()

        // Ensure the project task file index is populated before we scan for tasks. This avoids
        // paying the cost of a full recursive directory walk on every sync run.
        try? taskIndex.refreshIfNeeded(config: config, forgeDir: forgeDir)

        // Lint and auto-fix task markdown files before collecting tasks so that
        // IDs, headings, spacing, inbox/completed placement, and titles are normalised.
        let areaFiles = scanAreaFiles()
        let projectTaskFiles = findAllProjectTaskFiles()

        if options.enableLinting {
            let linter = TaskFileLinter()
            var lintPaths = Set<String>()

            // All markdown files in the task files root (Forge/tasks/*.md), including inbox and someday-maybe.
            let paths = ForgePaths(forgeDir: forgeDir)
            let fm = FileManager.default
            if let entries = try? fm.contentsOfDirectory(atPath: paths.taskFilesRoot) {
                for entry in entries where entry.hasSuffix(".md") {
                    // Skip generated summaries such as due.md.
                    if entry == "due.md" { continue }
                    let fullPath = (paths.taskFilesRoot as NSString).appendingPathComponent(entry)
                    lintPaths.insert(fullPath)
                }
            }

            // All project TASKS.md discovered under project_roots.
            lintPaths.formUnion(projectTaskFiles.map(\.path))

            for path in lintPaths {
                _ = try? linter.fix(path: path)
            }
        }

        let sourced = try await collectAllTasks(areaFiles: areaFiles)
        let allTasks = sourced.map(\.task)

        let reminders = try await remindersBridge.fetchReminders(from: forgeLists)

        let tasksByID = Dictionary(allTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sourceByID = Dictionary(sourced.map { ($0.task.id, $0) }, uniquingKeysWith: { first, _ in first })

        let taskChangeState = try computeTaskChangeState(sourced: sourced)
        let taskChangedAtByID = taskChangeState.changedAtByID
        let taskChangedSinceLastSync = taskChangeState.changedSinceLastSync

        var remindersAfterDedup = reminders
        remindersAfterDedup = try deduplicateRemindersByForgeID(
            remindersAfterDedup, sourceByID: sourceByID, report: &report
        )
        remindersAfterDedup = try deduplicateRemindersByContent(
            remindersAfterDedup, tasksByID: tasksByID, sourceByID: sourceByID, report: &report
        )

        var remindersByID = buildReminderIndex(remindersAfterDedup)
        var remindersWithoutForgeIDBySignature = buildUnlinkedReminderIndex(remindersAfterDedup)
        var remindersWithoutForgeIDByLooseSignature = buildUnlinkedReminderLooseIndex(remindersAfterDedup)

        // When the same task ID appears more than once in markdown, sync only one to avoid duplicate reminders.
        // Prefer a completed variant when any duplicate is completed, so markdown completion propagates to Reminders.
        var orderedIDs: [String] = []
        var preferredByID: [String: SourcedTask] = [:]
        for st in sourced {
            let id = st.task.id
            if preferredByID[id] == nil {
                orderedIDs.append(id)
                preferredByID[id] = st
                continue
            }
            if let existing = preferredByID[id],
               !existing.task.isCompleted,
               st.task.isCompleted
            {
                preferredByID[id] = st
            }
        }

        for id in orderedIDs {
            guard let st = preferredByID[id] else { continue }
            let list = try remindersBridge.findOrCreateList(context: st.task.context)
            syncTaskToReminders(
                task: st.task,
                taskChangedAt: taskChangedAtByID[st.task.id] ?? .distantPast,
                taskChangedSinceLastSync: taskChangedSinceLastSync.contains(st.task.id),
                tags: st.areaTags,
                remindersByID: &remindersByID,
                remindersWithoutForgeIDBySignature: &remindersWithoutForgeIDBySignature,
                remindersWithoutForgeIDByLooseSignature: &remindersWithoutForgeIDByLooseSignature,
                list: list, report: &report
            )
        }

        try syncRemindersToMarkdown(
            reminders: remindersAfterDedup, tasksByID: tasksByID,
            sourceByID: sourceByID, report: &report,
            importedInboxSignatures: &importedInboxSignatures,
            taskChangedAtByID: taskChangedAtByID,
            taskChangedSinceLastSync: taskChangedSinceLastSync
        )

        if options.enableFinderTags {
            await applyFinderTags(sourced: sourced, areaFiles: areaFiles)
        }

        // Refresh the read-only due summary markdown with the default 7-day horizon, including areas.
        if options.enableDueSummary {
            await refreshDueMarkdownSummary()
        }

        if options.enableRollups, !config.projectAreas.isEmpty {
            let rollup = RollupGenerator(config: config, forgeDir: forgeDir, taskFilesRoot: taskFilesRoot)
            if let rollupReport = try? rollup.generateAll() {
                report.rollupAreas = rollupReport.areasUpdated
                report.rollupTasks = rollupReport.tasksLinked
            }
        }

        try remindersBridge.commit()

        return report
    }

    /// Regenerate the read-only due markdown summary (due.md) in the task files root.
    ///
    /// Uses a fixed 7-day horizon and includes both project and area tasks so the summary always
    /// reflects the latest synced state.
    private func refreshDueMarkdownSummary() async {
        let horizonDays = 7
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let horizon = calendar.date(byAdding: .day, value: horizonDays, to: today) else { return }

        let updatedAreaFiles = scanAreaFiles()
        guard let updatedSourced = try? await collectAllTasks(areaFiles: updatedAreaFiles) else { return }

        var overdueItems: [DueSummaryGenerator.Item] = []
        var dueTodayItems: [DueSummaryGenerator.Item] = []
        var upcomingItems: [DueSummaryGenerator.Item] = []

        for st in updatedSourced {
            let task = st.task
            guard !task.isCompleted, let due = task.dueDate else { continue }

            let fileURL = URL(fileURLWithPath: st.filePath)
            let label: String
            if st.isAreaTask {
                label = fileURL.deletingPathExtension().lastPathComponent.capitalized
            } else {
                label = fileURL.deletingLastPathComponent().lastPathComponent
            }

            let item = DueSummaryGenerator.Item(task: task, label: label, sourcePath: st.filePath)

            if task.isOverdue {
                overdueItems.append(item)
            } else if task.isDueToday {
                dueTodayItems.append(item)
            } else if due <= horizon {
                upcomingItems.append(item)
            }
        }

        overdueItems.sort { ($0.task.dueDate ?? .distantPast) < ($1.task.dueDate ?? .distantPast) }
        dueTodayItems.sort { $0.task.text.lowercased() < $1.task.text.lowercased() }
        upcomingItems.sort { ($0.task.dueDate ?? .distantFuture) < ($1.task.dueDate ?? .distantFuture) }

        let generator = DueSummaryGenerator()
        generator.writeMarkdownSummary(
            overdueTasks: overdueItems,
            dueTodayTasks: dueTodayItems,
            upcomingTasks: upcomingItems,
            days: horizonDays,
            taskFilesRoot: taskFilesRoot
        )
    }

    // MARK: - Collect Tasks

    /// Recursively find all TASKS.md files under each project root (not only direct children).
    /// This ensures nested project folders are included regardless of Finder tags.
    private func findAllProjectTaskFiles() -> [(path: String, projectName: String)] {
        return taskIndex.projectTaskFiles(for: config)
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

        // Include inbox.md so completion in markdown can be pushed back to Reminders.
        // Inbox tasks are first-class tasks and can be created either in markdown or imported from Reminders.
        let inboxPath = (taskFilesRoot as NSString).appendingPathComponent("inbox.md")
        if FileManager.default.fileExists(atPath: inboxPath) {
            let inboxTasks = (try? markdownIO.parseTasksAtPathAndPersistIds(at: inboxPath, projectName: "Inbox")) ?? []
            for task in inboxTasks {
                result.append(SourcedTask(
                    task: task, filePath: inboxPath,
                    areaTags: config.workspaceTags, isAreaTask: true
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
        let excluded: Set<String> = ["config.yaml", "someday-maybe.md", "inbox.md", "due.md"]
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

    /// Looser signature used only for re-linking old reminders that are missing forge metadata.
    /// Ignores list identifier so we can link reminders created in the wrong Forge list and then move them.
    private struct ReminderLooseSignature: Hashable {
        let normalisedTitle: String
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

    private func buildUnlinkedReminderIndex(_ reminders: [EKReminder]) -> [ReminderContentSignature: EKReminder] {
        var index: [ReminderContentSignature: EKReminder] = [:]
        for reminder in reminders {
            guard remindersBridge.extractForgeID(from: reminder) == nil else { continue }
            index[reminderContentSignature(reminder)] = reminder
        }
        return index
    }

    private func buildUnlinkedReminderLooseIndex(_ reminders: [EKReminder]) -> [ReminderLooseSignature: [EKReminder]] {
        var index: [ReminderLooseSignature: [EKReminder]] = [:]
        for reminder in reminders {
            guard remindersBridge.extractForgeID(from: reminder) == nil else { continue }
            let sig = ReminderLooseSignature(
                normalisedTitle: (reminder.title ?? "")
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "  ", with: " "),
                dueDay: reminder.dueDateComponents.flatMap { comp in
                    guard let d = Calendar.current.date(from: comp) else { return nil }
                    return Self.dayString(d)
                },
                deferDay: reminder.startDateComponents.flatMap { comp in
                    guard let d = Calendar.current.date(from: comp) else { return nil }
                    return Self.dayString(d)
                },
                recurrenceString: reminder.recurrenceRules?.first.map { "\($0.frequency.rawValue)-\($0.interval)" } ?? ""
            )
            index[sig, default: []].append(reminder)
        }
        return index
    }

    private func taskContentSignature(_ task: ForgeTask, listIdentifier: String) -> ReminderContentSignature {
        let title = task.text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "  ", with: " ")
        let dueDay: String? = task.dueDate.map { Self.dayString($0) }
        let deferDay: String? = task.deferDate.map { Self.dayString($0) }
        // Only match non-recurring reminders by content. Recurring matching requires translating
        // Forge repeat rules to EventKit recurrence strings, which we intentionally avoid here.
        return ReminderContentSignature(
            normalisedTitle: title,
            listIdentifier: listIdentifier,
            dueDay: dueDay,
            deferDay: deferDay,
            recurrenceString: ""
        )
    }

    private func taskLooseSignature(_ task: ForgeTask) -> ReminderLooseSignature {
        let title = task.text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "  ", with: " ")
        return ReminderLooseSignature(
            normalisedTitle: title,
            dueDay: task.dueDate.map { Self.dayString($0) },
            deferDay: task.deferDate.map { Self.dayString($0) },
            recurrenceString: ""
        )
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


    // MARK: - Markdown -> Reminders

    private func syncTaskToReminders(
        task: ForgeTask,
        taskChangedAt: Date,
        taskChangedSinceLastSync: Bool,
        tags: [String],
        remindersByID: inout [String: EKReminder],
        remindersWithoutForgeIDBySignature: inout [ReminderContentSignature: EKReminder],
        remindersWithoutForgeIDByLooseSignature: inout [ReminderLooseSignature: [EKReminder]],
        list: EKCalendar,
        report: inout SyncReport
    ) {
        let policy = config.dueConflictPolicy
        let reminder: EKReminder? = {
            if let r = remindersByID[task.id] { return r }
            // Try to re-link older/unlinked reminders by content in the expected list.
            let sig = taskContentSignature(task, listIdentifier: list.calendarIdentifier)
            if let candidate = remindersWithoutForgeIDBySignature[sig] {
                // Attach forge metadata so subsequent syncs are ID-based.
                let projectName = task.projectName ?? "Inbox"
                candidate.notes = remindersBridge.formatNotes(project: projectName, taskID: task.id, tags: tags)
                try? store.save(candidate, commit: false)
                remindersByID[task.id] = candidate
                remindersWithoutForgeIDBySignature.removeValue(forKey: sig)
                remindersWithoutForgeIDByLooseSignature.removeValue(forKey: taskLooseSignature(task))
                report.remindersLinkedByContent += 1
                return candidate
            }

            // Fallback: ignore list identifier. Only link if the match is unambiguous.
            let loose = taskLooseSignature(task)
            guard let group = remindersWithoutForgeIDByLooseSignature[loose], group.count == 1 else { return nil }
            let only = group[0]
            let projectName = task.projectName ?? "Inbox"
            only.notes = remindersBridge.formatNotes(project: projectName, taskID: task.id, tags: tags)
            try? store.save(only, commit: false)
            remindersByID[task.id] = only
            remindersWithoutForgeIDByLooseSignature.removeValue(forKey: loose)
            remindersWithoutForgeIDBySignature.removeValue(forKey: reminderContentSignature(only))
            report.remindersLinkedByContent += 1
            return only
        }()

        if let reminder {
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
                let reminderModifiedAt = reminder.lastModifiedDate ?? .distantPast
                let reminderDue = parseReminderDue(reminder)

                let dueAlreadyMatches: Bool = {
                    guard let markdownDue = task.dueDate else { return reminderDue == nil }
                    guard let reminderDue else { return false }
                    if reminderDue.hasTime != task.dueHasTime { return false }
                    if task.dueHasTime {
                        return reminderDue.date == markdownDue
                    }
                    return Calendar.current.startOfDay(for: reminderDue.date) == Calendar.current.startOfDay(for: markdownDue)
                }()

                let alarmMatchesTimedDue: Bool = {
                    guard task.dueHasTime, let markdownDue = task.dueDate else { return true }
                    let alarms = reminder.alarms ?? []
                    guard alarms.count == 1, let abs = alarms[0].absoluteDate else { return false }
                    return abs == markdownDue
                }()

                let shouldUpdateReminderDue: Bool = {
                    // If markdown has no due date, never overwrite a reminder due date here.
                    guard task.dueDate != nil else { return false }

                    // If reminder has no due date, always seed it from markdown.
                    if reminderDue == nil { return true }

                    switch policy {
                    case .reminders:
                        // Even in reminders-preferred mode, if due matches but the alarm doesn't,
                        // repair the alarm so Reminders.app displays the expected time.
                        return dueAlreadyMatches && !alarmMatchesTimedDue
                    case .markdown:
                        return true
                    case .newest:
                        // If we detected the markdown task changed since the last sync, prefer markdown.
                        if taskChangedSinceLastSync { return true }
                        // If due matches but the alarm doesn't, repair it regardless of timestamps.
                        if dueAlreadyMatches && !alarmMatchesTimedDue { return true }
                        return taskChangedAt > reminderModifiedAt
                    }
                }()

                if shouldUpdateReminderDue {
                    do {
                        try remindersBridge.updateDueDate(reminder, to: task.dueDate, hasTime: task.dueHasTime)
                        report.remindersDueUpdated += 1
                        report.remindersDueUpdatedTaskIDs.append(task.id)
                        let list = reminder.calendar?.title ?? "(unknown list)"
                        let title = reminder.title ?? ""
                        let taskDueDesc: String = {
                            guard let d = task.dueDate else { return "nil" }
                            let cal = Calendar.current
                            let y = cal.component(.year, from: d)
                            let m = cal.component(.month, from: d)
                            let day = cal.component(.day, from: d)
                            let h = cal.component(.hour, from: d)
                            let min = cal.component(.minute, from: d)
                            return String(format: "%04d-%02d-%02d %02d:%02d (hasTime=%@)", y, m, day, h, min, task.dueHasTime ? "true" : "false")
                        }()
                        let dueDesc: String = {
                            guard let comp = reminder.dueDateComponents else { return "nil" }
                            let y = comp.year.map(String.init) ?? "?"
                            let m = comp.month.map(String.init) ?? "?"
                            let d = comp.day.map(String.init) ?? "?"
                            let h = comp.hour.map(String.init) ?? "nil"
                            let min = comp.minute.map(String.init) ?? "nil"
                            return "\(y)-\(m)-\(d) \(h):\(min)"
                        }()
                        report.remindersDueUpdatedDetails.append("\(task.id) → [\(list)] \(title) taskDue=\(taskDueDesc) reminderDue=\(dueDesc)")
                    } catch {
                        report.errors.append("Failed to update reminder due date for \(task.id): \(error)")
                    }
                }
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

    // MARK: - Reminders -> Markdown

    private func syncRemindersToMarkdown(
        reminders: [EKReminder],
        tasksByID: [String: ForgeTask],
        sourceByID: [String: SourcedTask],
        report: inout SyncReport,
        importedInboxSignatures: inout [ReminderContentSignature: String],
        taskChangedAtByID: [String: Date],
        taskChangedSinceLastSync: Set<String>
    ) throws {
        for reminder in reminders {
            if let ids = remindersBridge.extractForgeID(from: reminder) {
                guard let task = tasksByID[ids.taskID] else { continue }
                guard let source = sourceByID[ids.taskID] else { continue }

                if reminder.isCompleted && !task.isCompleted {
                    if try markdownIO.completeTask(withID: ids.taskID, inFileAt: source.filePath) {
                        report.tasksCompleted += 1
                    }
                    continue
                }

                if !reminder.isCompleted {
                    if let reminderDue = parseReminderDue(reminder) {
                        let differs: Bool = {
                            guard let existing = task.dueDate else { return true }
                            if reminderDue.hasTime != task.dueHasTime { return true }
                            if reminderDue.hasTime { return existing != reminderDue.date }
                            return Calendar.current.startOfDay(for: existing) != Calendar.current.startOfDay(for: reminderDue.date)
                        }()

                        if differs {
                            let shouldUpdateMarkdownDue: Bool = {
                                switch config.dueConflictPolicy {
                                case .reminders:
                                    return true
                                case .markdown:
                                    return false
                                case .newest:
                                    // If markdown changed since last sync, do not overwrite it from Reminders.
                                    if taskChangedSinceLastSync.contains(ids.taskID) { return false }
                                    let markdownModifiedAt: Date = taskChangedAtByID[ids.taskID] ?? .distantPast
                                    let reminderModifiedAt = reminder.lastModifiedDate ?? .distantPast
                                    return reminderModifiedAt >= markdownModifiedAt
                                }
                            }()

                            if shouldUpdateMarkdownDue {
                                if try markdownIO.updateTaskDueDate(
                                    withID: ids.taskID,
                                    to: reminderDue.date,
                                    hasTime: reminderDue.hasTime,
                                    inFileAt: source.filePath
                                ) {
                                    report.tasksUpdated += 1
                                }
                            }
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
                let incomingDue: (date: Date?, hasTime: Bool) = {
                    guard let comp = reminder.dueDateComponents,
                          let d = Calendar.current.date(from: comp) else { return (nil, false) }
                    let hasTime = (comp.hour != nil || comp.minute != nil)
                    return (d, hasTime)
                }()

                let task = ForgeTask(
                    id: ForgeTask.newID(),
                    text: reminder.title ?? "Untitled",
                    section: .nextActions,
                    dueDate: incomingDue.date,
                    dueHasTime: incomingDue.hasTime,
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

    // Calendar sync removed.
}
