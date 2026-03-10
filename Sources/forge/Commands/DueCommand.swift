import ArgumentParser
import Foundation
import ForgeCore

struct DueCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "due",
        abstract: "Show overdue and upcoming due tasks across all TASKS.md files."
    )

    /// Also write a markdown summary file to the Forge tasks directory.
    @Flag(name: .shortAndLong, help: "Also write a markdown summary to Forge/tasks/due.md.")
    var markdown: Bool = false

    @Option(name: .shortAndLong, help: "Show tasks due within the next N days (default: 7).")
    var days: Int = 7

    @Flag(name: .shortAndLong, inversion: .prefixedNo, help: "Include tasks from the Forge directory (area files). Default: on.")
    var areas = true

    mutating func run() throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let markdownIO = MarkdownIO()
        let taskFilesRoot = ConfigLoader.taskFilesRoot(forgeDir: forgeDir)
         let taskIndex = FileTaskIndex.shared

        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let red = "\u{1B}[31m"
        let yellow = "\u{1B}[33m"
        let green = "\u{1B}[32m"
        let reset = "\u{1B}[0m"

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let horizon = calendar.date(byAdding: .day, value: days, to: today)!

        // Prime the cached index of project TASKS.md files so that we do not need to walk the
        // entire directory tree on every `forge due` run.
        try? taskIndex.refreshIfNeeded(config: config, forgeDir: forgeDir)

        // Collect tasks from all TASKS.md files under the configured project roots using the
        // cached index. This matches the menubar app's behaviour so badge counts and CLI output
        // stay in sync.
        let indexedProjectFiles = taskIndex.projectTaskFiles(for: config)
        var overdueTasks: [DueSummaryGenerator.Item] = []
        var dueTodayTasks: [DueSummaryGenerator.Item] = []
        var upcomingTasks: [DueSummaryGenerator.Item] = []

        for file in indexedProjectFiles {
            let tasks = (try? markdownIO.parseTasks(at: file.path, projectName: file.projectName)) ?? []
            for task in tasks where !task.isCompleted {
                guard let due = task.dueDate else { continue }
                let item = DueSummaryGenerator.Item(task: task, label: file.projectName, sourcePath: file.path)
                if task.isOverdue {
                    overdueTasks.append(item)
                } else if task.isDueToday {
                    dueTodayTasks.append(item)
                } else if due <= horizon {
                    upcomingTasks.append(item)
                }
            }
        }

        // Include area files (markdown in Forge directory) unless --no-areas.
        if areas {
            let areaFiles = ConfigLoader.areaFiles(forgeDir: forgeDir, focusTag: nil)
            for area in areaFiles {
                let content = (try? String(contentsOfFile: area.path, encoding: .utf8)) ?? ""
                let tasks = markdownIO.parseTasks(from: content, projectName: area.name)
                for task in tasks where !task.isCompleted {
                    guard let due = task.dueDate else { continue }
                    let item = DueSummaryGenerator.Item(task: task, label: area.name, sourcePath: area.path)
                    if task.isOverdue {
                        overdueTasks.append(item)
                    } else if task.isDueToday {
                        dueTodayTasks.append(item)
                    } else if due <= horizon {
                        upcomingTasks.append(item)
                    }
                }
            }
        }

        // Sort each group by due date.
        overdueTasks.sort { ($0.task.dueDate ?? .distantPast) < ($1.task.dueDate ?? .distantPast) }
        dueTodayTasks.sort { $0.task.text.lowercased() < $1.task.text.lowercased() }
        upcomingTasks.sort { ($0.task.dueDate ?? .distantFuture) < ($1.task.dueDate ?? .distantFuture) }

        let totalCount = overdueTasks.count + dueTodayTasks.count + upcomingTasks.count

        if totalCount == 0 {
            print("No overdue or upcoming tasks in the next \(days) days.")
            if markdown {
                let generator = DueSummaryGenerator()
                generator.writeMarkdownSummary(
                    overdueTasks: [],
                    dueTodayTasks: [],
                    upcomingTasks: [],
                    days: days,
                    taskFilesRoot: taskFilesRoot
                )
            }
            return
        }

        // Overdue
        if !overdueTasks.isEmpty {
            print("\(bold)\(red)⚠ Overdue (\(overdueTasks.count))\(reset)")
            for item in overdueTasks {
                printDueTask(item, red: red, dim: dim, reset: reset)
            }
            print()
        }

        // Due today
        if !dueTodayTasks.isEmpty {
            print("\(bold)\(yellow)📅 Due Today (\(dueTodayTasks.count))\(reset)")
            for item in dueTodayTasks {
                printDueTask(item, red: red, dim: dim, reset: reset)
            }
            print()
        }

        // Upcoming
        if !upcomingTasks.isEmpty {
            print("\(bold)\(green)📆 Due within \(days) days (\(upcomingTasks.count))\(reset)")
            for item in upcomingTasks {
                printDueTask(item, red: red, dim: dim, reset: reset)
            }
            print()
        }

        // Summary line
        var parts: [String] = []
        if !overdueTasks.isEmpty {
            parts.append("\(red)\(overdueTasks.count) overdue\(reset)")
        }
        if !dueTodayTasks.isEmpty {
            parts.append("\(yellow)\(dueTodayTasks.count) today\(reset)")
        }
        if !upcomingTasks.isEmpty {
            parts.append("\(green)\(upcomingTasks.count) upcoming\(reset)")
        }
        print("\(dim)\(totalCount) tasks: \(parts.joined(separator: ", "))\(reset)")

        if markdown {
            let generator = DueSummaryGenerator()
            generator.writeMarkdownSummary(
                overdueTasks: overdueTasks,
                dueTodayTasks: dueTodayTasks,
                upcomingTasks: upcomingTasks,
                days: days,
                taskFilesRoot: taskFilesRoot
            )
        }
    }

    /// Formats and prints a single due task line.
    private func printDueTask(
        _ item: DueSummaryGenerator.Item,
        red: String,
        dim: String,
        reset: String
    ) {
        let task = item.task
        let dueStr = task.dueDateString ?? ""
        let ctxLabel = task.context.map { " \(dim)@\($0)\(reset)" } ?? ""
        let waitLabel = task.waitingOn.map { " \(dim)⏳\($0)\(reset)" } ?? ""
        let repeatLabel = task.repeatRule.map { " \(dim)↻\($0.serialise())\(reset)" } ?? ""
        let idLabel = " \(dim)[\(task.id)]\(reset)"
        print("  \(task.text) \(dim)due \(dueStr)\(reset) \(dim)← \(item.label)\(reset)\(ctxLabel)\(waitLabel)\(repeatLabel)\(idLabel)")
    }
}
