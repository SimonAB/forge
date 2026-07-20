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

// MARK: - Board filter preferences (UserDefaults)

/// UserDefaults key and helpers for which meta tags appear in the board's filter picker.
/// When unset or empty, all config meta tags are shown.
public enum BoardFilterPreferences {
    public static let userDefaultsKey = "ForgeBoardFilterMetaTags"

    /// Meta tag strings to show in the board filter. Nil or empty = show all from config.
    public static func loadEnabledMetaTags() -> [String]? {
        guard let a = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String], !a.isEmpty else {
            return nil
        }
        return a
    }

    /// Persist the selected meta tags for the board filter. Pass nil or empty to mean "all".
    public static func saveEnabledMetaTags(_ tags: [String]?) {
        if let tags = tags, !tags.isEmpty {
            UserDefaults.standard.set(tags, forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }
}

// MARK: - Default text editor preference (UserDefaults)

/// UserDefaults-backed default text editor for opening config and other files.
/// Use "default" or nil for system default (Open With). "Vim (in selected terminal)"
/// opens in the terminal selected in config with vim.
public enum EditorPreferences {
    public static let userDefaultsKey = "ForgePreferredTextEditor"
    public static let vimInTerminalDisplayTitle = "Vim (in selected terminal)"
    public static let legacyVimInTerminalDisplayTitle = "Vim (in default terminal)"

    /// Stored value: nil or "default" = system default; otherwise app name or "Vim (in selected terminal)".
    public static func loadPreferredEditor() -> String? {
        UserDefaults.standard.string(forKey: userDefaultsKey)
    }

    public static func savePreferredEditor(_ identifier: String?) {
        if let id = identifier, !id.isEmpty, id != "default" {
            UserDefaults.standard.set(id, forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }

    /// Display titles for the preferences picker. First = system default.
    public static let knownEditors = [
        "Default (system)",
        "Cursor",
        "Visual Studio Code",
        vimInTerminalDisplayTitle,
        "TextEdit",
        "Sublime Text",
    ]

    /// Stored value for the given display title. Used when saving selection.
    public static func identifier(forDisplayTitle title: String) -> String? {
        if title == "Default (system)" { return nil }
        if title == legacyVimInTerminalDisplayTitle { return vimInTerminalDisplayTitle }
        return title
    }

    /// Display title for the given stored value. Used when loading selection.
    public static func displayTitle(forIdentifier identifier: String?) -> String {
        guard let id = identifier, !id.isEmpty, id != "default" else { return "Default (system)" }
        if id == legacyVimInTerminalDisplayTitle { return vimInTerminalDisplayTitle }
        return knownEditors.contains(id) ? id : id
    }

    /// Returns true when the editor selection means "open with vim in selected terminal".
    public static func isVimInTerminal(_ identifier: String?) -> Bool {
        identifier == vimInTerminalDisplayTitle || identifier == legacyVimInTerminalDisplayTitle
    }
}

// MARK: - Terminal app options (config + preferences)

/// Known terminal application display titles for the preferences picker.
/// First item is automatic detection order in TerminalLauncher.
public enum TerminalPreferences {
    public static let knownTerminals = [
        "Auto (recommended)",
        "Ghostty",
        "kitty",
        "iTerm",
        "Warp",
        "cmux",
        "Terminal",
    ]

    /// Config value for a given picker display title.
    public static func configValue(forDisplayTitle title: String) -> String? {
        if title == "Auto (recommended)" { return "auto" }
        if title == "cmux.app" { return "cmux" } // backwards compatibility for older UI labels
        return title
    }

    /// Picker display title for a config value.
    public static func displayTitle(forConfigValue value: String?) -> String {
        guard let value = value, !value.isEmpty else { return "Auto (recommended)" }
        if value.lowercased() == "auto" { return "Auto (recommended)" }
        if value.lowercased() == "cmux" || value.lowercased() == "cmux.app" { return "cmux" }
        return knownTerminals.contains(value) ? value : value
    }
}

// MARK: - Calendar

/// Optional Calendar integration configuration (read-only).
public struct CalendarConfig: Codable, Sendable {
    /// When non-empty, `forge calendar` only reads these Calendar **titles** (exact match). Empty = all event calendars.
    public let include: [String]

    enum CodingKeys: String, CodingKey {
        case include
    }

    public init(include: [String] = []) {
        self.include = include
    }
}

// MARK: - Legacy GTD (kept for compatibility)

/// Legacy task-system configuration, retained to keep older configs and internal modules building.
/// The kanban-only CLI and UI do not rely on these fields.
public struct GTDConfig: Codable, Sendable {
    public let contexts: [String]
    public let remindersList: String
    public let calendarInclude: [String]

    enum CodingKeys: String, CodingKey {
        case contexts
        case remindersList = "reminders_list"
        case calendarInclude = "calendar_include"
    }

    public init(contexts: [String] = [], remindersList: String = "Forge", calendarInclude: [String] = []) {
        self.contexts = contexts
        self.remindersList = remindersList
        self.calendarInclude = calendarInclude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contexts = try container.decodeIfPresent([String].self, forKey: .contexts) ?? []
        remindersList = try container.decodeIfPresent(String.self, forKey: .remindersList) ?? "Forge"
        calendarInclude = try container.decodeIfPresent([String].self, forKey: .calendarInclude) ?? []
    }
}

/// Top-level forge configuration, loaded from config.yaml.
public struct ForgeConfig: Codable, Sendable {
    /// Paths under which Forge searches for project folders. At least one is expected.
    /// Decodes from `project_roots`; if absent, falls back to legacy `workspace` (single path).
    public let projectRoots: [String]
    public let board: BoardConfig
    public let calendar: CalendarConfig
    public let omnifocus: OmniFocusConfig
    public let gtd: GTDConfig
    public let workspaceTags: [String]
    public var projectAreas: [String: [String]]
    /// Preferred terminal application name (e.g. "Ghostty", "kitty", "iTerm", "Warp", "cmux", "Terminal").
    /// If nil or "auto", Forge detects the first available modern terminal.
    public let terminal: String?

    /// If set, only directories that have this Finder tag are treated as Forge projects.
    public let projectTag: String?

    /// How many directory levels under each `project_root` to search for projects.
    /// `1` = direct children only (default). `2` = also search inside untagged grouping folders.
    public let projectScanDepth: Int

    public enum DueConflictPolicy: String, Codable, Sendable, CaseIterable {
        case reminders
        case markdown
        case newest
    }
    public let dueConflictPolicy: DueConflictPolicy

    enum CodingKeys: String, CodingKey {
        case workspace
        case board, calendar, omnifocus
        case gtd
        case projectRoots = "project_roots"
        case workspaceTags = "workspace_tags"
        case projectAreas = "project_areas"
        case terminal
        case projectTag = "project_tag"
        case projectScanDepth = "project_scan_depth"
        case dueConflictPolicy = "due_conflict_policy"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectRoots, forKey: .projectRoots)
        try container.encode(board, forKey: .board)
        try container.encode(calendar, forKey: .calendar)
        try container.encode(omnifocus, forKey: .omnifocus)
        try container.encode(gtd, forKey: .gtd)
        try container.encode(workspaceTags, forKey: .workspaceTags)
        try container.encode(projectAreas, forKey: .projectAreas)
        try container.encodeIfPresent(terminal, forKey: .terminal)
        try container.encodeIfPresent(projectTag, forKey: .projectTag)
        try container.encode(projectScanDepth, forKey: .projectScanDepth)
        try container.encode(dueConflictPolicy, forKey: .dueConflictPolicy)
    }

    public init(
        projectRoots: [String],
        board: BoardConfig,
        calendar: CalendarConfig = CalendarConfig(),
        omnifocus: OmniFocusConfig = OmniFocusConfig(),
        gtd: GTDConfig = GTDConfig(),
        workspaceTags: [String] = ["work"],
        projectAreas: [String: [String]] = [:],
        terminal: String? = nil,
        projectTag: String? = nil,
        projectScanDepth: Int = 1,
        dueConflictPolicy: DueConflictPolicy = .newest
    ) {
        self.projectRoots = projectRoots
        self.board = board
        self.calendar = calendar
        self.omnifocus = omnifocus
        self.gtd = gtd
        self.workspaceTags = workspaceTags
        self.projectAreas = projectAreas
        self.terminal = terminal
        self.projectTag = projectTag
        self.projectScanDepth = max(1, projectScanDepth)
        self.dueConflictPolicy = dueConflictPolicy
    }

    /// Primary path (first project root). Used for Forge dir fallback and working directory.
    public var resolvedWorkspacePath: String {
        resolvedProjectRoots.first ?? ""
    }

    /// Paths to scan for projects. Expands `~`. Depth is controlled by `projectScanDepth`.
    public var resolvedProjectRoots: [String] {
        projectRoots.map { ($0 as NSString).expandingTildeInPath }
    }

    /// Effective scan depth (at least 1).
    public var resolvedProjectScanDepth: Int {
        max(1, projectScanDepth)
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
        var decodedCalendar = (try? container.decode(CalendarConfig.self, forKey: .calendar)) ?? CalendarConfig()
        omnifocus = (try? container.decode(OmniFocusConfig.self, forKey: .omnifocus)) ?? OmniFocusConfig()
        gtd = (try? container.decode(GTDConfig.self, forKey: .gtd)) ?? GTDConfig()
        let roots = try container.decodeIfPresent([String].self, forKey: .projectRoots)
        let legacyWorkspace = try container.decodeIfPresent(String.self, forKey: .workspace)
        if let r = roots, !r.isEmpty {
            projectRoots = r
        } else if let w = legacyWorkspace {
            projectRoots = [w]
        } else {
            projectRoots = []
        }
        terminal = try container.decodeIfPresent(String.self, forKey: .terminal)
        projectTag = try container.decodeIfPresent(String.self, forKey: .projectTag)
        projectScanDepth = max(1, try container.decodeIfPresent(Int.self, forKey: .projectScanDepth) ?? 1)
        workspaceTags = try container.decodeIfPresent([String].self, forKey: .workspaceTags) ?? ["work"]
        projectAreas = try container.decodeIfPresent([String: [String]].self, forKey: .projectAreas) ?? [:]
        dueConflictPolicy = try container.decodeIfPresent(DueConflictPolicy.self, forKey: .dueConflictPolicy) ?? .newest

        // Backwards compatibility: allow reading Calendar allowlist from legacy `gtd.calendar_include`.
        if decodedCalendar.include.isEmpty, !gtd.calendarInclude.isEmpty {
            decodedCalendar = CalendarConfig(include: gtd.calendarInclude)
        }

        calendar = decodedCalendar
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
                    ColumnConfig(name: "Watch", tag: "Watch 👁️", colour: 2),  // Green
                    ColumnConfig(name: "Coding", tag: "Coding 🤖", colour: 5), // Yellow
                    ColumnConfig(name: "Write", tag: "Write ✒️", colour: 6),   // Orange
                    ColumnConfig(name: "Review", tag: "Review 🖍️", colour: 7),  // Red
                    ColumnConfig(name: "Shipped", tag: "Shipped 🚀", colour: 3), // Purple
                    ColumnConfig(name: "Paused", tag: "Paused ⏸️", colour: 1),  // Grey
                ],
                metaTags: ["URGENT ⚠️", "Collab 🤝", "Student 🎓"],
                tagAliases: [
                    "Active": "Watch 👁️",
                    "active 🚧": "Watch 👁️",
                    "watch 👁️": "Watch 👁️",
                    "Plan ☼": "Plan 📐",
                    "Plan 💡": "Plan 📐",
                    "Review 📝": "Review 🖍️",
                    "Edit 🖍️": "Review 🖍️",
                    "paused ⏸️": "Paused ⏸️",
                    "Paused ⏸": "Paused ⏸️",
                    "Paused ⏸︎": "Paused ⏸️",  // text-style variation (U+FE0E)
                    "Analyse 🔍": "Coding 🤖",
                    "3. Analyse 🔍": "Coding 🤖",
                    "4. Write ✒️": "Write ✒️",
                ]
            ),
            calendar: CalendarConfig(include: []),
            terminal: "auto",
            projectTag: "🔥 Forge",
            dueConflictPolicy: .newest
        )
    }
}
