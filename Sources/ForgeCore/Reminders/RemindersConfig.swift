import Foundation

/// Optional Apple Reminders backend settings (`reminders:` in config.yaml).
///
/// Lists match Forge project folders by title. Optional column sync uses one
/// sentinel reminder per list. Ordinary reminder items are not created or completed.
public struct RemindersConfig: Codable, Sendable, Equatable {
    /// When false, CLI commands that talk to Reminders refuse to run (except `status`).
    public var enabled: Bool
    /// Optional extra inbox list title. Shown but not treated as a project unless a
    /// folder has the same name. Migrated from `gtd.reminders_list` when unset.
    public var list: String
    /// Maximum age of `.cache/reminders-snapshot.json` before a live EventKit refresh.
    public var snapshotMaxAgeSeconds: TimeInterval
    /// When true, default CLI listing includes completed reminders.
    public var includeCompleted: Bool
    /// After a successful `forge move`, update the sentinel reminder on the matched list.
    public var syncOnMove: Bool
    /// On board Refresh / `forge reminders refresh --apply-finder`, pull sentinel → Finder.
    public var syncFromReminders: Bool
    /// Title prefix for the per-list kanban sentinel (`Forge · Watch`).
    public var sentinelPrefix: String
    /// Optional EventKit source title (iCloud / On My Mac) when creating lists.
    public var source: String?
    /// Reminders list title → Forge folder name (case-insensitive keys).
    public var folderAliases: [String: String]
    /// Whether `list` appeared in YAML. Used only during `ForgeConfig` decode migration.
    var listSpecifiedInYAML: Bool

    public static let defaultListName = "Forge"
    public static let defaultSnapshotMaxAge: TimeInterval = 900
    /// Middle dot U+00B7.
    public static let defaultSentinelPrefix = "Forge · "

    enum CodingKeys: String, CodingKey {
        case enabled
        case list
        case snapshotMaxAgeSeconds = "snapshot_max_age_seconds"
        case includeCompleted = "include_completed"
        case syncOnMove = "sync_on_move"
        case syncFromReminders = "sync_from_reminders"
        case sentinelPrefix = "sentinel_prefix"
        case source
        case folderAliases = "folder_aliases"
    }

    public init(
        enabled: Bool = false,
        list: String = RemindersConfig.defaultListName,
        snapshotMaxAgeSeconds: TimeInterval = RemindersConfig.defaultSnapshotMaxAge,
        includeCompleted: Bool = false,
        syncOnMove: Bool = false,
        syncFromReminders: Bool = false,
        sentinelPrefix: String = RemindersConfig.defaultSentinelPrefix,
        source: String? = nil,
        folderAliases: [String: String] = [:],
        listSpecifiedInYAML: Bool = true
    ) {
        self.enabled = enabled
        self.list = list
        self.snapshotMaxAgeSeconds = snapshotMaxAgeSeconds
        self.includeCompleted = includeCompleted
        self.syncOnMove = syncOnMove
        self.syncFromReminders = syncFromReminders
        self.sentinelPrefix = sentinelPrefix
        self.source = source
        self.folderAliases = folderAliases
        self.listSpecifiedInYAML = listSpecifiedInYAML
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        if c.contains(.list) {
            let raw = (try c.decode(String.self, forKey: .list))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            list = raw.isEmpty ? Self.defaultListName : raw
            listSpecifiedInYAML = true
        } else {
            list = Self.defaultListName
            listSpecifiedInYAML = false
        }
        snapshotMaxAgeSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .snapshotMaxAgeSeconds)
            ?? Self.defaultSnapshotMaxAge
        includeCompleted = try c.decodeIfPresent(Bool.self, forKey: .includeCompleted) ?? false
        syncOnMove = try c.decodeIfPresent(Bool.self, forKey: .syncOnMove) ?? false
        syncFromReminders = try c.decodeIfPresent(Bool.self, forKey: .syncFromReminders) ?? false
        if let prefixRaw = try c.decodeIfPresent(String.self, forKey: .sentinelPrefix) {
            let collapsed = prefixRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            sentinelPrefix = collapsed.isEmpty ? Self.defaultSentinelPrefix : prefixRaw
        } else {
            sentinelPrefix = Self.defaultSentinelPrefix
        }
        let sourceRaw = try c.decodeIfPresent(String.self, forKey: .source)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        source = (sourceRaw?.isEmpty == false) ? sourceRaw : nil
        folderAliases = try c.decodeIfPresent([String: String].self, forKey: .folderAliases) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(list, forKey: .list)
        try c.encode(snapshotMaxAgeSeconds, forKey: .snapshotMaxAgeSeconds)
        try c.encode(includeCompleted, forKey: .includeCompleted)
        try c.encode(syncOnMove, forKey: .syncOnMove)
        try c.encode(syncFromReminders, forKey: .syncFromReminders)
        if sentinelPrefix != Self.defaultSentinelPrefix {
            try c.encode(sentinelPrefix, forKey: .sentinelPrefix)
        }
        if let source, !source.isEmpty {
            try c.encode(source, forKey: .source)
        }
        if !folderAliases.isEmpty {
            try c.encode(folderAliases, forKey: .folderAliases)
        }
    }

    public static func == (lhs: RemindersConfig, rhs: RemindersConfig) -> Bool {
        lhs.enabled == rhs.enabled
            && lhs.list == rhs.list
            && lhs.snapshotMaxAgeSeconds == rhs.snapshotMaxAgeSeconds
            && lhs.includeCompleted == rhs.includeCompleted
            && lhs.syncOnMove == rhs.syncOnMove
            && lhs.syncFromReminders == rhs.syncFromReminders
            && lhs.sentinelPrefix == rhs.sentinelPrefix
            && lhs.source == rhs.source
            && lhs.folderAliases == rhs.folderAliases
    }

    /// Copy with selected flags changed (for Preferences UI).
    public func updating(
        enabled: Bool? = nil,
        list: String? = nil,
        includeCompleted: Bool? = nil,
        syncOnMove: Bool? = nil,
        syncFromReminders: Bool? = nil
    ) -> RemindersConfig {
        var copy = self
        if let enabled { copy.enabled = enabled }
        if let list {
            let trimmed = list.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.list = trimmed.isEmpty ? Self.defaultListName : trimmed
            copy.listSpecifiedInYAML = true
        }
        if let includeCompleted { copy.includeCompleted = includeCompleted }
        if let syncOnMove { copy.syncOnMove = syncOnMove }
        if let syncFromReminders { copy.syncFromReminders = syncFromReminders }
        return copy
    }

    /// Inbox list title, trimmed. Empty after trim means no dedicated inbox.
    public var inboxListTitle: String? {
        let trimmed = list.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether sentinel column sync is active in either direction.
    public var columnSyncEnabled: Bool { syncOnMove || syncFromReminders }
}
