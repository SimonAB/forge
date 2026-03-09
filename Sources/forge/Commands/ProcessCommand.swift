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
        let inboxPath = ConfigLoader.inboxPath(forgeDir: forgeDir)
        let markdownIO = MarkdownIO()

        func readTrimmedLine() -> String? {
            readLine()?.trimmingCharacters(in: .whitespaces)
        }

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
        print("\(dim)For each item: do now, file as a next action, defer to someday, delegate (waiting for), delete, or keep in the inbox.\(reset)\n")

        print("\(bold)Active projects:\(reset)")
        for (i, project) in activeProjects.enumerated() {
            let col = project.column ?? "Untagged"
            print("  \(dim)\(i + 1).\(reset) \(project.name) \(dim)(\(col))\(reset)")
        }
        print("  \(dim)d.\(reset) Done now (complete in inbox)")
        print("  \(dim)n.\(reset) Next action (move to project)")
        print("  \(dim)w.\(reset) Waiting for (move to project)")
        print("  \(dim)s.\(reset) Someday/Maybe")
        print("  \(dim)t.\(reset) Trash (delete from inbox)")
        print("  \(dim)k.\(reset) Keep in inbox")
        print()

        try? ForgePaths(forgeDir: forgeDir).ensureTaskFilesDirectoryExists()

        for task in pending {
            print("\(bold)→ \(task.text)\(reset)")
            print("  \(dim)Choose: number=move to project, d=done now, n=next, w=waiting, s=someday, t=trash, k=keep:\(reset) ", terminator: "")

            guard let input = readTrimmedLine(), !input.isEmpty else {
                continue
            }

            let lower = input.lowercased()

            if lower == "d" {
                if try markdownIO.completeTask(withID: task.id, inFileAt: inboxPath) {
                    print("  Marked done in inbox.\n")
                }
            } else if lower == "t" {
                if try markdownIO.completeTask(withID: task.id, inFileAt: inboxPath) {
                    print("  Deleted.\n")
                }
            } else if lower == "s" {
                let somedayPath = ConfigLoader.somedayPath(forgeDir: forgeDir)
                try markdownIO.appendTask(task, toFileAt: somedayPath)
                _ = try markdownIO.completeTask(withID: task.id, inFileAt: inboxPath)
                print("  Moved to someday/maybe.\n")
            } else if lower == "k" {
                print("  Kept in inbox.\n")
            } else if lower == "n" {
                print("  Project number for next action: ", terminator: "")
                guard
                    let projInput = readTrimmedLine(),
                    let num = Int(projInput),
                    num >= 1, num <= activeProjects.count
                else {
                    print("  \(dim)Invalid project selection, keeping in inbox.\(reset)\n")
                    continue
                }

                var nextTask = task
                nextTask.section = .nextActions

                print("  Context (optional, e.g. email, home): ", terminator: "")
                if let ctx = readTrimmedLine(), !ctx.isEmpty {
                    nextTask.context = ctx
                }

                print("  Due date (YYYY-MM-DD, optional): ", terminator: "")
                if let dateString = readTrimmedLine(), !dateString.isEmpty {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    if let date = formatter.date(from: dateString) {
                        nextTask.dueDate = date
                    } else {
                        print("  \(dim)Could not parse date, leaving without due date.\(reset)")
                    }
                }

                let target = activeProjects[num - 1]
                let tasksPath = (target.path as NSString).appendingPathComponent("TASKS.md")
                try markdownIO.appendTask(nextTask, toFileAt: tasksPath)
                _ = try markdownIO.completeTask(withID: task.id, inFileAt: inboxPath)
                print("  Filed as next action in \(target.name).\n")
            } else if lower == "w" {
                print("  Project number for waiting item: ", terminator: "")
                guard
                    let projInput = readTrimmedLine(),
                    let num = Int(projInput),
                    num >= 1, num <= activeProjects.count
                else {
                    print("  \(dim)Invalid project selection, keeping in inbox.\(reset)\n")
                    continue
                }

                var waitingTask = task
                waitingTask.section = .waitingFor

                print("  Waiting on (person or dependency, optional): ", terminator: "")
                if let who = readTrimmedLine(), !who.isEmpty {
                    waitingTask.waitingOn = who
                    waitingTask.sinceDate = Date()
                }

                let target = activeProjects[num - 1]
                let tasksPath = (target.path as NSString).appendingPathComponent("TASKS.md")
                try markdownIO.appendTask(waitingTask, toFileAt: tasksPath)
                _ = try markdownIO.completeTask(withID: task.id, inFileAt: inboxPath)
                print("  Filed under Waiting For in \(target.name).\n")
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
