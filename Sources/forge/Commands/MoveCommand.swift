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
        let tagStore = FinderTagStore()

        guard let targetCol = findColumn(named: targetColumn, in: config) else {
            let valid = config.board.columns.map(\.name).joined(separator: ", ")
            let msg = "Unknown column '\(targetColumn)'. Valid columns: \(valid)"
            if json { ForgeJSONError.emit(msg, command: "move") }
            throw ValidationError(msg)
        }

        guard let matched = findProject(named: project, in: projects) else {
            let msg = "No project matching '\(project)'. Use 'forge board --list' to see all projects."
            if json { ForgeJSONError.emit(msg, command: "move") }
            throw ValidationError(msg)
        }

        if strict {
            switch KanbanTransitionPolicy.validate(from: matched.column, to: targetCol.name) {
            case .allowed:
                break
            case .rejected(let reason):
                if json { ForgeJSONError.emit(reason, command: "move") }
                throw ValidationError(reason)
            }
        }

        let forgeDir = ConfigLoader.forgeDirectory(for: config)

        try OmniFocusMoveSync.setFinderWorkflowColumn(
            path: matched.path,
            column: targetCol.name,
            config: config,
            tagStore: tagStore,
            forgeDir: forgeDir,
            folderName: matched.name,
            previousColumn: matched.column
        )

        let from = matched.column ?? "Untagged"
        var notes: [String] = []

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
            for match in matches {
                print("  - \(match.name)")
            }
            return nil
        }
        return nil
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
