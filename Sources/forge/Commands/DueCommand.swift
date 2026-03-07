import ArgumentParser
import Foundation
import ForgeCore

struct DueCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "due",
        abstract: "Show overdue and upcoming due tasks across all TASKS.md files."
    )

    @Option(name: .shortAndLong, help: "Show tasks due within the next N days (default: 7).")
    var days: Int = 7

    @Flag(name: .shortAndLong, inversion: .prefixedNo, help: "Include tasks from the Forge directory (area files). Default: on.")
    var areas = true

    mutating func run() throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let markdownIO = MarkdownIO()

        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let red = "\u{1B}[31m"
        let yellow = "\u{1B}[33m"
        let green = "\u{1B}[32m"
        let reset = "\u{1B}[0m"

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let horizon = calendar.date(byAdding: .day, value: days, to: today)!

        // Collect tasks from all TASKS.md files under ~/Documents.
        let taskFiles = TaskFileFinder.findAllUnderDocuments()
        var overdueTasks: [(ForgeTask, String)] = []
        var dueTodayTasks: [(ForgeTask, String)] = []
        var upcomingTasks: [(ForgeTask, String)] = []

        for file in taskFiles {
            let tasks = (try? markdownIO.parseTasks(at: file.path, projectName: file.label)) ?? []
            for task in tasks where !task.isCompleted {
                guard let due = task.dueDate else { continue }
                if task.isOverdue {
                    overdueTasks.append((task, file.label))
                } else if task.isDueToday {
                    dueTodayTasks.append((task, file.label))
                } else if due <= horizon {
                    upcomingTasks.append((task, file.label))
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
                    if task.isOverdue {
                        overdueTasks.append((task, area.name))
                    } else if task.isDueToday {
                        dueTodayTasks.append((task, area.name))
                    } else if due <= horizon {
                        upcomingTasks.append((task, area.name))
                    }
                }
            }
        }

        // Sort each group by due date.
        overdueTasks.sort { ($0.0.dueDate ?? .distantPast) < ($1.0.dueDate ?? .distantPast) }
        dueTodayTasks.sort { $0.0.text.lowercased() < $1.0.text.lowercased() }
        upcomingTasks.sort { ($0.0.dueDate ?? .distantFuture) < ($1.0.dueDate ?? .distantFuture) }

        let totalCount = overdueTasks.count + dueTodayTasks.count + upcomingTasks.count

        if totalCount == 0 {
            print("No overdue or upcoming tasks in the next \(days) days.")
            return
        }

        // Overdue
        if !overdueTasks.isEmpty {
            print("\(bold)\(red)⚠ Overdue (\(overdueTasks.count))\(reset)")
            for (task, label) in overdueTasks {
                printDueTask(task, label: label, red: red, dim: dim, reset: reset)
            }
            print()
        }

        // Due today
        if !dueTodayTasks.isEmpty {
            print("\(bold)\(yellow)📅 Due Today (\(dueTodayTasks.count))\(reset)")
            for (task, label) in dueTodayTasks {
                printDueTask(task, label: label, red: red, dim: dim, reset: reset)
            }
            print()
        }

        // Upcoming
        if !upcomingTasks.isEmpty {
            print("\(bold)\(green)📆 Due within \(days) days (\(upcomingTasks.count))\(reset)")
            for (task, label) in upcomingTasks {
                printDueTask(task, label: label, red: red, dim: dim, reset: reset)
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
    }

    /// Formats and prints a single due task line.
    private func printDueTask(
        _ task: ForgeTask, label: String,
        red: String, dim: String, reset: String
    ) {
        let dueStr = task.dueDateString ?? ""
        let ctxLabel = task.context.map { " \(dim)@\($0)\(reset)" } ?? ""
        let waitLabel = task.waitingOn.map { " \(dim)⏳\($0)\(reset)" } ?? ""
        let repeatLabel = task.repeatRule.map { " \(dim)↻\($0.serialise())\(reset)" } ?? ""
        let idLabel = " \(dim)[\(task.id)]\(reset)"
        print("  \(task.text) \(dim)due \(dueStr)\(reset) \(dim)← \(label)\(reset)\(ctxLabel)\(waitLabel)\(repeatLabel)\(idLabel)")
    }
}
