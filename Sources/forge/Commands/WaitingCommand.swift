import ArgumentParser
import Foundation
import ForgeCore

struct WaitingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "waiting",
        abstract: "Show all waiting-for items across projects."
    )

    @Option(name: .long, help: "Focus on a specific tag (e.g. work, personal). Overrides persistent focus.")
    var focus: String?

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let scanner = WorkspaceScanner(config: config)
        let markdownIO = MarkdownIO()

        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let yellow = "\u{1B}[33m"
        let reset = "\u{1B}[0m"

        let activeFocus = focus ?? ConfigLoader.currentFocus(forgeDir: forgeDir)
        let showProjects = ConfigLoader.includesProjects(focusTag: activeFocus, config: config)

        if let tag = activeFocus {
            print("\(dim)Focus: \(tag)\(reset)\n")
        }

        var totalWaiting = 0

        if showProjects {
            let projects = try await scanner.scanProjects()
            for proj in projects {
                let tasksPath = (proj.path as NSString).appendingPathComponent("TASKS.md")
                guard FileManager.default.fileExists(atPath: tasksPath) else { continue }

                let tasks = (try? markdownIO.parseTasks(at: tasksPath, projectName: proj.name)) ?? []
                totalWaiting += printWaiting(tasks, heading: proj.name,
                                              bold: bold, dim: dim, yellow: yellow, reset: reset)
            }
        }

        let areas = ConfigLoader.areaFiles(forgeDir: forgeDir, focusTag: activeFocus)
        for area in areas {
            let content = (try? String(contentsOfFile: area.path, encoding: .utf8)) ?? ""
            let tasks = markdownIO.parseTasks(from: content, projectName: area.name)
            totalWaiting += printWaiting(tasks, heading: area.name,
                                          bold: bold, dim: dim, yellow: yellow, reset: reset)
        }

        if totalWaiting == 0 {
            print("No waiting-for items.")
        } else {
            print("\(dim)\(totalWaiting) items waiting\(reset)")
        }
    }

    private func printWaiting(
        _ tasks: [ForgeTask], heading: String,
        bold: String, dim: String, yellow: String, reset: String
    ) -> Int {
        let waiting = tasks.filter { !$0.isCompleted && $0.section == .waitingFor && !$0.isDeferred }
        guard !waiting.isEmpty else { return 0 }

        print("\(bold)\(heading)\(reset)")
        for task in waiting {
            let person = task.waitingOn ?? "?"
            let since = task.sinceDate.map {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return " since \(f.string(from: $0))"
            } ?? ""
            print("  \(yellow)⏳\(reset) \(task.text) \(dim)← \(person)\(since)\(reset) \(dim)[\(task.id)]\(reset)")
        }
        print()
        return waiting.count
    }
}
