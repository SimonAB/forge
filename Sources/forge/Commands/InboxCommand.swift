import ArgumentParser
import Foundation
import ForgeCore

struct InboxCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "Capture a task to the GTD inbox, or view inbox contents."
    )

    @Argument(help: "Task text to capture. If omitted, shows inbox contents.")
    var text: [String] = []

    mutating func run() throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let inboxPath = (forgeDir as NSString).appendingPathComponent("inbox.md")

        if text.isEmpty {
            try showInbox(at: inboxPath)
        } else {
            try captureToInbox(text: text.joined(separator: " "), at: inboxPath)
        }
    }

    private func showInbox(at path: String) throws {
        let markdownIO = MarkdownIO()

        guard FileManager.default.fileExists(atPath: path) else {
            print("Inbox is empty.")
            return
        }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let tasks = markdownIO.parseTasks(from: content, projectName: "Inbox")
        let pending = tasks.filter { !$0.isCompleted }

        if pending.isEmpty {
            print("Inbox is empty. 🎉")
            print("\u{1B}[2mCapture with: forge inbox \"task description\"\u{1B}[0m")
            return
        }

        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let reset = "\u{1B}[0m"

        print("\(bold)Inbox (\(pending.count) items)\(reset)")
        for task in pending {
            let dueLabel = task.dueDateString.map { " \(dim)due \($0)\(reset)" } ?? ""
            print("  • \(task.text)\(dueLabel) \(dim)[\(task.id)]\(reset)")
        }
        print()
        print("\(dim)Process with: forge process\(reset)")
    }

    private func captureToInbox(text: String, at path: String) throws {
        let markdownIO = MarkdownIO()

        if !FileManager.default.fileExists(atPath: path) {
            let header = "# Inbox\n\n## Next Actions\n\n## Completed\n\n"
            try header.write(toFile: path, atomically: true, encoding: .utf8)
        }

        let task = ForgeTask(
            id: ForgeTask.newID(),
            text: text,
            section: .nextActions
        )
        try markdownIO.appendTask(task, toFileAt: path)
        print("Captured: \(text)")
        print("  id: \(task.id)")
    }
}
