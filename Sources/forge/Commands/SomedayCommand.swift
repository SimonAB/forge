import ArgumentParser
import Foundation
import ForgeCore

struct SomedayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "someday",
        abstract: "View and manage the someday/maybe list."
    )

    @Argument(help: "Text to add to someday/maybe. If omitted, shows current items.")
    var text: [String] = []

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let somedayPath = (forgeDir as NSString).appendingPathComponent("someday-maybe.md")

        if text.isEmpty {
            try await showSomeday(at: somedayPath, config: config)
        } else {
            try addToSomeday(text: text.joined(separator: " "), at: somedayPath)
        }
    }

    private func showSomeday(at path: String, config: ForgeConfig) async throws {
        let markdownIO = MarkdownIO()
        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let reset = "\u{1B}[0m"

        var items: [ForgeTask] = []
        if FileManager.default.fileExists(atPath: path) {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            items = markdownIO.parseTasks(from: content).filter { !$0.isCompleted }
        }

        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()
        let paused = projects.filter { $0.column == "Paused" }

        print("\(bold)Someday / Maybe\(reset)\n")

        if !paused.isEmpty {
            print("\(bold)Paused projects:\(reset)")
            for p in paused {
                print("  ⏸️  \(p.name)")
            }
            print()
        }

        if !items.isEmpty {
            print("\(bold)Ideas & future tasks:\(reset)")
            for item in items {
                print("  • \(item.text) \(dim)[\(item.id)]\(reset)")
            }
            print()
        }

        if items.isEmpty && paused.isEmpty {
            print("\(dim)No someday items or paused projects.\(reset)")
            print("\(dim)Add with: forge someday \"idea description\"\(reset)")
        }
    }

    private func addToSomeday(text: String, at path: String) throws {
        let markdownIO = MarkdownIO()

        if !FileManager.default.fileExists(atPath: path) {
            let header = "# Someday / Maybe\n\n## Next Actions\n\n## Completed\n\n"
            try header.write(toFile: path, atomically: true, encoding: .utf8)
        }

        let task = ForgeTask(
            id: ForgeTask.newID(),
            text: text,
            section: .nextActions
        )
        try markdownIO.appendTask(task, toFileAt: path)
        print("Added to someday/maybe: \(text)")
        print("  id: \(task.id)")
    }
}
