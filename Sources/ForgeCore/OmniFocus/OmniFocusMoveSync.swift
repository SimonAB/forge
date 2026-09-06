import Foundation

/// Shared Finder ↔ OmniFocus column mirror used by `forge move` and the board apps.
public enum OmniFocusMoveSync {

    public enum Outcome: Sendable, Equatable {
        case disabled
        case skipped(String)
        case synced(
            updatedCount: Int,
            alias: String?,
            missingAlias: [String],
            projectStatusNote: String?
        )
    }

    /// Result of pulling OmniFocus columns onto Finder workflow tags.
    public struct PullOutcome: Sendable, Equatable {
        public let updatedFolders: [String]
        public let errors: [String]

        public init(updatedFolders: [String], errors: [String]) {
            self.updatedFolders = updatedFolders
            self.errors = errors
        }
    }

    /// Resolved OmniFocus column for a project's linked tasks (multi-tag + majority).
    public static func resolvedOmniFocusColumn(
        tasks: [OmniFocusTaskRecord],
        boardOrder: [String] = KanbanTransitionPolicy.mainFlowOrder,
        preferFinder: String? = nil
    ) -> String? {
        OmniFocusColumnResolution.resolveProject(
            tasks: tasks,
            boardOrder: boardOrder,
            preferFinder: preferFinder
        )
    }

    /// Resolved column for an OF → Finder pull (prefers tags that differ from Finder).
    public static func resolvedOmniFocusColumnForPull(
        tasks: [OmniFocusTaskRecord],
        finderColumn: String?,
        boardOrder: [String] = KanbanTransitionPolicy.mainFlowOrder
    ) -> String? {
        OmniFocusColumnResolution.resolveProjectForPull(
            tasks: tasks,
            finderColumn: finderColumn,
            boardOrder: boardOrder
        )
    }

    /// True when every linked task resolves to the same column (after multi-tag policy).
    public static func unanimousOmniFocusColumn(tasks: [OmniFocusTaskRecord]) -> String? {
        let columns = Set(tasks.compactMap(\.forgeColumn))
        guard columns.count == 1 else { return nil }
        return columns.first
    }

    /// Set the Finder workflow tag for a project directory to `column`.
    ///
    /// When `forgeDir` and `folderName` are provided and a `Completed…` meta tag is configured,
    /// records or clears the ship-date cache and strips Completed (and legacy Archived) on leave-Shipped.
    /// When `nexus.sidecar_enabled` is true, also writes `<project>/.forge/kanban.toml`.
    public static func setFinderWorkflowColumn(
        path: String,
        column: String,
        config: ForgeConfig,
        tagStore: FinderTagStore = FinderTagStore(),
        forgeDir: String? = nil,
        folderName: String? = nil,
        previousColumn: String? = nil,
        source: String = KanbanNexus.Source.forgeMove
    ) throws {
        try KanbanNexus.setWorkflowColumn(
            path: path,
            column: column,
            config: config,
            tagStore: tagStore,
            forgeDir: forgeDir,
            folderName: folderName,
            previousColumn: previousColumn,
            source: source
        )
    }

    /// Mirror a Finder workflow column onto linked OmniFocus tasks (flat aliases or nested root).
    public static func mirrorFinderColumn(
        config: ForgeConfig,
        forgeDir: String,
        projects: [Project],
        project: Project,
        column: String,
        force: Bool = false,
        service: OmniFocusService? = nil
    ) -> Outcome {
        let of = config.omnifocus
        guard of.enabled, of.syncOnMove else { return .disabled }

        let service = service ?? OmniFocusService(config: config)
        let inventory: OmniFocusInventory
        do {
            if let snap = try service.loadEligibleSnapshot(forgeDir: forgeDir),
               snap.tasks.contains(where: { $0.projectFolderName == project.name }) {
                inventory = snap
            } else {
                inventory = try service.fetchInventory()
            }
        } catch {
            return .skipped(error.localizedDescription)
        }

        if !of.allowSyncWithDrift {
            let report = OmniFocusAlignment.doctor(
                projects: projects,
                inventory: inventory,
                config: config
            )
            if OmniFocusAlignment.shouldBlockSyncOnMove(
                folderName: project.name,
                report: report,
                force: force
            ) {
                return .skipped(
                    "\(project.name) has ambiguous OF links. Resolve with `forge omnifocus doctor`, or pass --force."
                )
            }
        }

        let taskIds = inventory.tasks.filter { $0.projectFolderName == project.name }.map(\.id)
        let previousColumn = project.column
        let leavingShipped = previousColumn == "Shipped" && column != "Shipped"
        let enteringShipped = previousColumn != "Shipped" && column == "Shipped"

        var projectStatusNote: String?

        do {
            // Reopen Done/Dropped before tagging so incomplete tasks are writable again.
            if leavingShipped, of.reopenOfProjectWhenLeavingShipped {
                let status = try service.applyOfProjectStatus(folderName: project.name, status: "Active")
                if status.updated {
                    projectStatusNote = "OF project \(status.projectName ?? project.name): \(status.before ?? "?") → Active"
                } else if status.reason == "no_matching_project" {
                    projectStatusNote = "OF project status: no matching project named \(project.name)"
                }
            }

            if taskIds.isEmpty {
                // Still allow project-status-only feedback when there are no linked tasks.
                if enteringShipped, of.completeOfProjectWhenEnteringShipped {
                    let status = try service.applyOfProjectStatus(folderName: project.name, status: "Done")
                    if status.updated {
                        projectStatusNote = "OF project \(status.projectName ?? project.name): \(status.before ?? "?") → Done"
                    } else if status.reason == "no_matching_project" {
                        projectStatusNote = "OF project status: no matching project named \(project.name)"
                    }
                }
                _ = try? service.refreshSnapshot(forgeDir: forgeDir)
                if projectStatusNote != nil {
                    return .synced(
                        updatedCount: 0,
                        alias: of.columnAlias(for: column),
                        missingAlias: [],
                        projectStatusNote: projectStatusNote
                    )
                }
                return .skipped("no linked tasks for \(project.name)")
            }

            let result = try service.applyForgeColumn(
                folderName: project.name,
                column: column,
                taskIds: taskIds
            )

            if enteringShipped, of.completeOfProjectWhenEnteringShipped {
                let status = try service.applyOfProjectStatus(folderName: project.name, status: "Done")
                if status.updated {
                    let note = "OF project \(status.projectName ?? project.name): \(status.before ?? "?") → Done"
                    projectStatusNote = projectStatusNote.map { "\($0); \(note)" } ?? note
                } else if status.reason == "no_matching_project", projectStatusNote == nil {
                    projectStatusNote = "OF project status: no matching project named \(project.name)"
                }
            }

            _ = try? service.refreshSnapshot(forgeDir: forgeDir)
            return .synced(
                updatedCount: result.updated.count,
                alias: of.columnAlias(for: column),
                missingAlias: result.missingAlias,
                projectStatusNote: projectStatusNote
            )
        } catch {
            return .skipped(error.localizedDescription)
        }
    }

    /// Pull unanimous OmniFocus columns onto Finder workflow tags where they disagree.
    public static func applyOmniFocusColumnsToFinder(
        config: ForgeConfig,
        forgeDir: String,
        projects: [Project],
        force: Bool = false,
        tagStore: FinderTagStore = FinderTagStore(),
        inventory: OmniFocusInventory? = nil
    ) throws -> PullOutcome {
        let of = config.omnifocus
        guard of.enabled, of.syncFromOmnifocus else {
            return PullOutcome(updatedFolders: [], errors: [])
        }

        let service = OmniFocusService(config: config)
        let inventory = try inventory ?? service.fetchInventory()
        let report = OmniFocusAlignment.doctor(
            projects: projects,
            inventory: inventory,
            config: config
        )
        var updated: [String] = []
        var errors: [String] = []

        for project in projects {
            let tasks = inventory.tasks.filter { $0.projectFolderName == project.name }
            guard !tasks.isEmpty else { continue }

            if OmniFocusAlignment.shouldBlockSyncOnMove(
                folderName: project.name,
                report: report,
                force: force
            ) {
                errors.append("\(project.name): ambiguous OF links")
                continue
            }

            // Prefer an OF tag that differs from Finder (user often stacks Watch without clearing Review).
            guard let ofColumn = resolvedOmniFocusColumnForPull(
                tasks: tasks,
                finderColumn: project.column,
                boardOrder: config.board.columns.map(\.name)
            ) else {
                if tasks.contains(where: { $0.forgeColumn != nil || !$0.forgeColumns.isEmpty }) {
                    errors.append("\(project.name): linked OF tasks disagree on column")
                }
                continue
            }
            guard ofColumn != project.column else { continue }
            guard config.board.columns.contains(where: { $0.name == ofColumn }) else {
                errors.append("\(project.name): OF column \(ofColumn) is not a board column")
                continue
            }

            // Do not re-force Shipped after the user left it (board / Finder override).
            if ofColumn == "Shipped",
               (try? ShippedArchiveStore.isCompletedShipSuppressed(
                   forgeDir: forgeDir,
                   folderName: project.name
               )) == true {
                continue
            }

            do {
                try setFinderWorkflowColumn(
                    path: project.path,
                    column: ofColumn,
                    config: config,
                    tagStore: tagStore,
                    forgeDir: forgeDir,
                    folderName: project.name,
                    previousColumn: project.column,
                    source: KanbanNexus.Source.ofRefresh
                )
                updated.append(project.name)
            } catch {
                errors.append("\(project.name): \(error.localizedDescription)")
            }
        }

        _ = try? service.refreshSnapshot(forgeDir: forgeDir)
        return PullOutcome(updatedFolders: updated, errors: errors)
    }

    /// Push Finder columns onto OF for every linked project whose column/alias disagrees.
    ///
    /// Used by the board Refresh action so a UI move that only updated Finder can catch up OmniFocus.
    public static func mirrorAllFinderColumns(
        config: ForgeConfig,
        forgeDir: String,
        projects: [Project],
        force: Bool = false
    ) throws -> (syncedFolders: Int, updatedTasks: Int, errors: [String]) {
        let of = config.omnifocus
        guard of.enabled, of.syncOnMove else { return (0, 0, []) }

        let service = OmniFocusService(config: config)
        let inventory = try service.fetchInventory()
        let report = OmniFocusAlignment.doctor(
            projects: projects,
            inventory: inventory,
            config: config
        )
        var updates: [OmniFocusService.ColumnUpdate] = []
        var errors: [String] = []

        for project in projects {
            guard let column = project.column else { continue }
            let tasks = inventory.tasks.filter { $0.projectFolderName == project.name }
            guard !tasks.isEmpty else { continue }

            if OmniFocusAlignment.shouldBlockSyncOnMove(
                folderName: project.name,
                report: report,
                force: force
            ) {
                errors.append("\(project.name): ambiguous OF links")
                continue
            }

            // Do not push Finder → OF when OF still has a clear opposing column.
            // Refresh pull is responsible for OF → Finder; overwriting OF here undoes the user's tag change.
            if let ofColumn = resolvedOmniFocusColumn(
                tasks: tasks,
                boardOrder: config.board.columns.map(\.name),
                preferFinder: nil
            ), ofColumn != column {
                continue
            }

            let needsColumn = tasks.contains { $0.forgeColumn != column }
            let alias = of.columnAlias(for: column)
            let needsAlias = alias.map { wanted in tasks.contains { $0.columnAliasTag != wanted } } ?? false
            let needsStripMulti = tasks.contains { $0.hasMultipleColumnTags }
            guard needsColumn || needsAlias || needsStripMulti else { continue }

            updates.append(OmniFocusService.ColumnUpdate(
                folderName: project.name,
                column: column,
                taskIds: tasks.map(\.id)
            ))
        }

        guard !updates.isEmpty else { return (0, 0, errors) }

        let outcome = try service.applyForgeColumns(updates)
        if !outcome.missingAlias.isEmpty {
            errors.append("Missing OF alias tag(s): \(outcome.missingAlias.joined(separator: ", "))")
        }
        _ = try? service.refreshSnapshot(forgeDir: forgeDir)
        return (updates.count, outcome.updated.count, errors)
    }

    /// Whether Refresh should force Finder to Shipped for a completed OF project.
    ///
    /// Returns false when Finder is already Shipped, the user suppressed re-ship,
    /// or a ship date exists while Finder is elsewhere (Finder override after ship).
    public static func shouldForceCompletedToShipped(
        finderColumn: String?,
        shippedAt: Date?,
        suppressed: Bool
    ) -> Bool {
        guard finderColumn != "Shipped" else { return false }
        if suppressed { return false }
        if shippedAt != nil { return false }
        return true
    }

    /// Move Finder folders to Shipped when the matching OF project is Done/Dropped.
    public static func applyCompletedProjectsToShipped(
        config: ForgeConfig,
        forgeDir: String,
        projects: [Project],
        inventory: OmniFocusInventory,
        tagStore: FinderTagStore = FinderTagStore()
    ) throws -> PullOutcome {
        let of = config.omnifocus
        guard of.enabled, of.syncCompletedProjectToShipped else {
            return PullOutcome(updatedFolders: [], errors: [])
        }
        guard config.board.columns.contains(where: { $0.name == "Shipped" }) else {
            return PullOutcome(updatedFolders: [], errors: ["Board has no Shipped column"])
        }

        let completedNames = Set(
            inventory.ofProjectSummaries.filter { $0.isCompleted }.map(\.name)
        )
        guard !completedNames.isEmpty else {
            return PullOutcome(updatedFolders: [], errors: [])
        }

        var updated: [String] = []
        var errors: [String] = []

        for project in projects {
            let alias = of.folderAliases[project.name] ?? project.name
            let ofNameMatches = completedNames.contains(project.name) || completedNames.contains(alias)
            guard ofNameMatches else { continue }
            // Prefer projects that are linked (have Forge tag or tasks); also allow name-only match.
            let linked = inventory.tasks.contains { $0.projectFolderName == project.name }
                || inventory.linkTags.contains { $0.folderName == project.name }
                || inventory.ofProjectNames.contains(project.name)
            guard linked else { continue }
            guard project.column != "Shipped" else { continue }

            let suppressed = (try? ShippedArchiveStore.isCompletedShipSuppressed(
                forgeDir: forgeDir,
                folderName: project.name
            )) == true
            let priorShip = try? ShippedArchiveStore.shippedAt(
                forgeDir: forgeDir,
                folderName: project.name
            )
            guard shouldForceCompletedToShipped(
                finderColumn: project.column,
                shippedAt: priorShip,
                suppressed: suppressed
            ) else {
                // Persist suppression when Finder left Shipped after a recorded ship.
                if !suppressed, priorShip != nil {
                    try? ShippedArchiveStore.suppressCompletedShip(
                        forgeDir: forgeDir,
                        folderName: project.name
                    )
                }
                continue
            }

            do {
                try setFinderWorkflowColumn(
                    path: project.path,
                    column: "Shipped",
                    config: config,
                    tagStore: tagStore,
                    forgeDir: forgeDir,
                    folderName: project.name,
                    previousColumn: project.column
                )
                updated.append(project.name)
            } catch {
                errors.append("\(project.name): \(error.localizedDescription)")
            }
        }

        return PullOutcome(updatedFolders: updated, errors: errors)
    }

    /// Board Refresh: OF → Finder only (plus completed→Shipped).
    ///
    /// Does **not** push Finder columns onto OmniFocus — that belongs to `forge move` /
    /// board drag. A full push after pull was restoring stale Finder tags (e.g. Review)
    /// when OF still carried both the old and new column tags.
    ///
    /// After a successful pull, strip leftover OF kanban tags down to the pulled column
    /// so the next Refresh does not re-prefer a stacked older tag.
    public static func syncBidirectionalOnRefresh(
        config: ForgeConfig,
        forgeDir: String,
        projects: [Project],
        force: Bool = false,
        tagStore: FinderTagStore = FinderTagStore()
    ) throws -> (pulledFolders: [String], pushedFolders: Int, errors: [String]) {
        let of = config.omnifocus
        var errors: [String] = []
        var pulled: [String] = []

        // Nexus: portable sidecar → local tags before OF → Finder.
        if config.nexus.sidecarEnabled, config.nexus.syncSidecarOnRefresh {
            do {
                let painted = try KanbanFsSync.paintAllFromSidecar(
                    projects: projects,
                    config: config,
                    tagStore: tagStore
                )
                pulled.append(contentsOf: painted.map(\.project))
            } catch {
                errors.append("sidecar paint: \(error.localizedDescription)")
            }
        }

        guard of.enabled else {
            return (Array(Set(pulled)).sorted(), 0, errors)
        }

        let service = OmniFocusService(config: config)
        let inventory = try service.fetchInventory()

        if of.syncCompletedProjectToShipped {
            let shipped = try applyCompletedProjectsToShipped(
                config: config,
                forgeDir: forgeDir,
                projects: projects,
                inventory: inventory,
                tagStore: tagStore
            )
            pulled.append(contentsOf: shipped.updatedFolders)
            errors.append(contentsOf: shipped.errors)
        }

        var pulledColumns: [String: String] = [:]
        if of.syncFromOmnifocus {
            let pull = try applyOmniFocusColumnsToFinder(
                config: config,
                forgeDir: forgeDir,
                projects: projects,
                force: force,
                tagStore: tagStore,
                inventory: inventory
            )
            pulled.append(contentsOf: pull.updatedFolders)
            errors.append(contentsOf: pull.errors)

            // Record which column we applied so OF multi-tag cleanup matches the pull.
            for name in pull.updatedFolders {
                let tasks = inventory.tasks.filter { $0.projectFolderName == name }
                let finderBefore = projects.first(where: { $0.name == name })?.column
                if let col = resolvedOmniFocusColumnForPull(
                    tasks: tasks,
                    finderColumn: finderBefore,
                    boardOrder: config.board.columns.map(\.name)
                ) {
                    pulledColumns[name] = col
                }
            }
        }

        var pushed = 0
        if of.syncOnMove, !pulledColumns.isEmpty {
            var updates: [OmniFocusService.ColumnUpdate] = []
            for (name, column) in pulledColumns {
                let tasks = inventory.tasks.filter { $0.projectFolderName == name }
                guard !tasks.isEmpty else { continue }
                let needsStrip = tasks.contains {
                    $0.hasMultipleColumnTags || $0.forgeColumn != column
                }
                guard needsStrip else { continue }
                updates.append(OmniFocusService.ColumnUpdate(
                    folderName: name,
                    column: column,
                    taskIds: tasks.map(\.id)
                ))
            }
            if !updates.isEmpty {
                let outcome = try service.applyForgeColumns(updates)
                pushed = outcome.updated.count
                if !outcome.missingAlias.isEmpty {
                    errors.append(
                        "Missing OF alias tag(s): \(outcome.missingAlias.joined(separator: ", "))"
                    )
                }
            }
        }

        _ = try? service.refreshSnapshot(forgeDir: forgeDir)
        return (Array(Set(pulled)).sorted(), pushed, errors)
    }
}
