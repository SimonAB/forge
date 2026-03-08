import ArgumentParser
import Foundation
import ForgeCore

struct ContextsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contexts",
        abstract: "Show tasks grouped by context."
    )

    @Argument(help: "Filter to a specific context (e.g. office, lab, calls).")
    var context: String?

    @Option(name: .long, help: "Focus on a specific tag (e.g. work, personal). Overrides persistent focus.")
    var focus: String?

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let scanner = WorkspaceScanner(config: config)
        let markdownIO = MarkdownIO()

        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let reset = "\u{1B}[0m"

        let activeFocus = focus ?? ConfigLoader.currentFocus(forgeDir: forgeDir)
        let showProjects = ConfigLoader.includesProjects(focusTag: activeFocus, config: config)

        if let tag = activeFocus {
            print("\(dim)Focus: \(tag)\(reset)\n")
        }

        var tasksByContext: [String: [(task: ForgeTask, project: String)]] = [:]

        if showProjects {
            let projects = try await scanner.scanProjects()
            let activeProjects = projects.filter { p in
                p.column != nil && p.column != "Shipped" && p.column != "Paused"
            }

            for proj in activeProjects {
                let tasksPath = (proj.path as NSString).appendingPathComponent("TASKS.md")
                guard FileManager.default.fileExists(atPath: tasksPath) else { continue }

                let tasks = (try? markdownIO.parseTasks(at: tasksPath, projectName: proj.name)) ?? []
                for task in tasks where !task.isCompleted && task.section == .nextActions && !task.isDeferred {
                    let ctx = task.context ?? "untagged"
                    tasksByContext[ctx, default: []].append((task: task, project: proj.name))
                }
            }
        }

        let areas = ConfigLoader.areaFiles(forgeDir: forgeDir, focusTag: activeFocus)
        for area in areas {
            let content = (try? String(contentsOfFile: area.path, encoding: .utf8)) ?? ""
            let tasks = markdownIO.parseTasks(from: content, projectName: area.name)
            for task in tasks where !task.isCompleted && task.section == .nextActions && !task.isDeferred {
                let ctx = task.context ?? "untagged"
                tasksByContext[ctx, default: []].append((task: task, project: area.name))
            }
        }

        if let filterCtx = context {
            let lower = filterCtx.lowercased()
            let matching = tasksByContext.filter { $0.key.lowercased() == lower }
            if matching.isEmpty {
                print("No tasks with context '@\(filterCtx)'.")
                return
            }
            for (ctx, items) in matching.sorted(by: { $0.key < $1.key }) {
                printContext(ctx, items: items, bold: bold, dim: dim, reset: reset)
            }
        } else {
            let sorted = tasksByContext.sorted { $0.key < $1.key }
            for (ctx, items) in sorted {
                printContext(ctx, items: items, bold: bold, dim: dim, reset: reset)
            }
        }
    }

    private func printContext(
        _ ctx: String,
        items: [(task: ForgeTask, project: String)],
        bold: String, dim: String, reset: String
    ) {
        print("\(bold)@\(ctx) (\(items.count))\(reset)")
        for item in items {
            let dueLabel = item.task.dueDateString.map { " \(dim)due \($0)\(reset)" } ?? ""
            print("  • \(item.task.text)\(dueLabel) \(dim)← \(item.project)\(reset) \(dim)[\(item.task.id)]\(reset)")
        }
        print()
    }
}
