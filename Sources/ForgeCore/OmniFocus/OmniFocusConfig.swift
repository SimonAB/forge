import Foundation

/// Optional OmniFocus bridge settings (`omnifocus:` in config.yaml).
public struct OmniFocusConfig: Codable, Sendable, Equatable {
    /// When false, CLI commands that talk to OmniFocus refuse to run (except documenting how to enable).
    public var enabled: Bool
    /// After a successful `forge move`, mirror the Finder column onto linked OF tasks.
    public var syncOnMove: Bool
    /// On board Refresh, pull a unanimous OF column onto the Finder workflow tag.
    public var syncFromOmnifocus: Bool
    /// When a linked OF *project* is Done/Dropped, move the Finder folder to Shipped on Refresh.
    public var syncCompletedProjectToShipped: Bool
    /// Allow `sync_on_move` even when `doctor` still reports drift.
    public var allowSyncWithDrift: Bool
    /// Maximum age of `.cache/omnifocus-snapshot.json` before refresh is required for enrichment.
    public var snapshotMaxAgeSeconds: TimeInterval
    /// Column to propose when linked tasks exist but the Finder folder has no workflow tag.
    public var defaultUntaggedColumn: String
    public var proposeUrgentOnOverdue: Bool
    public var proposeShippedWhenIdle: Bool
    /// Known renames: OmniFocus tag final component → actual folder name.
    public var folderAliases: [String: String]
    /// OmniFocus root tag for project links (aligned with Finder `project_tag` by default).
    public var linkTagRoot: String
    /// Older roots still recognised when reading (e.g. plain `Forge` from early pilots).
    public var legacyLinkTagRoots: [String]
    /// Nested OF tag root for column mirrors when not using flat aliases (e.g. `KanbanStatus/Watch`).
    public var columnTagRoot: String
    /// Older column roots still recognised when reading (e.g. `ForgeColumn`).
    public var legacyColumnTagRoots: [String]
    /// Forge column name → OmniFocus status tag (primary column marker when `flat_column_tags` is true).
    public var columnTagAliases: [String: String]
    /// Extra OF tag name → Forge column recognised when reading only (not written).
    public var columnTagAliasReads: [String: String]
    /// When true, write only `column_tag_aliases` for mapped columns (no nested `KanbanStatus/…`).
    public var flatColumnTags: Bool

    /// Default OF / Finder project-scope tag name.
    public static let defaultLinkTagRoot = "🔥 Forge"
    /// Default OF tag root for nested column mirrors (legacy / fallback).
    public static let defaultColumnTagRoot = "KanbanStatus"

    enum CodingKeys: String, CodingKey {
        case enabled
        case syncOnMove = "sync_on_move"
        case syncFromOmnifocus = "sync_from_omnifocus"
        case syncCompletedProjectToShipped = "sync_completed_project_to_shipped"
        case allowSyncWithDrift = "allow_sync_with_drift"
        case snapshotMaxAgeSeconds = "snapshot_max_age_seconds"
        case defaultUntaggedColumn = "default_untagged_column"
        case proposeUrgentOnOverdue = "propose_urgent_on_overdue"
        case proposeShippedWhenIdle = "propose_shipped_when_idle"
        case folderAliases = "folder_aliases"
        case linkTagRoot = "link_tag_root"
        case legacyLinkTagRoots = "legacy_link_tag_roots"
        case columnTagRoot = "column_tag_root"
        case legacyColumnTagRoots = "legacy_column_tag_roots"
        case columnTagAliases = "column_tag_aliases"
        case columnTagAliasReads = "column_tag_alias_reads"
        case flatColumnTags = "flat_column_tags"
    }

    public init(
        enabled: Bool = false,
        syncOnMove: Bool = false,
        syncFromOmnifocus: Bool = true,
        syncCompletedProjectToShipped: Bool = true,
        allowSyncWithDrift: Bool = false,
        snapshotMaxAgeSeconds: TimeInterval = 900,
        defaultUntaggedColumn: String = "Watch",
        proposeUrgentOnOverdue: Bool = true,
        proposeShippedWhenIdle: Bool = true,
        folderAliases: [String: String] = [:],
        linkTagRoot: String = OmniFocusConfig.defaultLinkTagRoot,
        legacyLinkTagRoots: [String] = ["Forge"],
        columnTagRoot: String = OmniFocusConfig.defaultColumnTagRoot,
        legacyColumnTagRoots: [String] = ["ForgeColumn"],
        columnTagAliases: [String: String] = [:],
        columnTagAliasReads: [String: String] = [:],
        flatColumnTags: Bool = true
    ) {
        self.enabled = enabled
        self.syncOnMove = syncOnMove
        self.syncFromOmnifocus = syncFromOmnifocus
        self.syncCompletedProjectToShipped = syncCompletedProjectToShipped
        self.allowSyncWithDrift = allowSyncWithDrift
        self.snapshotMaxAgeSeconds = snapshotMaxAgeSeconds
        self.defaultUntaggedColumn = defaultUntaggedColumn
        self.proposeUrgentOnOverdue = proposeUrgentOnOverdue
        self.proposeShippedWhenIdle = proposeShippedWhenIdle
        self.folderAliases = folderAliases
        self.linkTagRoot = linkTagRoot
        self.legacyLinkTagRoots = legacyLinkTagRoots
        self.columnTagRoot = columnTagRoot
        self.legacyColumnTagRoots = legacyColumnTagRoots
        self.columnTagAliases = columnTagAliases
        self.columnTagAliasReads = columnTagAliasReads
        self.flatColumnTags = flatColumnTags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        syncOnMove = try c.decodeIfPresent(Bool.self, forKey: .syncOnMove) ?? false
        syncFromOmnifocus = try c.decodeIfPresent(Bool.self, forKey: .syncFromOmnifocus) ?? true
        syncCompletedProjectToShipped = try c.decodeIfPresent(Bool.self, forKey: .syncCompletedProjectToShipped) ?? true
        allowSyncWithDrift = try c.decodeIfPresent(Bool.self, forKey: .allowSyncWithDrift) ?? false
        snapshotMaxAgeSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .snapshotMaxAgeSeconds) ?? 900
        defaultUntaggedColumn = try c.decodeIfPresent(String.self, forKey: .defaultUntaggedColumn) ?? "Watch"
        proposeUrgentOnOverdue = try c.decodeIfPresent(Bool.self, forKey: .proposeUrgentOnOverdue) ?? true
        proposeShippedWhenIdle = try c.decodeIfPresent(Bool.self, forKey: .proposeShippedWhenIdle) ?? true
        folderAliases = try c.decodeIfPresent([String: String].self, forKey: .folderAliases) ?? [:]
        linkTagRoot = try c.decodeIfPresent(String.self, forKey: .linkTagRoot) ?? Self.defaultLinkTagRoot
        legacyLinkTagRoots = try c.decodeIfPresent([String].self, forKey: .legacyLinkTagRoots) ?? ["Forge"]
        columnTagRoot = try c.decodeIfPresent(String.self, forKey: .columnTagRoot) ?? Self.defaultColumnTagRoot
        legacyColumnTagRoots = try c.decodeIfPresent([String].self, forKey: .legacyColumnTagRoots) ?? ["ForgeColumn"]
        columnTagAliases = try c.decodeIfPresent([String: String].self, forKey: .columnTagAliases) ?? [:]
        columnTagAliasReads = try c.decodeIfPresent([String: String].self, forKey: .columnTagAliasReads) ?? [:]
        flatColumnTags = try c.decodeIfPresent(Bool.self, forKey: .flatColumnTags) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(syncOnMove, forKey: .syncOnMove)
        if !syncFromOmnifocus {
            try c.encode(syncFromOmnifocus, forKey: .syncFromOmnifocus)
        }
        if !syncCompletedProjectToShipped {
            try c.encode(syncCompletedProjectToShipped, forKey: .syncCompletedProjectToShipped)
        }
        try c.encode(allowSyncWithDrift, forKey: .allowSyncWithDrift)
        try c.encode(snapshotMaxAgeSeconds, forKey: .snapshotMaxAgeSeconds)
        try c.encode(defaultUntaggedColumn, forKey: .defaultUntaggedColumn)
        try c.encode(proposeUrgentOnOverdue, forKey: .proposeUrgentOnOverdue)
        try c.encode(proposeShippedWhenIdle, forKey: .proposeShippedWhenIdle)
        if !folderAliases.isEmpty {
            try c.encode(folderAliases, forKey: .folderAliases)
        }
        try c.encode(linkTagRoot, forKey: .linkTagRoot)
        if legacyLinkTagRoots != ["Forge"] {
            try c.encode(legacyLinkTagRoots, forKey: .legacyLinkTagRoots)
        }
        try c.encode(columnTagRoot, forKey: .columnTagRoot)
        if legacyColumnTagRoots != ["ForgeColumn"] {
            try c.encode(legacyColumnTagRoots, forKey: .legacyColumnTagRoots)
        }
        if !columnTagAliases.isEmpty {
            try c.encode(columnTagAliases, forKey: .columnTagAliases)
        }
        if !columnTagAliasReads.isEmpty {
            try c.encode(columnTagAliasReads, forKey: .columnTagAliasReads)
        }
        if !flatColumnTags {
            try c.encode(flatColumnTags, forKey: .flatColumnTags)
        }
    }

    /// Copy with selected flags changed (for Preferences UI).
    public func updating(
        enabled: Bool? = nil,
        syncOnMove: Bool? = nil,
        syncFromOmnifocus: Bool? = nil
    ) -> OmniFocusConfig {
        var copy = self
        if let enabled { copy.enabled = enabled }
        if let syncOnMove { copy.syncOnMove = syncOnMove }
        if let syncFromOmnifocus { copy.syncFromOmnifocus = syncFromOmnifocus }
        return copy
    }

    /// Roots accepted when reading OF link tags (canonical first, then legacy aliases).
    public var readLinkTagRoots: [String] {
        var roots = [linkTagRoot]
        for legacy in legacyLinkTagRoots where legacy != linkTagRoot {
            roots.append(legacy)
        }
        return roots
    }

    /// Roots accepted when reading OF column tags (canonical first, then legacy).
    public var readColumnTagRoots: [String] {
        var roots = [columnTagRoot]
        for legacy in legacyColumnTagRoots where legacy != columnTagRoot {
            roots.append(legacy)
        }
        return roots
    }

    /// Canonical path string for a folder link tag, e.g. `🔥 Forge:Lepto`.
    public func linkTagPath(folderName: String) -> String {
        "\(linkTagRoot):\(folderName)"
    }

    /// Nested path string for a column mirror tag, e.g. `KanbanStatus/Watch`.
    public func columnTagPath(column: String) -> String {
        "\(columnTagRoot)/\(column)"
    }

    /// Human-facing OF column tag label (flat alias when configured, else nested path).
    public func columnTagLabel(for column: String) -> String {
        if flatColumnTags, let alias = columnAlias(for: column) {
            return alias
        }
        return columnTagPath(column: column)
    }

    /// True when writes for this column should use only the flat alias tag.
    public func writesFlatAlias(for column: String) -> Bool {
        flatColumnTags && columnAlias(for: column) != nil
    }

    /// True when `root` is a legacy column tag root (not the canonical one).
    public func isLegacyColumnTagRoot(_ root: String?) -> Bool {
        guard let root, root != columnTagRoot else { return false }
        return legacyColumnTagRoots.contains(root)
    }

    /// OmniFocus tag name aliased for a Forge column, if configured.
    public func columnAlias(for column: String) -> String? {
        columnTagAliases[column]
    }

    /// OF tag name → Forge column (write aliases plus read-only extras).
    public var columnTagNameToColumn: [String: String] {
        var map = columnTagAliasReads
        for (column, name) in columnTagAliases {
            map[name] = column
        }
        return map
    }

    /// All OF status tag names to strip when changing column (write + read aliases).
    public var allColumnAliasNames: [String] {
        Array(Set(columnTagAliases.values).union(columnTagAliasReads.keys)).sorted()
    }
}
