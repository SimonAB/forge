import Foundation

// MARK: - Inventory from OmniFocus

/// One OmniFocus task linked (or linkable) to a Forge project folder.
public struct OmniFocusTaskRecord: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let projectFolderName: String?
    public let projectTag: String?
    /// Resolved Forge workflow column (policy pick when several kanban tags are present).
    public let forgeColumn: String?
    /// All distinct Forge columns detected from OF kanban tags on this task.
    public let forgeColumns: [String]
    /// OF tag root that carried a nested column (`KanbanStatus` or legacy `ForgeColumn`), if any.
    public let columnTagRoot: String?
    /// Primary flat OF status tag (first alias match), if present.
    public let columnAliasTag: String?
    public let due: Date?
    public let completed: Bool
    public let ofProjectName: String?

    /// True when more than one distinct kanban column tag was present on the task.
    public var hasMultipleColumnTags: Bool { forgeColumns.count > 1 }

    public init(
        id: String,
        title: String,
        projectFolderName: String?,
        projectTag: String?,
        forgeColumn: String?,
        forgeColumns: [String] = [],
        columnTagRoot: String? = nil,
        columnAliasTag: String? = nil,
        due: Date?,
        completed: Bool,
        ofProjectName: String?
    ) {
        self.id = id
        self.title = title
        self.projectFolderName = projectFolderName
        self.projectTag = projectTag
        let cols = forgeColumns.isEmpty ? (forgeColumn.map { [$0] } ?? []) : forgeColumns
        self.forgeColumns = cols
        self.forgeColumn = forgeColumn ?? cols.first
        self.columnTagRoot = columnTagRoot
        self.columnAliasTag = columnAliasTag
        self.due = due
        self.completed = completed
        self.ofProjectName = ofProjectName
    }

    enum CodingKeys: String, CodingKey {
        case id, title, projectFolderName, projectTag, forgeColumn, forgeColumns
        case columnTagRoot, columnAliasTag, due, completed, ofProjectName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        projectFolderName = try c.decodeIfPresent(String.self, forKey: .projectFolderName)
        projectTag = try c.decodeIfPresent(String.self, forKey: .projectTag)
        let single = try c.decodeIfPresent(String.self, forKey: .forgeColumn)
        let cols = try c.decodeIfPresent([String].self, forKey: .forgeColumns) ?? []
        let resolvedCols = cols.isEmpty ? (single.map { [$0] } ?? []) : cols
        forgeColumns = resolvedCols
        forgeColumn = single ?? resolvedCols.first
        columnTagRoot = try c.decodeIfPresent(String.self, forKey: .columnTagRoot)
        columnAliasTag = try c.decodeIfPresent(String.self, forKey: .columnAliasTag)
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        completed = try c.decode(Bool.self, forKey: .completed)
        ofProjectName = try c.decodeIfPresent(String.self, forKey: .ofProjectName)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(projectFolderName, forKey: .projectFolderName)
        try c.encodeIfPresent(projectTag, forKey: .projectTag)
        try c.encodeIfPresent(forgeColumn, forKey: .forgeColumn)
        if !forgeColumns.isEmpty {
            try c.encode(forgeColumns, forKey: .forgeColumns)
        }
        try c.encodeIfPresent(columnTagRoot, forKey: .columnTagRoot)
        try c.encodeIfPresent(columnAliasTag, forKey: .columnAliasTag)
        try c.encodeIfPresent(due, forKey: .due)
        try c.encode(completed, forKey: .completed)
        try c.encodeIfPresent(ofProjectName, forKey: .ofProjectName)
    }
}

/// Tag under the OmniFocus `Forge` root (or flat `Forge/…`).
public struct OmniFocusLinkTag: Codable, Sendable, Equatable {
    public let path: String
    public let folderName: String
    public let taskCount: Int

    public init(path: String, folderName: String, taskCount: Int) {
        self.path = path
        self.folderName = folderName
        self.taskCount = taskCount
    }
}

/// Snapshot / live export payload from OmniFocus.
public struct OmniFocusInventory: Codable, Sendable, Equatable {
    public let generatedAt: Date
    /// True if any recognised link root exists (canonical or legacy).
    public let hasForgeRootTag: Bool
    /// True if the configured canonical root (e.g. 🔥 Forge) exists.
    public let hasCanonicalRootTag: Bool
    public let linkRoot: String
    public let linkTags: [OmniFocusLinkTag]
    public let tasks: [OmniFocusTaskRecord]
    public let ofProjectNames: [String]
    /// Active (incomplete) task counts for OF projects, when available.
    public let ofProjectSummaries: [OmniFocusProjectSummary]

    public init(
        generatedAt: Date,
        hasForgeRootTag: Bool,
        hasCanonicalRootTag: Bool? = nil,
        linkRoot: String = OmniFocusConfig.defaultLinkTagRoot,
        linkTags: [OmniFocusLinkTag],
        tasks: [OmniFocusTaskRecord],
        ofProjectNames: [String],
        ofProjectSummaries: [OmniFocusProjectSummary] = []
    ) {
        self.generatedAt = generatedAt
        self.hasForgeRootTag = hasForgeRootTag
        self.hasCanonicalRootTag = hasCanonicalRootTag ?? hasForgeRootTag
        self.linkRoot = linkRoot
        self.linkTags = linkTags
        self.tasks = tasks
        self.ofProjectNames = ofProjectNames
        self.ofProjectSummaries = ofProjectSummaries.isEmpty
            ? ofProjectNames.map { OmniFocusProjectSummary(name: $0, activeTaskCount: 0, isCompleted: false) }
            : ofProjectSummaries
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt, hasForgeRootTag, hasCanonicalRootTag, linkRoot
        case linkTags, tasks, ofProjectNames, ofProjectSummaries
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        hasForgeRootTag = try c.decode(Bool.self, forKey: .hasForgeRootTag)
        hasCanonicalRootTag = try c.decodeIfPresent(Bool.self, forKey: .hasCanonicalRootTag) ?? hasForgeRootTag
        linkRoot = try c.decodeIfPresent(String.self, forKey: .linkRoot) ?? OmniFocusConfig.defaultLinkTagRoot
        linkTags = try c.decode([OmniFocusLinkTag].self, forKey: .linkTags)
        tasks = try c.decode([OmniFocusTaskRecord].self, forKey: .tasks)
        ofProjectNames = try c.decode([String].self, forKey: .ofProjectNames)
        let summaries = try c.decodeIfPresent([OmniFocusProjectSummary].self, forKey: .ofProjectSummaries) ?? []
        ofProjectSummaries = summaries.isEmpty
            ? ofProjectNames.map { OmniFocusProjectSummary(name: $0, activeTaskCount: 0, isCompleted: false) }
            : summaries
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encode(hasForgeRootTag, forKey: .hasForgeRootTag)
        try c.encode(hasCanonicalRootTag, forKey: .hasCanonicalRootTag)
        try c.encode(linkRoot, forKey: .linkRoot)
        try c.encode(linkTags, forKey: .linkTags)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(ofProjectNames, forKey: .ofProjectNames)
        try c.encode(ofProjectSummaries, forKey: .ofProjectSummaries)
    }
}

/// OmniFocus project name with active task count (for dry-run summaries).
public struct OmniFocusProjectSummary: Codable, Sendable, Equatable {
    public let name: String
    public let activeTaskCount: Int
    /// True when the OF project is Done or Dropped.
    public let isCompleted: Bool

    public init(name: String, activeTaskCount: Int, isCompleted: Bool = false) {
        self.name = name
        self.activeTaskCount = activeTaskCount
        self.isCompleted = isCompleted
    }

    enum CodingKeys: String, CodingKey {
        case name, activeTaskCount, isCompleted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        activeTaskCount = try c.decode(Int.self, forKey: .activeTaskCount)
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(activeTaskCount, forKey: .activeTaskCount)
        if isCompleted {
            try c.encode(isCompleted, forKey: .isCompleted)
        }
    }
}

// MARK: - Doctor / align

public enum OmniFocusDoctorBucket: String, Codable, Sendable {
    case aligned
    case forgeOnly = "forge_only"
    case ofOnly = "of_only"
    case ambiguous
    case columnDrift = "column_drift"
    case structureHint = "structure_hint"
    case hygiene
}

public struct OmniFocusDoctorItem: Codable, Sendable, Equatable {
    public let bucket: OmniFocusDoctorBucket
    public let folderName: String?
    public let path: String?
    public let ofTag: String?
    public let finderColumn: String?
    public let ofColumn: String?
    public let detail: String

    public init(
        bucket: OmniFocusDoctorBucket,
        folderName: String? = nil,
        path: String? = nil,
        ofTag: String? = nil,
        finderColumn: String? = nil,
        ofColumn: String? = nil,
        detail: String
    ) {
        self.bucket = bucket
        self.folderName = folderName
        self.path = path
        self.ofTag = ofTag
        self.finderColumn = finderColumn
        self.ofColumn = ofColumn
        self.detail = detail
    }
}

public struct OmniFocusDoctorReport: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let items: [OmniFocusDoctorItem]
    public let isClean: Bool

    public init(generatedAt: Date, items: [OmniFocusDoctorItem]) {
        self.generatedAt = generatedAt
        self.items = items
        let blocking: Set<OmniFocusDoctorBucket> = [.forgeOnly, .ofOnly, .ambiguous, .columnDrift]
        self.isClean = !items.contains { blocking.contains($0.bucket) }
    }
}

public enum OmniFocusAlignKind: String, Codable, Sendable {
    case ensureForgeRootTag = "ensure_forge_root_tag"
    case createOfLinkTag = "create_of_link_tag"
    /// Create `<linkRoot>:<name>` if needed and tag the matching OF project + its active tasks.
    case tagMatchingOfProject = "tag_matching_of_project"
    case setForgeColumnFromFinder = "set_forge_column_from_finder"
    case setFinderColumnFromOf = "set_finder_column_from_of"
    /// Rewrite legacy column tag roots (e.g. `ForgeColumn/…`) onto the canonical root.
    case migrateColumnTagRoot = "migrate_column_tag_root"
    /// Apply configured `column_tag_aliases` OF tag (and strip nested duplicates when flat).
    case ensureColumnAlias = "ensure_column_alias"
    case suggestRename = "suggest_rename"
    case ignore = "ignore"
}

/// One planned change. Dry-run prints these; `--apply` executes them.
public struct OmniFocusAlignProposal: Codable, Sendable, Equatable {
    public let id: String
    public let kind: OmniFocusAlignKind
    public let folderName: String?
    public let path: String?
    public let ofTag: String?
    public let column: String?
    public let taskIds: [String]
    public let summary: String

    public init(
        id: String = UUID().uuidString,
        kind: OmniFocusAlignKind,
        folderName: String? = nil,
        path: String? = nil,
        ofTag: String? = nil,
        column: String? = nil,
        taskIds: [String] = [],
        summary: String
    ) {
        self.id = id
        self.kind = kind
        self.folderName = folderName
        self.path = path
        self.ofTag = ofTag
        self.column = column
        self.taskIds = taskIds
        self.summary = summary
    }
}

public struct OmniFocusAlignPlan: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let proposals: [OmniFocusAlignProposal]
    public let dryRun: Bool

    public init(generatedAt: Date, proposals: [OmniFocusAlignProposal], dryRun: Bool) {
        self.generatedAt = generatedAt
        self.proposals = proposals
        self.dryRun = dryRun
    }
}

/// Per-project enrichment embedded in `forge board --json`.
public struct OmniFocusBoardEnrichment: Codable, Sendable, Equatable {
    public let taskCount: Int
    public let nextTask: String?
    public let due: Date?
    public let forgeColumn: String?
    public let snapshotAgeSeconds: TimeInterval?

    public init(
        taskCount: Int,
        nextTask: String?,
        due: Date?,
        forgeColumn: String?,
        snapshotAgeSeconds: TimeInterval?
    ) {
        self.taskCount = taskCount
        self.nextTask = nextTask
        self.due = due
        self.forgeColumn = forgeColumn
        self.snapshotAgeSeconds = snapshotAgeSeconds
    }
}
