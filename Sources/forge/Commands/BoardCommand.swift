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

    @Flag(name: .long, help: "Emit JSON (board config + projects with Radar metrics; for scripts and assistants).")
    var json = false

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

        if json {
            let now = Date()
            let rows: [BoardJSONProjectRow] = projects.map { p in
                let resolution = KanbanRadar.activityResolution(for: p)
                return BoardJSONProjectRow(
                    name: p.name,
                    path: p.path,
                    column: p.column,
                    workflowTag: p.workflowTag,
                    metaTags: p.metaTags,
                    assignees: p.assignees,
                    tags: p.tags,
                    radarBucket: KanbanRadar.bucket(for: p, now: now).rawValue,
                    daysSinceActivity: KanbanRadar.daysSinceActivity(for: p, now: now),
                    activityModificationDate: resolution.modificationDate,
                    activitySource: resolution.source
                )
            }
            let columnInfos = config.board.columns.map { c in
                BoardJSONColumn(name: c.name, tag: c.tag, colour: c.colour)
            }
            let tagAliases = config.board.tagAliases.map { BoardJSONTagAlias(from: $0.key, to: $0.value) }
                .sorted { $0.from < $1.from }
            let boardInfo = BoardJSONConfigSnapshot(
                columns: columnInfos,
                metaTags: config.board.metaTags,
                tagAliases: tagAliases
            )
            let payload = BoardJSONPayload(board: boardInfo, projects: rows)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            if let s = String(data: data, encoding: .utf8) {
                print(s)
            }
            return
        }

        let renderer = KanbanRenderer()

        if list {
            renderer.renderList(projects: projects, config: config)
        } else {
            renderer.render(projects: projects, config: config)
        }
    }
}

// MARK: - JSON payload

private struct BoardJSONPayload: Encodable {
    let board: BoardJSONConfigSnapshot
    let projects: [BoardJSONProjectRow]
}

private struct BoardJSONConfigSnapshot: Encodable {
    let columns: [BoardJSONColumn]
    let metaTags: [String]
    let tagAliases: [BoardJSONTagAlias]
}

private struct BoardJSONColumn: Encodable {
    let name: String
    let tag: String
    let colour: Int
}

private struct BoardJSONTagAlias: Encodable {
    let from: String
    let to: String
}

private struct BoardJSONProjectRow: Encodable {
    let name: String
    let path: String
    let column: String?
    let workflowTag: String?
    let metaTags: [String]
    let assignees: [String]
    let tags: [String]
    let radarBucket: String
    let daysSinceActivity: Double
    let activityModificationDate: Date
    let activitySource: String
}
