import ArgumentParser
import Foundation
import ForgeCore

struct DoneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "done",
        abstract: "Mark a task as completed by its ID."
    )

    @Argument(help: "Task ID (the 6-character code from <!-- id:xxxxxx -->).")
    var taskID: String

    @Option(name: .long, help: "Path to the TASKS.md or area file containing the task. Use when the project is not in the scanned list (e.g. missing project_tag) or when running from an editor.")
    var file: String?

    mutating func run() async throws {
        // If a specific file path is given, complete in that file only (no config or project scan needed).
        if let path = file {
            let expanded = (path as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else {
                print("File not found: \(expanded)")
                return
            }
            let markdownIO = MarkdownIO()
            if try markdownIO.completeTask(withID: taskID, inFileAt: expanded) {
                print("✓ Completed task \(taskID)")
            } else {
                print("Task \(taskID) not found in \(expanded)")
            }
            return
        }

        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let markdownIO = MarkdownIO()
        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()

        for project in projects {
            let tasksPath = (project.path as NSString).appendingPathComponent("TASKS.md")
            guard FileManager.default.fileExists(atPath: tasksPath) else { continue }

            if try markdownIO.completeTask(withID: taskID, inFileAt: tasksPath) {
                print("✓ Completed task \(taskID) in \(project.name)")
                return
            }
        }

        // All markdown files in Forge/tasks (inbox, someday-maybe, area files, etc.).
        for (taskPath, taskName) in ConfigLoader.allTaskFilesInTaskRoot(forgeDir: forgeDir) {
            if try markdownIO.completeTask(withID: taskID, inFileAt: taskPath) {
                print("✓ Completed task \(taskID) in \(taskName)")
                return
            }
        }

        print("Task \(taskID) not found in any project or area file.")
    }
}
