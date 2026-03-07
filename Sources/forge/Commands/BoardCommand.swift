import ArgumentParser
import Foundation
import ForgeCore

struct BoardCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "board",
        abstract: "Display the kanban board."
    )

    @Flag(name: .shortAndLong, help: "Show as a compact list instead of columns.")
    var list = false

    @Option(name: .shortAndLong, help: "Filter to a specific column.")
    var column: String?

    mutating func run() throws {
        let config = try ConfigLoader.load()
        let scanner = WorkspaceScanner(config: config)
        var projects = try scanner.scanProjects()

        if let columnFilter = column {
            let lowerFilter = columnFilter.lowercased()
            projects = projects.filter {
                $0.column?.lowercased() == lowerFilter
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
