import Foundation

/// Decodes the OmniJS export payload (ISO-8601 date strings).
struct OmniFocusInventoryDTO: Decodable {
    let ok: Bool?
    let generatedAt: String
    let hasForgeRootTag: Bool
    let hasCanonicalRootTag: Bool?
    let linkRoot: String?
    let columnRoot: String?
    let linkTags: [LinkTagDTO]
    let tasks: [TaskDTO]
    let ofProjectNames: [String]
    let ofProjectSummaries: [ProjectSummaryDTO]?

    struct LinkTagDTO: Decodable {
        let path: String
        let folderName: String
        let taskCount: Int
    }

    struct TaskDTO: Decodable {
        let id: String
        let title: String
        let projectFolderName: String?
        let projectTag: String?
        let forgeColumn: String?
        let forgeColumns: [String]?
        let columnTagRoot: String?
        let columnAliasTag: String?
        let due: String?
        let completed: Bool
        let ofProjectName: String?
    }

    struct ProjectSummaryDTO: Decodable {
        let name: String
        let activeTaskCount: Int
        let isCompleted: Bool?
    }

    func toInventory(fallbackLinkRoot: String, boardOrder: [String]) -> OmniFocusInventory {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterBasic = ISO8601DateFormatter()
        formatterBasic.formatOptions = [.withInternetDateTime]

        func parseDate(_ s: String?) -> Date? {
            guard let s else { return nil }
            return formatter.date(from: s) ?? formatterBasic.date(from: s)
        }

        let generated = parseDate(generatedAt) ?? Date()
        let tags = linkTags.map {
            OmniFocusLinkTag(path: $0.path, folderName: $0.folderName, taskCount: $0.taskCount)
        }
        let tasks = tasks.map { dto -> OmniFocusTaskRecord in
            let rawColumns: [String]
            if let listed = dto.forgeColumns, !listed.isEmpty {
                rawColumns = listed
            } else if let single = dto.forgeColumn {
                rawColumns = [single]
            } else {
                rawColumns = []
            }
            let resolution = OmniFocusColumnResolution.resolveTask(
                columns: rawColumns,
                boardOrder: boardOrder
            )
            return OmniFocusTaskRecord(
                id: dto.id,
                title: dto.title,
                projectFolderName: dto.projectFolderName,
                projectTag: dto.projectTag,
                forgeColumn: resolution.resolved,
                forgeColumns: resolution.columns,
                columnTagRoot: dto.columnTagRoot,
                columnAliasTag: dto.columnAliasTag,
                due: parseDate(dto.due),
                completed: dto.completed,
                ofProjectName: dto.ofProjectName
            )
        }
        let summaries = (ofProjectSummaries ?? []).map {
            OmniFocusProjectSummary(
                name: $0.name,
                activeTaskCount: $0.activeTaskCount,
                isCompleted: $0.isCompleted ?? false
            )
        }
        return OmniFocusInventory(
            generatedAt: generated,
            hasForgeRootTag: hasForgeRootTag,
            hasCanonicalRootTag: hasCanonicalRootTag,
            linkRoot: linkRoot ?? fallbackLinkRoot,
            linkTags: tags,
            tasks: tasks,
            ofProjectNames: ofProjectNames,
            ofProjectSummaries: summaries
        )
    }
}

/// High-level OmniFocus operations used by the CLI.
public struct OmniFocusService: Sendable {
    public let config: ForgeConfig
    public let bridge: OmniJSBridge

    public init(config: ForgeConfig, bridge: OmniJSBridge = OmniJSBridge()) {
        self.config = config
        self.bridge = bridge
    }

    public var ofConfig: OmniFocusConfig { config.omnifocus }

    public func requireEnabled() throws {
        guard ofConfig.enabled else { throw OmniJSBridgeError.disabled }
    }

    private struct InventoryArgs: Encodable {
        let linkRoot: String
        let legacyRoots: [String]
        let columnRoot: String
        let legacyColumnRoots: [String]
        let columnAliases: [String: String]
        let columnAliasReads: [String: String]
    }

    private var inventoryArgs: InventoryArgs {
        InventoryArgs(
            linkRoot: ofConfig.linkTagRoot,
            legacyRoots: ofConfig.legacyLinkTagRoots,
            columnRoot: ofConfig.columnTagRoot,
            legacyColumnRoots: ofConfig.legacyColumnTagRoots,
            columnAliases: ofConfig.columnTagAliases,
            columnAliasReads: ofConfig.columnTagAliasReads
        )
    }

    /// Live export from OmniFocus.
    public func fetchInventory() throws -> OmniFocusInventory {
        try requireEnabled()
        let dto: OmniFocusInventoryDTO = try bridge.evaluateJSON(
            omniJSSource: OmniJSSnippets.exportInventory,
            argument: inventoryArgs
        )
        return dto.toInventory(
            fallbackLinkRoot: ofConfig.linkTagRoot,
            boardOrder: config.board.columns.map(\.name)
        )
    }

    /// Refresh local snapshot cache from a live export.
    public func refreshSnapshot(forgeDir: String) throws -> OmniFocusInventory {
        let inventory = try fetchInventory()
        try OmniFocusSnapshotStore.write(forgeDir: forgeDir, inventory: inventory)
        return inventory
    }

    /// Load snapshot if present and fresh enough.
    public func loadEligibleSnapshot(forgeDir: String, now: Date = Date()) throws -> OmniFocusInventory? {
        try OmniFocusSnapshotStore.loadIfEligible(
            forgeDir: forgeDir,
            maxAge: ofConfig.snapshotMaxAgeSeconds,
            now: now
        )
    }

    /// Apply ensure-tag / set-column writes. Caller must have already shown a dry-run plan.
    public func applyEnsureTags(folders: [String], ensureRoot: Bool) throws -> [String] {
        try requireEnabled()
        struct Args: Encodable {
            let ensureRoot: Bool
            let folders: [String]
            let linkRoot: String
        }
        struct Result: Decodable { let ok: Bool?; let created: [String] }
        let result: Result = try bridge.evaluateJSON(
            omniJSSource: OmniJSSnippets.ensureLinkTags,
            argument: Args(
                ensureRoot: ensureRoot,
                folders: folders,
                linkRoot: ofConfig.linkTagRoot
            )
        )
        return result.created
    }

    public func applyForgeColumn(folderName: String, column: String, taskIds: [String] = []) throws -> (updated: [String], missingAlias: [String]) {
        let batch = try applyForgeColumns([
            ColumnUpdate(folderName: folderName, column: column, taskIds: taskIds),
        ])
        return (batch.updated, batch.missingAlias)
    }

    /// One folder/column write for batched OmniFocus updates.
    public struct ColumnUpdate: Encodable, Sendable {
        public let folderName: String
        public let column: String
        public let taskIds: [String]

        public init(folderName: String, column: String, taskIds: [String] = []) {
            self.folderName = folderName
            self.column = column
            self.taskIds = taskIds
        }
    }

    public struct ColumnApplyOutcome: Sendable {
        public let updated: [String]
        public let missingAlias: [String]
        public let results: [FolderColumnResult]

        public struct FolderColumnResult: Sendable {
            public let folderName: String
            public let column: String
            public let updated: [String]
            public let missingAlias: [String]
        }
    }

    /// Apply several folder→column writes in a single OmniJS evaluation.
    public func applyForgeColumns(_ updates: [ColumnUpdate]) throws -> ColumnApplyOutcome {
        try requireEnabled()
        guard !updates.isEmpty else {
            return ColumnApplyOutcome(updated: [], missingAlias: [], results: [])
        }
        struct Args: Encodable {
            let updates: [ColumnUpdate]
            let linkRoot: String
            let legacyRoots: [String]
            let columnRoot: String
            let legacyColumnRoots: [String]
            let columnAliases: [String: String]
            let columnAliasReads: [String: String]
            let flatColumnTags: Bool
        }
        struct ResultDTO: Decodable {
            let ok: Bool?
            let updated: [String]
            let missingAlias: [String]?
            let results: [OneDTO]?

            struct OneDTO: Decodable {
                let folderName: String
                let column: String
                let updated: [String]
                let missingAlias: [String]?
            }
        }
        let dto: ResultDTO = try bridge.evaluateJSON(
            omniJSSource: OmniJSSnippets.setForgeColumnTags,
            argument: Args(
                updates: updates,
                linkRoot: ofConfig.linkTagRoot,
                legacyRoots: ofConfig.legacyLinkTagRoots,
                columnRoot: ofConfig.columnTagRoot,
                legacyColumnRoots: ofConfig.legacyColumnTagRoots,
                columnAliases: ofConfig.columnTagAliases,
                columnAliasReads: ofConfig.columnTagAliasReads,
                flatColumnTags: ofConfig.flatColumnTags
            )
        )
        let results = (dto.results ?? []).map {
            ColumnApplyOutcome.FolderColumnResult(
                folderName: $0.folderName,
                column: $0.column,
                updated: $0.updated,
                missingAlias: $0.missingAlias ?? []
            )
        }
        return ColumnApplyOutcome(
            updated: dto.updated,
            missingAlias: dto.missingAlias ?? [],
            results: results
        )
    }

    /// Create `<linkRoot>:<folderName>` if needed and tag the matching OF project + active tasks.
    public func applyTagMatchingOfProject(folderName: String) throws -> (createdTag: Bool, taggedTaskCount: Int) {
        try requireEnabled()
        let aliasProjectNames = ofConfig.folderAliases
            .filter { $0.value == folderName }
            .map(\.key)
            .sorted()
        struct Args: Encodable {
            let folderName: String
            let linkRoot: String
            let aliasProjectNames: [String]
        }
        struct Result: Decodable {
            let ok: Bool?
            let error: String?
            let createdTag: Bool?
            let taggedTaskIds: [String]?
        }
        let result: Result = try bridge.evaluateJSON(
            omniJSSource: OmniJSSnippets.tagMatchingOfProject,
            argument: Args(
                folderName: folderName,
                linkRoot: ofConfig.linkTagRoot,
                aliasProjectNames: aliasProjectNames
            )
        )
        if result.ok == false {
            throw OmniJSBridgeError.evaluationFailed(result.error ?? "tag_matching_of_project failed")
        }
        return (result.createdTag ?? false, result.taggedTaskIds?.count ?? 0)
    }

    /// Result of setting an OmniFocus project status (Active / Done).
    public struct ProjectStatusOutcome: Sendable, Equatable {
        public let updated: Bool
        public let projectName: String?
        public let status: String
        public let before: String?
        public let reason: String?

        public init(
            updated: Bool,
            projectName: String?,
            status: String,
            before: String?,
            reason: String?
        ) {
            self.updated = updated
            self.projectName = projectName
            self.status = status
            self.before = before
            self.reason = reason
        }
    }

    /// Set the matching OF project to Active or Done (by Finder folder name + aliases).
    public func applyOfProjectStatus(folderName: String, status: String) throws -> ProjectStatusOutcome {
        try requireEnabled()
        let aliasProjectNames = ofConfig.folderAliases
            .filter { $0.value == folderName }
            .map(\.key)
            .sorted()
        struct Args: Encodable {
            let folderName: String
            let status: String
            let aliasProjectNames: [String]
        }
        struct Result: Decodable {
            let ok: Bool?
            let error: String?
            let updated: Bool?
            let projectName: String?
            let status: String?
            let before: String?
            let reason: String?
        }
        let result: Result = try bridge.evaluateJSON(
            omniJSSource: OmniJSSnippets.setOfProjectStatus,
            argument: Args(
                folderName: folderName,
                status: status,
                aliasProjectNames: aliasProjectNames
            )
        )
        if result.ok == false {
            throw OmniJSBridgeError.evaluationFailed(result.error ?? "set_of_project_status failed")
        }
        return ProjectStatusOutcome(
            updated: result.updated ?? false,
            projectName: result.projectName,
            status: result.status ?? status,
            before: result.before,
            reason: result.reason
        )
    }
}
