import ArgumentParser
import Foundation
import ForgeCore

struct NextCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "next",
        abstract: "Show all next actions across projects."
    )

    @Option(name: .shortAndLong, help: "Filter by project name (substring match).")
    var project: String?

    @Option(name: .shortAndLong, help: "Filter by context.")
    var context: String?

    @Flag(name: .shortAndLong, help: "Include waiting-for items.")
    var all = false

    @Flag(name: .shortAndLong, help: "Include deferred tasks (hidden by default).")
    var deferred = false

    @Option(name: .long, help: "Focus on a specific tag (e.g. work, personal). Overrides persistent focus.")
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
        let reset = "\u{1B}[0m"

        let activeFocus = focus ?? ConfigLoader.currentFocus(forgeDir: forgeDir)
        let showProjects = ConfigLoader.includesProjects(focusTag: activeFocus, config: config)

        if let tag = activeFocus {
            print("\(dim)Focus: \(tag)\(reset)\n")
        }

        var totalTasks = 0
        var overdueTasks = 0

        if showProjects {
            let projects = try await scanner.scanProjects()
            let filteredProjects: [Project]
            if let projectFilter = project {
                let lower = projectFilter.lowercased()
                filteredProjects = projects.filter { $0.name.lowercased().contains(lower) }
            } else {
                filteredProjects = projects.filter { p in
                    p.column != nil && p.column != "Shipped" && p.column != "Paused"
                }
            }

            for proj in filteredProjects {
                let tasksPath = (proj.path as NSString).appendingPathComponent("TASKS.md")
                guard FileManager.default.fileExists(atPath: tasksPath) else { continue }

                let tasks = (try? markdownIO.parseTasks(at: tasksPath, projectName: proj.name)) ?? []
                var relevantTasks = tasks.filter {
                    !$0.isCompleted
                    && ($0.section == .nextActions || (all && $0.section == .waitingFor))
                    && (deferred || !$0.isDeferred)
                }

                if let ctx = context {
                    relevantTasks = relevantTasks.filter { $0.context?.lowercased() == ctx.lowercased() }
                }

                guard !relevantTasks.isEmpty else { continue }

                print("\(bold)\(proj.name)\(reset) \(dim)(\(proj.column ?? "Untagged"))\(reset)")
                printTasks(relevantTasks, totalTasks: &totalTasks, overdueTasks: &overdueTasks,
                           red: red, yellow: yellow, dim: dim, reset: reset)
                print()
            }
        }

        if project == nil {
            let areas = ConfigLoader.areaFiles(forgeDir: forgeDir, focusTag: activeFocus)
            for area in areas {
                guard area.name != "Inbox" else { continue }
                let content = (try? String(contentsOfFile: area.path, encoding: .utf8)) ?? ""
                let tasks = markdownIO.parseTasks(from: content, projectName: area.name)
                var relevantTasks = tasks.filter {
                    !$0.isCompleted
                    && ($0.section == .nextActions || (all && $0.section == .waitingFor))
                    && (deferred || !$0.isDeferred)
                }
                if let ctx = context {
                    relevantTasks = relevantTasks.filter { $0.context?.lowercased() == ctx.lowercased() }
                }
                guard !relevantTasks.isEmpty else { continue }

                print("\(bold)\(area.name)\(reset) \(dim)(Area)\(reset)")
                printTasks(relevantTasks, totalTasks: &totalTasks, overdueTasks: &overdueTasks,
                           red: red, yellow: yellow, dim: dim, reset: reset)
                print()
            }
        }

        if totalTasks == 0 {
            print("No next actions found.")
            if project == nil && activeFocus != nil {
                print("\(dim)Tip: clear focus with 'forge focus --clear' to see all areas.\(reset)")
            } else if project == nil {
                print("\(dim)Tip: add tasks with 'forge add <project> \"task description\"'\(reset)")
            }
        } else {
            print("\(dim)\(totalTasks) tasks\(overdueTasks > 0 ? ", \(red)\(overdueTasks) overdue\(reset)" : "")\(reset)")
        }
    }

    private func printTasks(
        _ tasks: [ForgeTask], totalTasks: inout Int, overdueTasks: inout Int,
        red: String, yellow: String, dim: String, reset: String
    ) {
        for task in tasks {
            totalTasks += 1
            var prefix = "  "
            var dueLabel = ""

            if task.isOverdue {
                overdueTasks += 1
                prefix = "  \(red)▸\(reset)"
                dueLabel = " \(red)OVERDUE \(task.dueDateString ?? "")\(reset)"
            } else if task.isDueToday {
                prefix = "  \(yellow)▸\(reset)"
                dueLabel = " \(yellow)TODAY\(reset)"
            } else if let due = task.dueDateString {
                dueLabel = " \(dim)due \(due)\(reset)"
            }

            let ctxLabel = task.context.map { " \(dim)@\($0)\(reset)" } ?? ""
            let waitLabel = task.waitingOn.map { " \(dim)⏳\($0)\(reset)" } ?? ""
            let repeatLabel = task.repeatRule.map { " \(dim)↻\($0.serialise())\(reset)" } ?? ""
            let cyan = "\u{1B}[36m"
            let deferLabel: String
            if task.becomesActionableToday {
                deferLabel = " \(cyan)AVAILABLE TODAY\(reset)"
            } else if task.isDeferred {
                deferLabel = " \(dim)deferred until \(task.deferDateString ?? "")\(reset)"
            } else {
                deferLabel = ""
            }
            let idLabel = " \(dim)[\(task.id)]\(reset)"

            print("\(prefix) \(task.text)\(dueLabel)\(deferLabel)\(ctxLabel)\(waitLabel)\(repeatLabel)\(idLabel)")
        }
    }
}
