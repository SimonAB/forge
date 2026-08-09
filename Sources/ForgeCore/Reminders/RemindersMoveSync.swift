import Foundation

/// Finder ↔ Reminders sentinel mirror used by `forge move`, board drag, and Refresh.
public enum RemindersMoveSync {
    public enum Outcome: Sendable, Equatable {
        case disabled
        case skipped(String)
        case synced(listTitle: String, column: String)
    }

    public struct PullOutcome: Sendable, Equatable {
        public let updatedFolders: [String]
        public let createdLists: [String]
        public let paintedColours: [String]
        public let paintedPriorities: [String]
        public let errors: [String]

        public init(
            updatedFolders: [String],
            createdLists: [String] = [],
            paintedColours: [String] = [],
            paintedPriorities: [String] = [],
            errors: [String]
        ) {
            self.updatedFolders = updatedFolders
            self.createdLists = createdLists
            self.paintedColours = paintedColours
            self.paintedPriorities = paintedPriorities
            self.errors = errors
        }
    }

    /// Paint the matched list’s colour from the Finder column (Reminders enabled; no sentinel required).
    public static func paintListColour(
        config: ForgeConfig,
        project: Project,
        column: String,
        inventory: RemindersInventory,
        writer: any RemindersMutating,
        force: Bool = false
    ) async -> Outcome {
        let rem = config.reminders
        guard rem.enabled else { return .disabled }
        guard let colourIndex = config.board.colourIndex(forColumn: column) else {
            return .skipped("no colour index for column \(column)")
        }

        let report = RemindersAlignment.doctor(
            projects: [project],
            inventory: inventory,
            config: config
        )
        if RemindersAlignment.shouldBlockSyncOnMove(
            folderName: project.name,
            report: report,
            force: force
        ) {
            return .skipped("doctor drift for \(project.name)")
        }

        let lists = inventory.lists.filter {
            $0.matchedProject?.lowercased() == project.name.lowercased()
        }
        guard lists.count == 1, let list = lists.first else {
            return .skipped("no unique Reminders list for \(project.name)")
        }

        do {
            try await writer.updateListColour(listId: list.id, colourIndex: colourIndex)
            return .synced(listTitle: list.title, column: column)
        } catch {
            return .skipped(error.localizedDescription)
        }
    }

    /// Paint list colour, then update the sentinel when `sync_on_move` is on.
    /// Sentinel priority follows Finder URGENT whenever Reminders is enabled.
    public static func afterFinderColumnChange(
        config: ForgeConfig,
        project: Project,
        column: String,
        inventory: RemindersInventory,
        writer: any RemindersMutating,
        force: Bool = false
    ) async -> (colour: Outcome, sentinel: Outcome, priority: Outcome) {
        guard config.reminders.enabled else {
            return (.disabled, .disabled, .disabled)
        }
        let colour = await paintListColour(
            config: config,
            project: project,
            column: column,
            inventory: inventory,
            writer: writer,
            force: force
        )
        let sentinel = await mirrorFinderColumn(
            config: config,
            project: project,
            column: column,
            inventory: inventory,
            writer: writer,
            force: force
        )
        let priority = await paintSentinelPriority(
            config: config,
            project: project,
            inventory: inventory,
            writer: writer,
            force: force
        )
        return (colour, sentinel, priority)
    }

    /// Set the matched list’s unique sentinel priority from Finder URGENT (Reminders enabled).
    /// Does not create a sentinel.
    public static func paintSentinelPriority(
        config: ForgeConfig,
        project: Project,
        inventory: RemindersInventory,
        writer: any RemindersMutating,
        force: Bool = false
    ) async -> Outcome {
        let rem = config.reminders
        guard rem.enabled else { return .disabled }

        let report = RemindersAlignment.doctor(
            projects: [project],
            inventory: inventory,
            config: config
        )
        if RemindersAlignment.shouldBlockSyncOnMove(
            folderName: project.name,
            report: report,
            force: force
        ) {
            return .skipped("doctor drift for \(project.name)")
        }

        let lists = inventory.lists.filter {
            $0.matchedProject?.lowercased() == project.name.lowercased()
        }
        guard lists.count == 1, let list = lists.first else {
            return .skipped("no unique Reminders list for \(project.name)")
        }

        let prefix = rem.sentinelPrefix
        let sentinels = inventory.reminders.filter {
            $0.listId == list.id
                && RemindersSentinel.isSentinel(title: $0.title, notes: $0.notes, prefix: prefix)
        }
        guard sentinels.count == 1, let sentinel = sentinels.first else {
            if sentinels.isEmpty {
                return .skipped("no unique sentinel on \(list.title)")
            }
            return .skipped("multiple sentinels on \(list.title)")
        }

        let isUrgent = KanbanRadar.isUrgent(metaTags: project.metaTags)
        let priority = RemindersSentinel.priority(isUrgent: isUrgent)
        do {
            try await writer.updateReminderPriority(reminderId: sentinel.id, priority: priority)
            return .synced(listTitle: list.title, column: isUrgent ? "URGENT" : "clear")
        } catch {
            return .skipped(error.localizedDescription)
        }
    }

    /// Update or create the sentinel after a Finder column change.
    public static func mirrorFinderColumn(
        config: ForgeConfig,
        project: Project,
        column: String,
        inventory: RemindersInventory,
        writer: any RemindersMutating,
        force: Bool = false
    ) async -> Outcome {
        let rem = config.reminders
        guard rem.enabled, rem.syncOnMove else { return .disabled }

        let report = RemindersAlignment.doctor(
            projects: [project],
            inventory: inventory,
            config: config
        )
        if RemindersAlignment.shouldBlockSyncOnMove(
            folderName: project.name,
            report: report,
            force: force
        ) {
            return .skipped("doctor drift for \(project.name)")
        }

        let lists = inventory.lists.filter {
            $0.matchedProject?.lowercased() == project.name.lowercased()
        }
        guard lists.count == 1, let list = lists.first else {
            return .skipped("no unique Reminders list for \(project.name)")
        }

        let prefix = rem.sentinelPrefix
        let sentinels = inventory.reminders.filter {
            $0.listId == list.id
                && RemindersSentinel.isSentinel(title: $0.title, notes: $0.notes, prefix: prefix)
        }

        let priority = RemindersSentinel.priority(
            isUrgent: KanbanRadar.isUrgent(metaTags: project.metaTags)
        )

        do {
            if sentinels.isEmpty {
                let reminderId = try await writer.saveSentinel(
                    listId: list.id,
                    column: column,
                    prefix: prefix
                )
                try await writer.updateReminderPriority(reminderId: reminderId, priority: priority)
            } else if let sentinel = sentinels.first, sentinels.count == 1 {
                let current = RemindersSentinel.parse(
                    title: sentinel.title,
                    notes: sentinel.notes,
                    prefix: prefix,
                    knownColumns: config.board.columns.map(\.name)
                )
                if current != column || sentinel.isCompleted {
                    try await writer.updateSentinel(
                        reminderId: sentinel.id,
                        column: column,
                        prefix: prefix
                    )
                }
                try await writer.updateReminderPriority(reminderId: sentinel.id, priority: priority)
            } else if force, let sentinel = sentinels.first {
                try await writer.updateSentinel(
                    reminderId: sentinel.id,
                    column: column,
                    prefix: prefix
                )
                try await writer.updateReminderPriority(reminderId: sentinel.id, priority: priority)
            } else {
                return .skipped("multiple sentinels on \(list.title)")
            }
            return .synced(listTitle: list.title, column: column)
        } catch {
            return .skipped(error.localizedDescription)
        }
    }

    /// Pull unique sentinels onto Finder when the step is a single column.
    ///
    /// Folders in `skipFolderNames` (already updated by OmniFocus this refresh) are ignored.
    public static func applySentinelsToFinder(
        config: ForgeConfig,
        projects: [Project],
        inventory: RemindersInventory,
        skipFolderNames: Set<String> = [],
        setColumn: (Project, String) throws -> Void
    ) -> PullOutcome {
        let rem = config.reminders
        guard rem.enabled, rem.syncFromReminders else {
            return PullOutcome(updatedFolders: [], errors: [])
        }

        let knownColumns = config.board.columns.map(\.name)
        let prefix = rem.sentinelPrefix
        var updated: [String] = []
        var errors: [String] = []

        for project in projects {
            if skipFolderNames.contains(project.name) { continue }
            let lists = inventory.lists.filter {
                $0.matchedProject?.lowercased() == project.name.lowercased()
            }
            guard lists.count == 1, let list = lists.first else { continue }
            let sentinels = inventory.reminders.filter {
                $0.listId == list.id
                    && RemindersSentinel.isSentinel(title: $0.title, notes: $0.notes, prefix: prefix)
            }
            guard sentinels.count == 1, let sentinel = sentinels.first, !sentinel.isCompleted else {
                continue
            }
            guard let column = RemindersSentinel.parse(
                title: sentinel.title,
                notes: sentinel.notes,
                prefix: prefix,
                knownColumns: knownColumns
            ) else { continue }
            guard column != project.column else { continue }
            guard isSingleColumnStep(from: project.column, to: column, knownColumns: knownColumns) else {
                errors.append("\(project.name): sentinel \(column) is more than one column from \(project.column ?? "Untagged")")
                continue
            }
            do {
                try setColumn(project, column)
                updated.append(project.name)
            } catch {
                errors.append("\(project.name): \(error.localizedDescription)")
            }
        }

        return PullOutcome(updatedFolders: updated, errors: errors)
    }

    /// Adjacent main-flow step, Paused side-column, or untagged → any configured column.
    public static func isSingleColumnStep(
        from: String?,
        to: String,
        knownColumns: [String] = KanbanTransitionPolicy.mainFlowOrder
    ) -> Bool {
        if from == to { return true }
        if from == nil { return knownColumns.contains(to) || to == "Paused" }
        if from == "Paused" || to == "Paused" { return true }

        let flow = KanbanTransitionPolicy.mainFlowOrder
        guard let fromIndex = flow.firstIndex(of: from!),
              let toIndex = flow.firstIndex(of: to) else {
            return knownColumns.contains(to)
        }
        return abs(toIndex - fromIndex) == 1
    }

    /// Refresh snapshot, optionally pull sentinels onto Finder, then paint list colour and URGENT priority.
    /// Does not create lists or sentinels.
    ///
    /// Call after OmniFocus Refresh so `skipFolderNames` can exclude folders OF already updated.
    public static func refreshAndPull(
        config: ForgeConfig,
        forgeDir: String,
        projects: [Project],
        skipFolderNames: Set<String> = [],
        writerName: String,
        pullSentinels: Bool? = nil,
        setColumn: @Sendable (Project, String) throws -> Void
    ) async throws -> PullOutcome {
        guard config.reminders.enabled else {
            return PullOutcome(updatedFolders: [], errors: [])
        }
        let service = RemindersService(config: config)
        let inventory = try await service.refreshSnapshot(
            forgeDir: forgeDir,
            projectNames: projects.map(\.name),
            writer: writerName
        )
        return await applyRefreshAppearance(
            config: config,
            projects: projects,
            inventory: inventory,
            writer: RemindersWriter(),
            skipFolderNames: skipFolderNames,
            pullSentinels: pullSentinels ?? config.reminders.syncFromReminders,
            setColumn: setColumn
        )
    }

    /// Sentinel → Finder (optional), then Finder column → list colour and URGENT → sentinel priority.
    /// Does not create lists or sentinels.
    public static func applyRefreshAppearance(
        config: ForgeConfig,
        projects: [Project],
        inventory: RemindersInventory,
        writer: any RemindersMutating,
        skipFolderNames: Set<String> = [],
        force: Bool = false,
        pullSentinels: Bool,
        setColumn: (Project, String) throws -> Void
    ) async -> PullOutcome {
        guard config.reminders.enabled else {
            return PullOutcome(updatedFolders: [], errors: [])
        }

        var errors: [String] = []
        var updated: [String] = []
        var columnByFolder: [String: String] = [:]

        if pullSentinels {
            let pull = applySentinelsToFinder(
                config: config,
                projects: projects,
                inventory: inventory,
                skipFolderNames: skipFolderNames,
                setColumn: { project, column in
                    try setColumn(project, column)
                    columnByFolder[project.name] = column
                }
            )
            updated = pull.updatedFolders
            errors.append(contentsOf: pull.errors)
        }

        let paintProjects = projects.map { project in
            guard let column = columnByFolder[project.name] else { return project }
            return Project(
                name: project.name,
                path: project.path,
                tags: project.tags,
                workflowTag: project.workflowTag,
                column: column,
                metaTags: project.metaTags,
                assignees: project.assignees
            )
        }

        let colours = await paintAllMatchedListColours(
            config: config,
            projects: paintProjects,
            inventory: inventory,
            writer: writer,
            force: force
        )
        let priorities = await paintAllMatchedSentinelPriorities(
            config: config,
            projects: paintProjects,
            inventory: inventory,
            writer: writer,
            force: force
        )

        return PullOutcome(
            updatedFolders: updated,
            createdLists: [],
            paintedColours: colours.painted,
            paintedPriorities: priorities.painted,
            errors: errors
        )
    }

    /// Paint every uniquely matched list from its Finder column. Does not create lists or sentinels.
    public static func paintAllMatchedListColours(
        config: ForgeConfig,
        projects: [Project],
        inventory: RemindersInventory,
        writer: any RemindersMutating,
        force: Bool = false
    ) async -> (painted: [String], skipped: [String]) {
        var painted: [String] = []
        var skipped: [String] = []
        guard config.reminders.enabled else {
            return ([], ["reminders.enabled is false"])
        }
        for project in projects {
            guard let column = project.column else {
                skipped.append("\(project.name): no Finder column")
                continue
            }
            switch await paintListColour(
                config: config,
                project: project,
                column: column,
                inventory: inventory,
                writer: writer,
                force: force
            ) {
            case .disabled:
                skipped.append("\(project.name): reminders disabled")
            case .skipped(let reason):
                skipped.append("\(project.name): \(reason)")
            case .synced(let listTitle, let paintedColumn):
                painted.append("\(listTitle) → \(paintedColumn)")
            }
        }
        return (painted, skipped)
    }

    /// Set sentinel priority from Finder URGENT on every uniquely matched list that already has a sentinel.
    public static func paintAllMatchedSentinelPriorities(
        config: ForgeConfig,
        projects: [Project],
        inventory: RemindersInventory,
        writer: any RemindersMutating,
        force: Bool = false
    ) async -> (painted: [String], skipped: [String]) {
        var painted: [String] = []
        var skipped: [String] = []
        guard config.reminders.enabled else {
            return ([], ["reminders.enabled is false"])
        }
        for project in projects {
            switch await paintSentinelPriority(
                config: config,
                project: project,
                inventory: inventory,
                writer: writer,
                force: force
            ) {
            case .disabled:
                skipped.append("\(project.name): reminders disabled")
            case .skipped(let reason):
                skipped.append("\(project.name): \(reason)")
            case .synced(let listTitle, let label):
                painted.append("\(listTitle) → \(label)")
            }
        }
        return (painted, skipped)
    }
}
