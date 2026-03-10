import ArgumentParser
import Foundation
import ForgeCore

struct BoardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "board",
        abstract: "Display the kanban board."
    )

    @Flag(name: .shortAndLong, help: "Show as a compact list instead of columns.")
    var list = false

    @Option(name: .shortAndLong, help: "Filter to a specific column.")
    var column: String?

    @Option(name: .shortAndLong, help: "Filter to projects assigned to a person (matches #Person tags, case-insensitive).")
    var assignee: String?

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let scanner = WorkspaceScanner(config: config)
        var projects = try await scanner.scanProjects()

        if let columnFilter = column {
            let lowerFilter = columnFilter.lowercased()
            projects = projects.filter {
                $0.column?.lowercased() == lowerFilter
            }
        }

        if let assigneeFilter = assignee, !assigneeFilter.isEmpty {
            let needle = assigneeFilter.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
            projects = projects.filter { project in
                project.assignees.contains { $0.lowercased() == needle }
            }
        }

        let renderer = KanbanRenderer()

        if list {
            renderer.renderList(projects: projects, config: config)
        } else {
            renderer.render(projects: projects, config: config)
        }
    }
}
