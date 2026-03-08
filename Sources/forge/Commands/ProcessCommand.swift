import ArgumentParser
import Foundation
import ForgeCore

struct ProcessCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "process",
        abstract: "Interactively process inbox items into projects."
    )

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let inboxPath = (forgeDir as NSString).appendingPathComponent("inbox.md")
        let markdownIO = MarkdownIO()

        guard FileManager.default.fileExists(atPath: inboxPath) else {
            print("Inbox is empty.")
            return
        }

        let tasks = markdownIO.parseTasks(from: try String(contentsOfFile: inboxPath, encoding: .utf8))
        let pending = tasks.filter { !$0.isCompleted }

        if pending.isEmpty {
            print("Inbox is empty. Nothing to process.")
            return
        }

        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()
        let activeProjects = projects.filter { p in
            p.column != nil && p.column != "Shipped"
        }.sorted { $0.name < $1.name }

        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let reset = "\u{1B}[0m"

        print("\(bold)Processing \(pending.count) inbox items\(reset)")
        print("\(dim)For each item: assign to a project, defer to someday, or delete.\(reset)\n")

        print("\(bold)Active projects:\(reset)")
        for (i, project) in activeProjects.enumerated() {
            let col = project.column ?? "Untagged"
            print("  \(dim)\(i + 1).\(reset) \(project.name) \(dim)(\(col))\(reset)")
        }
        print("  \(dim)s.\(reset) Someday/Maybe")
        print("  \(dim)d.\(reset) Delete")
        print("  \(dim)k.\(reset) Keep in inbox")
        print()

        for task in pending {
            print("\(bold)→ \(task.text)\(reset)")
            print("  \(dim)Assign to project (number), s=someday, d=delete, k=keep:\(reset) ", terminator: "")

            guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else {
                continue
            }

            if input.lowercased() == "d" {
                if try markdownIO.completeTask(withID: task.id, inFileAt: inboxPath) {
                    print("  Deleted.\n")
                }
            } else if input.lowercased() == "s" {
                let somedayPath = (forgeDir as NSString).appendingPathComponent("someday-maybe.md")
                try markdownIO.appendTask(task, toFileAt: somedayPath)
                _ = try markdownIO.completeTask(withID: task.id, inFileAt: inboxPath)
                print("  Moved to someday/maybe.\n")
            } else if input.lowercased() == "k" {
                print("  Kept in inbox.\n")
            } else if let num = Int(input), num >= 1, num <= activeProjects.count {
                let target = activeProjects[num - 1]
                let tasksPath = (target.path as NSString).appendingPathComponent("TASKS.md")
                try markdownIO.appendTask(task, toFileAt: tasksPath)
                _ = try markdownIO.completeTask(withID: task.id, inFileAt: inboxPath)
                print("  Moved to \(target.name).\n")
            } else {
                print("  \(dim)Unrecognised input, keeping in inbox.\(reset)\n")
            }
        }

        print("Inbox processing complete.")
    }
}
