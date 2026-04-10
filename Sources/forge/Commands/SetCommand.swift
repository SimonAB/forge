import ArgumentParser
import Foundation
import ForgeCore

/// Non-interactive task metadata updates by ID.
///
/// Intended for LLM-driven workflows to adjust due dates, contexts, defers, and waiting status
/// without manually editing task files.
struct SetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Update a task's metadata by ID (due, defer, context, waiting, section)."
    )

    @Argument(help: "Task ID (the 6-character code from <!-- id:xxxxxx -->).")
    var taskID: String

    @Option(name: .long, help: "Update within a specific file (TASKS.md or area file). Skips searching.")
    var file: String?

    @Option(name: .long, help: "Set @ctx(value).")
    var ctx: String?

    @Flag(name: .long, help: "Clear @ctx(...) on the task.")
    var clearCtx = false

    @Option(name: .long, help: "Set @energy(value).")
    var energy: String?

    @Flag(name: .long, help: "Clear @energy(...) on the task.")
    var clearEnergy = false

    @Option(name: .long, help: "Set @due(YYYY-MM-DD or YYYY-MM-DD HH:mm).")
    var due: String?

    @Flag(name: .long, help: "Clear @due(...) on the task.")
    var clearDue = false

    @Option(name: .long, help: "Set @defer(YYYY-MM-DD).")
    var `defer`: String?

    @Flag(name: .long, help: "Clear @defer(...) on the task.")
    var clearDefer = false

    @Option(name: .long, help: "Set @waiting(value) and move to Waiting For section.")
    var waitingOn: String?

    @Flag(name: .long, help: "Clear @waiting(...) and @since(...), and move to Next Actions.")
    var clearWaiting = false

    enum SectionChoice: String, ExpressibleByArgument, CaseIterable {
        case next
        case waiting
    }

    @Option(name: .long, help: "Move task to a section: next or waiting.")
    var section: SectionChoice?

    @Flag(name: .long, help: "Also run `forge sync` after updating.")
    var syncAfter = false

    mutating func run() async throws {
        let markdownIO = MarkdownIO()

        if let specific = file {
            let expanded = (specific as NSString).expandingTildeInPath
            let ok = try markdownIO.updateTask(withID: taskID, inFileAt: expanded, projectName: nil) { task in
                applyEdits(to: &task)
            }
            if ok {
                print("✓ Updated \(taskID)")
                try await runSyncIfRequested()
            } else {
                print("Task \(taskID) not found in \(expanded)")
            }
            return
        }

        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)

        guard let location = try await locateTask(taskID: taskID, config: config, forgeDir: forgeDir) else {
            print("Task \(taskID) not found in inbox, areas, or projects.")
            return
        }

        let ok = try markdownIO.updateTask(withID: taskID, inFileAt: location.path, projectName: location.projectName) { task in
            applyEdits(to: &task)
        }
        if ok {
            print("✓ Updated \(taskID)")
            try await runSyncIfRequested()
        } else {
            print("Task \(taskID) not found in \(location.path)")
        }
    }

    private func applyEdits(to task: inout ForgeTask) {
        if clearCtx { task.context = nil }
        if let ctx = ctx { task.context = ctx.isEmpty ? nil : ctx }

        if clearEnergy { task.energy = nil }
        if let energy = energy { task.energy = energy.isEmpty ? nil : energy }

        if clearDue {
            task.dueDate = nil
            task.dueHasTime = false
        }
        if let dueRaw = due, !dueRaw.isEmpty {
            let parsed = MarkdownIO.parseDueInput(dueRaw)
            if let date = parsed.date {
                task.dueDate = date
                task.dueHasTime = parsed.hasTime
            }
        }

        if clearDefer { task.deferDate = nil }
        if let deferRaw = `defer`, !deferRaw.isEmpty {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.dateFormat = "yyyy-MM-dd"
            task.deferDate = f.date(from: deferRaw)
        }

        if clearWaiting {
            task.waitingOn = nil
            task.sinceDate = nil
            task.section = .nextActions
        }
        if let waiting = waitingOn, !waiting.isEmpty {
            task.waitingOn = waiting
            if task.sinceDate == nil {
                task.sinceDate = Date()
            }
            task.section = .waitingFor
        }

        if let choice = section {
            switch choice {
            case .next:
                task.section = .nextActions
            case .waiting:
                task.section = .waitingFor
            }
        }
    }

    private struct TaskLocation {
        let path: String
        let projectName: String?
    }

    private func locateTask(taskID: String, config: ForgeConfig, forgeDir: String) async throws -> TaskLocation? {
        let idMarker = "<!-- id:\(taskID) -->"

        for (path, label) in ConfigLoader.allTaskFilesInTaskRoot(forgeDir: forgeDir) {
            let raw = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            if raw.contains(idMarker) {
                return TaskLocation(path: path, projectName: label)
            }
        }

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

    private func runSyncIfRequested() async throws {
        guard syncAfter else { return }
        var cmd = SyncCommand()
        try await cmd.run()
    }
}

