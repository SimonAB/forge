import ArgumentParser
import Foundation
import ForgeCore

/// Show tasks grouped by project, with summary counts and status indicators.
struct ProjectsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "projects",
        abstract: "Show tasks per project."
    )

    @Option(name: .shortAndLong, help: "Filter to a single project (substring match).")
    var project: String?

    @Option(name: .shortAndLong, help: "Filter to a kanban column (e.g. Active, Write).")
    var column: String?

    @Flag(name: .shortAndLong, help: "Include completed tasks.")
    var all = false

    @Flag(name: .shortAndLong, help: "Include deferred tasks.")
    var deferred = false

    @Option(name: .long, help: "Focus on a specific tag (overrides persistent focus).")
    var focus: String?

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let scanner = WorkspaceScanner(config: config)
        let markdownIO = MarkdownIO()

        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let red = "\u{1B}[31m"
        let yellow = "\u{1B}[33m"
        let green = "\u{1B}[32m"
        let cyan = "\u{1B}[36m"
        let reset = "\u{1B}[0m"

        let activeFocus = focus ?? ConfigLoader.currentFocus(forgeDir: forgeDir)
        let showProjects = ConfigLoader.includesProjects(focusTag: activeFocus, config: config)

        if let tag = activeFocus {
            print("\(dim)Focus: \(tag)\(reset)\n")
        }

        var totalProjects = 0
        var totalTasks = 0

        if showProjects {
            var projects = try await scanner.scanProjects()

            if let projectFilter = project {
                let lower = projectFilter.lowercased()
                projects = projects.filter { $0.name.lowercased().contains(lower) }
            }

            if let columnFilter = column {
                let lower = columnFilter.lowercased()
                projects = projects.filter { $0.column?.lowercased().hasPrefix(lower) == true }
            } else if project == nil {
                projects = projects.filter { $0.column != nil && $0.column != "Shipped" }
            }

            for proj in projects {
                let tasksPath = (proj.path as NSString).appendingPathComponent("TASKS.md")
                guard FileManager.default.fileExists(atPath: tasksPath) else {
                    totalProjects += 1
                    print("\(bold)\(proj.name)\(reset) \(dim)(\(proj.column ?? "Untagged"))\(reset)  \(dim)no TASKS.md\(reset)")
                    print()
                    continue
                }

                let tasks = (try? markdownIO.parseTasks(at: tasksPath, projectName: proj.name)) ?? []
                totalProjects += 1
                printProject(
                    name: proj.name, label: proj.column ?? "Untagged",
                    tasks: tasks, markdownIO: markdownIO,
                    bold: bold, dim: dim, red: red, yellow: yellow,
                    green: green, cyan: cyan, reset: reset,
                    totalTasks: &totalTasks
                )
            }
        }

        if totalProjects == 0 {
            print("No projects found.")
            if project != nil {
                print("\(dim)Tip: use 'forge board --list' to see all projects.\(reset)")
            }
        } else {
            print("\(dim)\(totalProjects) project\(totalProjects == 1 ? "" : "s"), \(totalTasks) task\(totalTasks == 1 ? "" : "s")\(reset)")
        }
    }

    // MARK: - Rendering

    private func printProject(
        name: String, label: String,
        tasks: [ForgeTask], markdownIO: MarkdownIO,
        bold: String, dim: String, red: String, yellow: String,
        green: String, cyan: String, reset: String,
        totalTasks: inout Int
    ) {
        let pending = tasks.filter { !$0.isCompleted }
        let completed = tasks.filter { $0.isCompleted }
        let overdueCount = pending.filter(\.isOverdue).count
        let deferredCount = pending.filter(\.isDeferred).count

        var summary = "\(pending.count) pending"
        if overdueCount > 0 { summary += ", \(red)\(overdueCount) overdue\(reset)" }
        if deferredCount > 0 { summary += ", \(deferredCount) deferred" }
        if !completed.isEmpty { summary += ", \(completed.count) done" }

        print("\(bold)\(name)\(reset) \(dim)(\(label))\(reset)  \(dim)\(summary)\(reset)")

        let sections: [ForgeTask.Section] = [.nextActions, .waitingFor]
        for section in sections {
            let sectionTasks = pending.filter { $0.section == section }
            guard !sectionTasks.isEmpty else { continue }

            let sectionLabel = section == .waitingFor ? "Waiting For" : "Next Actions"
            print("  \(dim)\(sectionLabel)\(reset)")

            for task in sectionTasks {
                if task.isDeferred && !deferred { continue }
                totalTasks += 1
                printTask(task, dim: dim, red: red, yellow: yellow, cyan: cyan, reset: reset)
            }
        }

        if all && !completed.isEmpty {
            print("  \(dim)Completed\(reset)")
            for task in completed.prefix(5) {
                totalTasks += 1
                let doneLabel = task.doneDate.map {
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                    return " \(dim)done \(f.string(from: $0))\(reset)"
                } ?? ""
                print("    \(green)✓\(reset) \(dim)\(task.text)\(doneLabel)\(reset)")
            }
            if completed.count > 5 {
                print("    \(dim)… and \(completed.count - 5) more\(reset)")
            }
        }

        print()
    }

    private func printTask(
        _ task: ForgeTask,
        dim: String, red: String, yellow: String, cyan: String, reset: String
    ) {
        var prefix = "    •"
        var dueLabel = ""

        if task.isOverdue {
            prefix = "    \(red)▸\(reset)"
            dueLabel = " \(red)OVERDUE \(task.dueDateString ?? "")\(reset)"
        } else if task.isDueToday {
            prefix = "    \(yellow)▸\(reset)"
            dueLabel = " \(yellow)TODAY\(reset)"
        } else if let due = task.dueDateString {
            dueLabel = " \(dim)due \(due)\(reset)"
        }

        let deferLabel: String
        if task.becomesActionableToday {
            deferLabel = " \(cyan)AVAILABLE TODAY\(reset)"
        } else if task.isDeferred {
            deferLabel = " \(dim)deferred until \(task.deferDateString ?? "")\(reset)"
        } else {
            deferLabel = ""
        }

        let ctxLabel = task.context.map { " \(dim)@\($0)\(reset)" } ?? ""
        let waitLabel = task.waitingOn.map { " \(dim)⏳\($0)\(reset)" } ?? ""
        let repeatLabel = task.repeatRule.map { " \(dim)↻\($0.serialise())\(reset)" } ?? ""
        let idLabel = " \(dim)[\(task.id)]\(reset)"

        print("\(prefix) \(task.text)\(dueLabel)\(deferLabel)\(ctxLabel)\(waitLabel)\(repeatLabel)\(idLabel)")
    }
}
