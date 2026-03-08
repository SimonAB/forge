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

    /// When non-nil and non-empty, only these meta tags appear in the board filter picker; otherwise all from config.
    private let filterMetaTags: [String]?

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

    /// Load projects from the injected fetch closure and update state on the main actor.
    public func load() {
        isLoading = true
        error = nil
        Task {
            do {
                let result = try await fetchProjects()
                await MainActor.run {
                    self.projects = result
                    self.isLoading = false
                    self.error = nil
                }
            } catch {
                await MainActor.run {
                    self.projects = []
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
        let filtered = filteredProjects
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

    /// Projects filtered by metaTagFilter (when set).
    private var filteredProjects: [Project] {
        guard let tag = metaTagFilter, !tag.isEmpty else { return projects }
        return projects.filter { $0.metaTags.contains(tag) }
    }
}
