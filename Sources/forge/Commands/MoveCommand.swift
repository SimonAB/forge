import ArgumentParser
import Foundation
import ForgeCore

struct MoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move a project to a different kanban column."
    )

    @Argument(help: "Project directory name (or a unique substring).")
    var project: String

    @Argument(help: "Target column name (e.g. Active, Analyse, Write, Review, Shipped, Paused, Plan).")
    var targetColumn: String

    mutating func run() throws {
        let config = try ConfigLoader.load()
        let scanner = WorkspaceScanner(config: config)
        let projects = try scanner.scanProjects()
        let tagStore = FinderTagStore()

        guard let targetCol = findColumn(named: targetColumn, in: config) else {
            let valid = config.board.columns.map(\.name).joined(separator: ", ")
            throw ValidationError("Unknown column '\(targetColumn)'. Valid columns: \(valid)")
        }

        guard let matched = findProject(named: project, in: projects) else {
            throw ValidationError(
                "No project matching '\(project)'. Use 'forge board --list' to see all projects."
            )
        }

        if let existingWorkflowTag = matched.workflowTag {
            try tagStore.removeTag(existingWorkflowTag, at: matched.path)
        }

        try tagStore.addTag(targetCol.tag, at: matched.path)

        let from = matched.column ?? "Untagged"
        print("\(matched.name): \(from) → \(targetCol.name)")
    }

    private func findColumn(named name: String, in config: ForgeConfig) -> ColumnConfig? {
        let lower = name.lowercased()
        return config.board.columns.first { $0.name.lowercased() == lower }
            ?? config.board.columns.first { $0.name.lowercased().hasPrefix(lower) }
    }

    private func findProject(named query: String, in projects: [Project]) -> Project? {
        let lower = query.lowercased()
        if let exact = projects.first(where: { $0.name.lowercased() == lower }) {
            return exact
        }
        let matches = projects.filter { $0.name.lowercased().contains(lower) }
        if matches.count == 1 {
            return matches.first
        }
        if matches.count > 1 {
            print("Ambiguous match for '\(query)':")
            for m in matches { print("  • \(m.name)") }
        }
        return nil
    }
}
