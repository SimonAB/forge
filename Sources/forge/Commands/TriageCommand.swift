import ArgumentParser
import Foundation
import ForgeCore

/// Non-interactive inbox triage for LLM-driven workflows.
///
/// Moves a task by ID out of the inbox (or any task file) into a project, area file, someday list, or completes/trashes it.
/// Optionally updates task metadata (due/defer/context/etc.) while filing.
struct TriageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "triage",
        abstract: "Triage a task by ID (move, defer, delegate, someday, done, trash)."
    )

    enum Destination: String, ExpressibleByArgument, CaseIterable {
        case project
        case area
        case inbox
        case someday
        case done
        case trash
    }

    @Argument(help: "Task ID (the 6-character code from <!-- id:xxxxxx -->).")
    var taskID: String

    @Option(name: .long, help: "Where to send the task: project, area, inbox, someday, done, or trash.")
    var to: Destination

    @Option(name: .long, help: "Project directory name (or unique substring). Required when --to project.")
    var project: String?

    @Option(name: .long, help: "Area file name (e.g. Admin). Required when --to area. Creates Forge/tasks/<name>.md if missing.")
    var area: String?

    @Option(name: .long, help: "Target section when filing to a file: next or waiting. Default: next.")
    var section: SectionChoice = .next

    enum SectionChoice: String, ExpressibleByArgument, CaseIterable {
        case next
        case waiting
    }

    // Metadata updates (applied before filing).
    @Option(name: .long, help: "Set @ctx(value).")
    var ctx: String?

    @Option(name: .long, help: "Set @energy(value).")
    var energy: String?

    @Option(name: .long, help: "Set @waiting(value) and move to Waiting For section (unless --section next overrides).")
    var waitingOn: String?

    @Option(name: .long, help: "Set @due(YYYY-MM-DD or YYYY-MM-DD HH:mm).")
    var due: String?

    @Option(name: .long, help: "Set @defer(YYYY-MM-DD).")
    var `defer`: String?

    @Flag(name: .long, help: "Also run `forge sync` after triage completes.")
    var syncAfter = false

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let markdownIO = MarkdownIO()

        let location = try await locateTask(taskID: taskID, config: config, forgeDir: forgeDir)
        guard let source = location else {
            print("Task \(taskID) not found in inbox, areas, or projects.")
            return
        }

        guard var task = try markdownIO.findTask(withID: taskID, inFileAt: source.path, projectName: source.projectName) else {
            print("Task \(taskID) not found in \(source.path).")
            return
        }

        applyMetadataEdits(to: &task)

        // Compute target file path (or completion/trash).
        switch to {
        case .done:
            if try markdownIO.completeTask(withID: taskID, inFileAt: source.path) {
                print("✓ Completed \(taskID)")
            } else {
                print("Task \(taskID) not found in \(source.path).")
            }
            try await runSyncIfRequested(syncAfter, forgeDir: forgeDir)
            return

        case .trash:
            if try markdownIO.removeTask(withID: taskID, inFileAt: source.path) {
                print("✓ Trashed \(taskID)")
            } else {
                print("Task \(taskID) not found in \(source.path).")
            }
            try await runSyncIfRequested(syncAfter, forgeDir: forgeDir)
            return

        case .someday:
            let target = ConfigLoader.somedayPath(forgeDir: forgeDir)
            try fileTask(task, from: source.path, to: target, markdownIO: markdownIO)
            print("✓ Filed \(taskID) → Someday/Maybe")
            try await runSyncIfRequested(syncAfter, forgeDir: forgeDir)
            return

        case .inbox:
            let target = ConfigLoader.inboxPath(forgeDir: forgeDir)
            try fileTask(task, from: source.path, to: target, markdownIO: markdownIO)
            print("✓ Filed \(taskID) → Inbox")
            try await runSyncIfRequested(syncAfter, forgeDir: forgeDir)
            return

        case .area:
            guard let areaName = area, !areaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError("--area is required when --to area")
            }
            let target = try ensureAreaFile(named: areaName, forgeDir: forgeDir)
            try fileTask(task, from: source.path, to: target, markdownIO: markdownIO)
            print("✓ Filed \(taskID) → Area \(areaName)")
            try await runSyncIfRequested(syncAfter, forgeDir: forgeDir)
            return

        case .project:
            guard let projectQuery = project, !projectQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError("--project is required when --to project")
            }
            let scanner = WorkspaceScanner(config: config)
            let projects = try await scanner.scanProjects()
            guard let matched = findProject(named: projectQuery, in: projects) else {
                throw ValidationError("No project matching '\(projectQuery)'. Use 'forge board --list' to see all projects.")
            }
            let target = (matched.path as NSString).appendingPathComponent("TASKS.md")
            try fileTask(task, from: source.path, to: target, markdownIO: markdownIO)
            print("✓ Filed \(taskID) → \(matched.name)")
            try await runSyncIfRequested(syncAfter, forgeDir: forgeDir)
            return
        }
    }

    private func applyMetadataEdits(to task: inout ForgeTask) {
        // Section and waiting semantics.
        switch section {
        case .next:
            task.section = .nextActions
        case .waiting:
            task.section = .waitingFor
        }

        if let ctx = ctx, !ctx.isEmpty {
            task.context = ctx
        }
        if let energy = energy, !energy.isEmpty {
            task.energy = energy
        }
        if let waiting = waitingOn, !waiting.isEmpty {
            task.waitingOn = waiting
            task.section = .waitingFor
            if task.sinceDate == nil {
                task.sinceDate = Date()
            }
        }

        if let dueRaw = due, !dueRaw.isEmpty {
            let parsed = MarkdownIO.parseDueInput(dueRaw)
            if let date = parsed.date {
                task.dueDate = date
                task.dueHasTime = parsed.hasTime
            }
        }
        if let deferRaw = `defer`, !deferRaw.isEmpty {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.dateFormat = "yyyy-MM-dd"
            task.deferDate = f.date(from: deferRaw)
        }
    }

    private func fileTask(_ task: ForgeTask, from sourcePath: String, to targetPath: String, markdownIO: MarkdownIO) throws {
        let revised = task
        // Ensure section is applied even if source task was in inbox/other.
        // (Metadata edits already set section appropriately.)
        try markdownIO.appendTask(revised, toFileAt: targetPath)
        _ = try markdownIO.removeTask(withID: task.id, inFileAt: sourcePath)
    }

    private func ensureAreaFile(named name: String, forgeDir: String) throws -> String {
        let root = ConfigLoader.taskFilesRoot(forgeDir: forgeDir)
        let fileName = "\(name).md"
        let path = (root as NSString).appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: path) {
            try MarkdownIO().createEmptyTasksFile(at: path)
        }
        return path
    }

    private func findProject(named query: String, in projects: [Project]) -> Project? {
        let lower = query.lowercased()
        if let exact = projects.first(where: { $0.name.lowercased() == lower }) {
            return exact
        }
        let matches = projects.filter { $0.name.lowercased().contains(lower) }
        if matches.count == 1 { return matches.first }
        if matches.count > 1 {
            print("Ambiguous match for '\(query)':")
            for m in matches { print("  • \(m.name)") }
        }
        return nil
    }

    private struct TaskLocation {
        let path: String
        let projectName: String?
    }

    private func locateTask(taskID: String, config: ForgeConfig, forgeDir: String) async throws -> TaskLocation? {
        let idMarker = "<!-- id:\(taskID) -->"

        // Check inbox + all task root files first (fast; no project scan needed).
        for (path, label) in ConfigLoader.allTaskFilesInTaskRoot(forgeDir: forgeDir) {
            let raw = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            if raw.contains(idMarker) {
                return TaskLocation(path: path, projectName: label)
            }
        }

        // Then scan projects.
        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()
        for project in projects {
            let tasksPath = (project.path as NSString).appendingPathComponent("TASKS.md")
            guard FileManager.default.fileExists(atPath: tasksPath) else { continue }
            let raw = (try? String(contentsOfFile: tasksPath, encoding: .utf8)) ?? ""
            if raw.contains(idMarker) {
                return TaskLocation(path: tasksPath, projectName: project.name)
            }
        }

        return nil
    }

    private func runSyncIfRequested(_ shouldSync: Bool, forgeDir: String) async throws {
        guard shouldSync else { return }
        var cmd = SyncCommand()
        try await cmd.run()
    }
}

