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

    mutating func run() async throws {
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

        for (areaPath, areaName) in ConfigLoader.areaTaskFiles(forgeDir: forgeDir) {
            if try markdownIO.completeTask(withID: taskID, inFileAt: areaPath) {
                print("✓ Completed task \(taskID) in \(areaName)")
                return
            }
        }

        print("Task \(taskID) not found in any project or area file.")
    }
}
