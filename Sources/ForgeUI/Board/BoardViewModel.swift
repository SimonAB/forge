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

    /// When non-nil and non-empty, only these meta tags appear in the board filter picker; otherwise all from config.
    private let filterMetaTags: [String]?

    /// Cached compiled regex for searchFilter; invalidated when searchFilter changes.
    private var searchRegexCache: (pattern: String, regex: NSRegularExpression?, literalLower: String?)?

    /// Cache for filtered projects and grouped columns to avoid recomputing on every body read.
    private var boardCache: (
        key: (projectCount: Int, columnFilter: String?, metaTagFilter: String?, pathSegmentFilter: String?, searchFilter: String?, assigneeFilter: String?),
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
    /// Respects columnFilter (single column) and metaTagFilter (projects must have that meta tag).
    public var groupedColumns: [(column: ColumnConfig, projects: [Project])] {
        let key: (Int, String?, String?, String?, String?, String?) = (
            projects.count,
            columnFilter,
            metaTagFilter,
            pathSegmentFilter,
            searchFilter,
            assigneeFilter
        )
        if let cache = boardCache,
           cache.key.projectCount == key.0,
           cache.key.columnFilter == key.1,
           cache.key.metaTagFilter == key.2,
           cache.key.pathSegmentFilter == key.3,
           cache.key.searchFilter == key.4,
           cache.key.assigneeFilter == key.5 {
            return cache.grouped
        }
        let filtered = computeFilteredProjects()
        let grouped = computeGroupedColumns(from: filtered)
        boardCache = ((key.0, key.1, key.2, key.3, key.4, key.5), filtered, grouped)
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

    /// Projects filtered by metaTagFilter, pathSegmentFilter, and searchFilter (regex) when set.
    private func computeFilteredProjects() -> [Project] {
        var list = projects
        if let segment = pathSegmentFilter, !segment.isEmpty {
            list = list.filter { $0.path.contains(segment) }
        }
        if let tag = metaTagFilter, !tag.isEmpty {
            list = list.filter { $0.metaTags.contains(tag) }
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
}
