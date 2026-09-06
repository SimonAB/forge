import ArgumentParser
import Foundation
import ForgeCore

struct MoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move a project to a different kanban column."
    )

    @Argument(help: "Project directory name (or a unique substring).")
    var project: String

    @Argument(help: "Target column name (e.g. Watch, Coding, Write, Review, Shipped, Paused, Plan).")
    var targetColumn: String

    @Flag(
        name: .long,
        help: "Enforce left-to-right workflow rules (no multi-column jumps; Shipped stays Shipped)."
    )
    var strict: Bool = false

    @Flag(
        name: .long,
        help: "With OmniFocus or Reminders sync_on_move, proceed even when doctor reports drift."
    )
    var force: Bool = false

    @Flag(name: .long, help: "Emit JSON result.")
    var json: Bool = false

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()

        guard let targetCol = findColumn(named: targetColumn, in: config) else {
            let valid = config.board.columns.map(\.name).joined(separator: ", ")
            let msg = "Unknown column '\(targetColumn)'. Valid columns: \(valid)"
            try ForgeJSONError.throwDomainFailure(msg, command: "move", json: json)
        }

        let matched: Project
        switch matchProject(named: project, in: projects) {
        case .found(let project):
            matched = project
        case .none:
            let msg = "No project matching '\(project)'. Use 'forge board --list' to see all projects."
            try ForgeJSONError.throwDomainFailure(msg, command: "move", json: json)
        case .ambiguous(let candidates):
            if !json {
                printAmbiguousProjectMatch(query: project, candidates: candidates)
            }
            let msg = "Ambiguous project '\(project)'. Refine the name."
            try ForgeJSONError.throwDomainFailure(
                msg, command: "move", json: json, candidates: candidates
            )
        }

        if strict {
            switch KanbanTransitionPolicy.validate(from: matched.column, to: targetCol.name) {
            case .allowed:
                break
            case .rejected(let reason):
                try ForgeJSONError.throwDomainFailure(reason, command: "move", json: json)
            }
        }

        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let tagStore = PlatformTagStore.makeDefault()

        try KanbanNexus.setWorkflowColumn(
            path: matched.path,
            column: targetCol.name,
            config: config,
            tagStore: tagStore,
            forgeDir: forgeDir,
            folderName: matched.name,
            previousColumn: matched.column,
            source: KanbanNexus.Source.forgeMove
        )

        let from = matched.column ?? "Untagged"
        var notes: [String] = []

        if config.nexus.spColumnMirror {
            let mirrorNote = SuperProductivityColumnMirror.mirrorColumn(
                projectName: matched.name,
                column: targetCol,
                config: config,
                forgeDir: forgeDir
            )
            if let mirrorNote { notes.append(mirrorNote) }
        }

        let outcome = OmniFocusMoveSync.mirrorFinderColumn(
            config: config,
            forgeDir: forgeDir,
            projects: projects,
            project: matched,
            column: targetCol.name,
            force: force
        )
        switch outcome {
        case .disabled:
            break
        case .skipped(let reason):
            notes.append("OmniFocus sync skipped: \(reason)")
        case .synced(let count, let alias, let missing, let projectStatusNote):
            var msg = "OmniFocus sync: \(config.omnifocus.columnTagLabel(for: targetCol.name)) on \(count) task(s)."
            if let alias { msg += " alias \(alias)" }
            if !missing.isEmpty { msg += " (missing alias: \(missing.joined(separator: ", ")))" }
            notes.append(msg)
            if let projectStatusNote {
                notes.append(projectStatusNote)
            }
        }

        if config.reminders.enabled {
            do {
                guard let inv = try RemindersService(config: config).loadEligibleSnapshot(forgeDir: forgeDir) else {
                    notes.append("Reminders sync skipped: no eligible snapshot (run forge reminders refresh).")
                    emitResult(project: matched.name, path: matched.path, from: from, to: targetCol.name, notes: notes)
                    return
                }
                let rem = await RemindersMoveSync.afterFinderColumnChange(
                    config: config,
                    project: matched,
                    column: targetCol.name,
                    inventory: inv,
                    writer: RemindersWriter(),
                    force: force
                )
                switch rem.colour {
                case .disabled: break
                case .skipped(let reason): notes.append("Reminders list colour skipped: \(reason)")
                case .synced(let listTitle, let column): notes.append("Reminders list colour: \(listTitle) → \(column).")
                }
                switch rem.sentinel {
                case .disabled: break
                case .skipped(let reason): notes.append("Reminders sentinel skipped: \(reason)")
                case .synced(let listTitle, let column): notes.append("Reminders sentinel: \(column) on \(listTitle).")
                }
                switch rem.priority {
                case .disabled: break
                case .skipped(let reason): notes.append("Reminders sentinel priority skipped: \(reason)")
                case .synced(let listTitle, let label): notes.append("Reminders sentinel priority: \(label) on \(listTitle).")
                }
            } catch {
                notes.append("Reminders sync skipped: \(error.localizedDescription)")
            }
        }

        emitResult(project: matched.name, path: matched.path, from: from, to: targetCol.name, notes: notes)
    }

    private func emitResult(project: String, path: String, from: String, to: String, notes: [String]) {
        if json {
            let payload = MoveResultPayload(
                project: project, path: path,
                fromColumn: from, toColumn: to,
                notes: notes
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(payload),
               let s = String(data: data, encoding: .utf8) {
                print(s)
            }
        } else {
            print("\(project): \(from) → \(to)")
            for note in notes { print(note) }
        }
    }

    // MARK: - Lookup helpers

    private func findColumn(named name: String, in config: ForgeConfig) -> ColumnConfig? {
        let lower = name.lowercased()
        return config.board.columns.first { $0.name.lowercased() == lower }
            ?? config.board.columns.first { $0.name.lowercased().hasPrefix(lower) }
    }
}

// MARK: - JSON payload

private struct MoveResultPayload: Encodable {
    let project: String
    let path: String
    let fromColumn: String
    let toColumn: String
    let notes: [String]
}
