import Foundation
import Yams

/// Column definition mapping a kanban column name to its Finder tag and colour.
public struct ColumnConfig: Codable, Sendable {
    public let name: String
    public let tag: String
    public let colour: Int

    public init(name: String, tag: String, colour: Int) {
        self.name = name
        self.tag = tag
        self.colour = colour
    }
}

/// Board configuration: columns, meta tags, and tag aliases for cleanup.
public struct BoardConfig: Codable, Sendable {
    public let columns: [ColumnConfig]
    public let metaTags: [String]
    public let tagAliases: [String: String]

    enum CodingKeys: String, CodingKey {
        case columns
        case metaTags = "meta_tags"
        case tagAliases = "tag_aliases"
    }

    public init(columns: [ColumnConfig], metaTags: [String], tagAliases: [String: String]) {
        self.columns = columns
        self.metaTags = metaTags
        self.tagAliases = tagAliases
    }
}

/// GTD-specific configuration.
public struct GTDConfig: Codable, Sendable {
    public let contexts: [String]
    public let remindersList: String
    public let calendarName: String

    enum CodingKeys: String, CodingKey {
        case contexts
        case remindersList = "reminders_list"
        case calendarName = "calendar_name"
    }

    public init(contexts: [String], remindersList: String, calendarName: String) {
        self.contexts = contexts
        self.remindersList = remindersList
        self.calendarName = calendarName
    }
}

/// Top-level forge configuration, loaded from config.yaml.
public struct ForgeConfig: Codable, Sendable {
    /// Paths whose direct children are Forge projects. At least one is expected.
    /// Decodes from `project_roots`; if absent, falls back to legacy `workspace` (single path).
    public let projectRoots: [String]
    public let board: BoardConfig
    public let gtd: GTDConfig
    /// Focus tags that include workspace projects (e.g. `["work"]`).
    /// When a focus session matches one of these tags, project tasks are shown.
    public let workspaceTags: [String]
    /// Maps area IDs to lists of project directory names for the rollup view.
    /// E.g. `{ "research": ["Lepto", "Deer-stress"] }`.
    /// Absent from config means no rollups are generated.
    public var projectAreas: [String: [String]]
    /// Preferred terminal application name (e.g. "Ghostty", "kitty", "iTerm", "Warp", "Terminal").
    /// If nil or "auto", Forge detects the first available modern terminal.
    public let terminal: String?

    /// If set, only directories that have this Finder tag are treated as Forge projects.
    public let projectTag: String?

    enum CodingKeys: String, CodingKey {
        case workspace
        case board, gtd
        case projectRoots = "project_roots"
        case workspaceTags = "workspace_tags"
        case projectAreas = "project_areas"
        case terminal
        case projectTag = "project_tag"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectRoots, forKey: .projectRoots)
        try container.encode(board, forKey: .board)
        try container.encode(gtd, forKey: .gtd)
        try container.encode(workspaceTags, forKey: .workspaceTags)
        try container.encode(projectAreas, forKey: .projectAreas)
        try container.encodeIfPresent(terminal, forKey: .terminal)
        try container.encodeIfPresent(projectTag, forKey: .projectTag)
    }

    public init(
        projectRoots: [String],
        board: BoardConfig,
        gtd: GTDConfig,
        workspaceTags: [String] = ["work"],
        projectAreas: [String: [String]] = [:],
        terminal: String? = nil,
        projectTag: String? = nil
    ) {
        self.projectRoots = projectRoots
        self.board = board
        self.gtd = gtd
        self.workspaceTags = workspaceTags
        self.projectAreas = projectAreas
        self.terminal = terminal
        self.projectTag = projectTag
    }

    /// Primary path (first project root). Used for Forge dir fallback and working directory.
    public var resolvedWorkspacePath: String {
        resolvedProjectRoots.first ?? ""
    }

    /// Paths to scan for projects (direct children = projects). Expands `~`.
    public var resolvedProjectRoots: [String] {
        projectRoots.map { ($0 as NSString).expandingTildeInPath }
    }

    /// Look up the column for a given Finder tag, resolving aliases first.
    public func column(forTag tag: String) -> ColumnConfig? {
        let resolved = board.tagAliases[tag] ?? tag
        return board.columns.first { $0.tag == resolved }
    }

    /// All workflow tags (both canonical and aliases).
    public var allWorkflowTags: Set<String> {
        var tags = Set(board.columns.map(\.tag))
        tags.formUnion(board.tagAliases.keys)
        return tags
    }
}

// MARK: - Loading and Saving

extension ForgeConfig {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        board = try container.decode(BoardConfig.self, forKey: .board)
        gtd = try container.decode(GTDConfig.self, forKey: .gtd)
        let roots = try container.decodeIfPresent([String].self, forKey: .projectRoots)
        let legacyWorkspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        if let r = roots, !r.isEmpty {
            projectRoots = r
        } else if let w = legacyWorkspace {
            projectRoots = [w]
        } else {
            projectRoots = []
        }
        workspaceTags = try container.decodeIfPresent([String].self, forKey: .workspaceTags) ?? ["work"]
        projectAreas = try container.decodeIfPresent([String: [String]].self, forKey: .projectAreas) ?? [:]
        terminal = try container.decodeIfPresent(String.self, forKey: .terminal)
        projectTag = try container.decodeIfPresent(String.self, forKey: .projectTag)
    }

    /// Load configuration from a YAML file at the given path.
    public static func load(from path: String) throws -> ForgeConfig {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoder = YAMLDecoder()
        return try decoder.decode(ForgeConfig.self, from: data)
    }

    /// Write this configuration to a YAML file at the given path.
    public func save(to path: String) throws {
        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(self)
        try yamlString.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// The default configuration matching the user's existing tag vocabulary.
    public static func defaultConfig(projectRoots: [String]) -> ForgeConfig {
        ForgeConfig(
            projectRoots: projectRoots,
            board: BoardConfig(

                columns: [
                    ColumnConfig(name: "Plan", tag: "Plan 📐", colour: 4),    // Blue
                    ColumnConfig(name: "Active", tag: "Active 🚧", colour: 2),  // Green
                    ColumnConfig(name: "Analyse", tag: "Analyse 🔍", colour: 5), // Yellow
                    ColumnConfig(name: "Write", tag: "Write ✒️", colour: 6),   // Orange
                    ColumnConfig(name: "Review", tag: "Review 🖍️", colour: 7),  // Red
                    ColumnConfig(name: "Shipped", tag: "Shipped 🚀", colour: 3), // Purple
                    ColumnConfig(name: "Paused", tag: "Paused ⏸️", colour: 1),  // Grey
                ],
                metaTags: ["Mine ⚒️", "Collab 🤝", "Student 🎓"],
                tagAliases: [
                    "active 🚧": "Active 🚧",
                    "Plan ☼": "Plan 📐",
                    "Plan 💡": "Plan 📐",
                    "Review 📝": "Review 🖍️",
                    "Edit 🖍️": "Review 🖍️",
                    "paused ⏸️": "Paused ⏸️",
                    "Paused ⏸": "Paused ⏸️",
                    "Paused ⏸︎": "Paused ⏸️",  // text-style variation (U+FE0E)
                    "3. Analyse 🔍": "Analyse 🔍",
                    "4. Write ✒️": "Write ✒️",
                ]
            ),
            gtd: GTDConfig(
                contexts: [
                    "office", "lab", "campus", "home", "errands", "shopping",
                    "writing", "review", "analysis", "planning", "deep-work",
                    "low-energy", "email", "slack", "calls", "computer",
                    "reading", "watching", "anywhere", "agenda",
                ],
                remindersList: "Forge",
                calendarName: "Forge"
            ),
            workspaceTags: ["work"],
            terminal: "auto",
            projectTag: "🔥 Forge"
        )
    }
}
