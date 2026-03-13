import Foundation
import SwiftUI
import ForgeCore

/// View model for the Kanban board. Loads projects via injected closures and performs moves
/// by calling a move closure, so the same UI can run on macOS (Finder tags) or iOS (attrs/sidecar).
@MainActor
@Observable
public final class BoardViewModel {

    public let config: ForgeConfig
    public private(set) var projects: [Project] = []
    public private(set) var error: String?
    public private(set) var isLoading = false

    /// When set, only projects in this column are shown. Nil = show all columns.
    public var columnFilter: String? = nil
    
    /// When set, only projects that have this meta tag (context/people) are shown. Nil = show all.
    public var metaTagFilter: String? = nil
    
    /// When set, only projects whose path contains this domain segment (e.g. "Work", "Home", "Sanctum") are shown. Nil = show all.
    public var pathSegmentFilter: String? = nil

    /// When non-empty, only projects matching this regex (against name, path, tags) are shown. Case-insensitive.
    public var searchFilter: String? = nil

    /// When set, only projects that have this assignee (derived from #Person Finder tags) are shown. Nil = show all.
    public var assigneeFilter: String? = nil

    /// When set, only projects whose "radar bucket" matches this key are shown. Nil = show all radar levels.
    /// Radar buckets combine urgency (e.g. URGENT meta tag) and neglect (based on last modification time).
    public var radarFilterKey: String? = nil
    
    /// When non-nil and non-empty, only these meta tags appear in the board filter picker; otherwise all from config.
    private let filterMetaTags: [String]?

    /// Cached compiled regex for searchFilter; invalidated when searchFilter changes.
    private var searchRegexCache: (pattern: String, regex: NSRegularExpression?, literalLower: String?)?

    /// Cache for filtered projects and grouped columns to avoid recomputing on every body read.
    private var boardCache: (
        key: (projectCount: Int, columnFilter: String?, metaTagFilter: String?, pathSegmentFilter: String?, searchFilter: String?, assigneeFilter: String?, radarFilterKey: String?),
        filtered: [Project],
        grouped: [(column: ColumnConfig, projects: [Project])]
    )?

    private let fetchProjects: @Sendable () async throws -> [Project]
    private let moveProject: @Sendable (Project, ColumnConfig) throws -> Void

    public init(
        config: ForgeConfig,
        fetchProjects: @escaping @Sendable () async throws -> [Project],
        moveProject: @escaping @Sendable (Project, ColumnConfig) throws -> Void,
        filterMetaTags: [String]? = nil
    ) {
        self.config = config
        self.fetchProjects = fetchProjects
        self.moveProject = moveProject
        self.filterMetaTags = filterMetaTags
    }

    /// Meta tags to show in the board filter picker. Subset of config when preference is set; otherwise all.
    public var metaTagsForFilter: [String] {
        let all = config.board.metaTags
        guard let selected = filterMetaTags, !selected.isEmpty else { return all }
        return all.filter { selected.contains($0) }
    }

    /// All distinct assignees present in the current project list, sorted for stable display.
    public var assigneesForFilter: [String] {
        let values = projects.flatMap { $0.assignees }
        let unique = Set(values)
        return unique.sorted()
    }

    /// Load projects from the injected fetch closure and update state on the main actor.
    public func load() {
        isLoading = true
        error = nil
        Task {
            do {
                let result = try await fetchProjects()
                await MainActor.run {
                    self.projects = result
                    self.boardCache = nil
                    self.isLoading = false
                    self.error = nil
                }
            } catch {
                await MainActor.run {
                    self.projects = []
                    self.boardCache = nil
                    self.isLoading = false
                    self.error = error.localizedDescription
                }
            }
        }
    }

    /// Move a project to a target column by calling the injected move closure, then refresh.
    public func move(project: Project, toColumn column: ColumnConfig) {
        do {
            try moveProject(project, column)
            load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Re-run the fetch to refresh the project list.
    public func refresh() {
        load()
    }

    /// Grouped columns: config columns in order plus "Untagged" if any project has no column.
    /// Respects columnFilter (single column) and filters (meta tag, radar, domain, search, assignee).
    public var groupedColumns: [(column: ColumnConfig, projects: [Project])] {
        let key: (Int, String?, String?, String?, String?, String?, String?) = (
            projects.count,
            columnFilter,
            metaTagFilter,
            pathSegmentFilter,
            searchFilter,
            assigneeFilter,
            radarFilterKey
        )
        if let cache = boardCache,
           cache.key.projectCount == key.0,
           cache.key.columnFilter == key.1,
           cache.key.metaTagFilter == key.2,
           cache.key.pathSegmentFilter == key.3,
           cache.key.searchFilter == key.4,
           cache.key.assigneeFilter == key.5,
           cache.key.radarFilterKey == key.6 {
            return cache.grouped
        }
        let filtered = computeFilteredProjects()
        let grouped = computeGroupedColumns(from: filtered)
        boardCache = ((key.0, key.1, key.2, key.3, key.4, key.5, key.6), filtered, grouped)
        return grouped
    }

    private func computeGroupedColumns(from filtered: [Project]) -> [(column: ColumnConfig, projects: [Project])] {
        var result: [(column: ColumnConfig, projects: [Project])] = []
        if let name = columnFilter, !name.isEmpty {
            if name == "Untagged" {
                let untaggedCol = ColumnConfig(name: "Untagged", tag: "", colour: 0)
                result.append((column: untaggedCol, projects: filtered.filter { $0.column == nil }))
            } else if let col = config.board.columns.first(where: { $0.name == name }) {
                result.append((column: col, projects: filtered.filter { $0.column == col.name }))
            } else {
                return allGroupedColumns(from: filtered)
            }
        } else {
            return allGroupedColumns(from: filtered)
        }
        return result
    }

    private func allGroupedColumns(from list: [Project]) -> [(column: ColumnConfig, projects: [Project])] {
        var result: [(column: ColumnConfig, projects: [Project])] = []
        for col in config.board.columns {
            result.append((column: col, projects: list.filter { $0.column == col.name }))
        }
        let untagged = list.filter { $0.column == nil }
        if !untagged.isEmpty {
            result.append((column: ColumnConfig(name: "Untagged", tag: "", colour: 0), projects: untagged))
        }
        return result
    }

    /// Projects filtered by metaTagFilter, radarFilterKey, pathSegmentFilter, assigneeFilter, and searchFilter (regex) when set.
    private func computeFilteredProjects() -> [Project] {
        var list = projects
        if let segment = pathSegmentFilter, !segment.isEmpty {
            list = list.filter { $0.path.contains(segment) }
        }
        if let tag = metaTagFilter, !tag.isEmpty {
            list = list.filter { $0.metaTags.contains(tag) }
        }
        if let radarKey = radarFilterKey, !radarKey.isEmpty {
            let now = Date()
            list = list.filter { radarBucket(for: $0, now: now) == radarKey }
        }
        if let assignee = assigneeFilter, !assignee.isEmpty {
            list = list.filter { $0.assignees.contains(assignee) }
        }
        if let query = searchFilter, !query.isEmpty {
            let (regex, literalLower) = compiledSearchRegex(for: query)
            list = list.filter { project in
                matchesSearch(project: project, regex: regex, literalLower: literalLower)
            }
        }
        return list
    }

    /// Compile search pattern once per searchFilter; returns (regex, literalFallback) for use in filter.
    private func compiledSearchRegex(for query: String) -> (NSRegularExpression?, String?) {
        if let cached = searchRegexCache, cached.pattern == query {
            return (cached.regex, cached.literalLower)
        }
        let regex: NSRegularExpression?
        let literalLower: String?
        do {
            regex = try NSRegularExpression(pattern: query, options: .caseInsensitive)
            literalLower = nil
        } catch {
            regex = nil
            literalLower = query.lowercased()
        }
        searchRegexCache = (query, regex, literalLower)
        return (regex, literalLower)
    }

    /// Returns true if the project matches the search (using pre-compiled regex or literal).
    private func matchesSearch(project: Project, regex: NSRegularExpression?, literalLower: String?) -> Bool {
        if let lower = literalLower {
            return project.name.lowercased().contains(lower)
                || project.path.lowercased().contains(lower)
                || project.metaTags.contains { $0.lowercased().contains(lower) }
                || project.tags.contains { $0.lowercased().contains(lower) }
        }
        guard let regex = regex else { return false }
        func match(_ s: String) -> Bool {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            return regex.firstMatch(in: s, range: range) != nil
        }
        return match(project.name) || match(project.path)
            || project.metaTags.contains { match($0) }
            || project.tags.contains { match($0) }
    }
    /// Compute a simple "radar bucket" for a project combining urgency and neglect.
    ///
    /// - Parameters:
    ///   - project: Project to score.
    ///   - now: Current time (default is `Date()`; injected for testability).
    /// - Returns: A string key representing the radar bucket: "calm", "watch", or "heat".
    private func radarBucket(for project: Project, now: Date) -> String {
        // Treat any meta tag whose base label starts with "URGENT" (e.g. "URGENT ⚠️") as urgent.
        let hasUrgentTag = project.metaTags.contains { tag in
            tag.uppercased().hasPrefix("URGENT")
        }
        
        let fm = FileManager.default
        let modificationDate: Date
        // Prefer the TASKS.md file inside the project directory as the activity signal.
        let tasksPath = (project.path as NSString).appendingPathComponent("TASKS.md")
        if let attrs = try? fm.attributesOfItem(atPath: tasksPath),
           let mtime = attrs[.modificationDate] as? Date {
            modificationDate = mtime
        } else if let attrs = try? fm.attributesOfItem(atPath: project.path),
                  let mtime = attrs[.modificationDate] as? Date {
            // Fallback: use the project folder itself if TASKS.md is missing.
            modificationDate = mtime
        } else {
            modificationDate = .distantPast
        }
        
        let secondsSinceChange = now.timeIntervalSince(modificationDate)
        let daysSinceChange = secondsSinceChange / (60 * 60 * 24)
        
        // Primary heat: explicitly urgent projects, or very neglected ones.
        if hasUrgentTag || daysSinceChange >= 21 {
            return "heat"
        }
        
        // Watch list: projects that have not moved for a week or more.
        if daysSinceChange >= 7 {
            return "watch"
        }
        
        // Recently-touched, non-urgent projects.
        return "calm"
    }
}
