import ArgumentParser
import Foundation
import ForgeCore

struct ReviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "Guided weekly review checklist."
    )

    mutating func run() throws {
        let config = try ConfigLoader.load()
        let scanner = WorkspaceScanner(config: config)
        let projects = try scanner.scanProjects()
        let markdownIO = MarkdownIO()

        let bold = "\u{1B}[1m"
        let dim = "\u{1B}[2m"
        let green = "\u{1B}[32m"
        let yellow = "\u{1B}[33m"
        let red = "\u{1B}[31m"
        let reset = "\u{1B}[0m"

        print("\n\(bold)═══ Forge Weekly Review ═══\(reset)\n")

        // Step 1: Inbox
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let inboxPath = (forgeDir as NSString).appendingPathComponent("inbox.md")
        let inboxTasks = FileManager.default.fileExists(atPath: inboxPath)
            ? markdownIO.parseTasks(from: (try? String(contentsOfFile: inboxPath, encoding: .utf8)) ?? "")
                .filter { !$0.isCompleted }
            : []

        print("\(bold)1. Inbox\(reset)")
        if inboxTasks.isEmpty {
            print("   \(green)✓\(reset) Inbox is empty")
        } else {
            print("   \(yellow)!\(reset) \(inboxTasks.count) items need processing — run \(dim)forge process\(reset)")
        }
        print()

        // Step 2: Overdue tasks
        var overdue: [(ForgeTask, String)] = []
        var dueThisWeek: [(ForgeTask, String)] = []
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date())!

        for proj in projects {
            let tasksPath = (proj.path as NSString).appendingPathComponent("TASKS.md")
            guard FileManager.default.fileExists(atPath: tasksPath) else { continue }
            let tasks = (try? markdownIO.parseTasks(at: tasksPath, projectName: proj.name)) ?? []
            for task in tasks where !task.isCompleted {
                if task.isOverdue {
                    overdue.append((task, proj.name))
                } else if let due = task.dueDate, due <= nextWeek {
                    dueThisWeek.append((task, proj.name))
                }
            }
        }

        for (areaPath, areaName) in ConfigLoader.areaTaskFiles(forgeDir: forgeDir) {
            let content = (try? String(contentsOfFile: areaPath, encoding: .utf8)) ?? ""
            let tasks = markdownIO.parseTasks(from: content, projectName: areaName)
            for task in tasks where !task.isCompleted {
                if task.isOverdue {
                    overdue.append((task, areaName))
                } else if let due = task.dueDate, due <= nextWeek {
                    dueThisWeek.append((task, areaName))
                }
            }
        }

        print("\(bold)2. Overdue\(reset)")
        if overdue.isEmpty {
            print("   \(green)✓\(reset) Nothing overdue")
        } else {
            for (task, proj) in overdue {
                print("   \(red)▸\(reset) \(task.text) \(dim)← \(proj) (due \(task.dueDateString ?? "?"))\(reset)")
            }
        }
        print()

        print("\(bold)3. Due this week\(reset)")
        if dueThisWeek.isEmpty {
            print("   \(green)✓\(reset) Nothing due this week")
        } else {
            for (task, proj) in dueThisWeek {
                print("   \(yellow)▸\(reset) \(task.text) \(dim)← \(proj) (due \(task.dueDateString ?? "?"))\(reset)")
            }
        }
        print()

        // Step 3: Waiting-for check
        var waitingItems: [(ForgeTask, String)] = []
        for proj in projects {
            let tasksPath = (proj.path as NSString).appendingPathComponent("TASKS.md")
            guard FileManager.default.fileExists(atPath: tasksPath) else { continue }
            let tasks = (try? markdownIO.parseTasks(at: tasksPath, projectName: proj.name)) ?? []
            waitingItems.append(contentsOf: tasks.filter { !$0.isCompleted && $0.section == .waitingFor }.map { ($0, proj.name) })
        }

        for (areaPath, areaName) in ConfigLoader.areaTaskFiles(forgeDir: forgeDir) {
            let content = (try? String(contentsOfFile: areaPath, encoding: .utf8)) ?? ""
            let tasks = markdownIO.parseTasks(from: content, projectName: areaName)
            waitingItems.append(contentsOf: tasks.filter { !$0.isCompleted && $0.section == .waitingFor }.map { ($0, areaName) })
        }

        print("\(bold)4. Waiting for\(reset)")
        if waitingItems.isEmpty {
            print("   \(green)✓\(reset) No pending delegations")
        } else {
            for (task, proj) in waitingItems {
                let person = task.waitingOn ?? "?"
                print("   \(yellow)⏳\(reset) \(task.text) \(dim)← \(person) (\(proj))\(reset)")
            }
            print("   \(dim)Follow up on any stale items.\(reset)")
        }
        print()

        // Step 4: Active projects review
        let active = projects.filter { p in
            p.column != nil && p.column != "Shipped" && p.column != "Paused"
        }
        let withoutTasks = active.filter { proj in
            let tasksPath = (proj.path as NSString).appendingPathComponent("TASKS.md")
            if !FileManager.default.fileExists(atPath: tasksPath) { return true }
            let tasks = (try? markdownIO.parseTasks(at: tasksPath, projectName: proj.name)) ?? []
            return tasks.filter({ !$0.isCompleted && $0.section == .nextActions }).isEmpty
        }

        print("\(bold)5. Active projects without next actions\(reset)")
        if withoutTasks.isEmpty {
            print("   \(green)✓\(reset) All active projects have next actions")
        } else {
            for proj in withoutTasks {
                print("   \(yellow)!\(reset) \(proj.name) \(dim)(\(proj.column ?? "?"))\(reset) — needs a next action")
            }
        }
        print()

        // Step 6: Becoming actionable this week
        var becomingActionable: [(ForgeTask, String)] = []
        for proj in projects {
            let tasksPath = (proj.path as NSString).appendingPathComponent("TASKS.md")
            guard FileManager.default.fileExists(atPath: tasksPath) else { continue }
            let tasks = (try? markdownIO.parseTasks(at: tasksPath, projectName: proj.name)) ?? []
            for task in tasks where !task.isCompleted {
                if let d = task.deferDate, d > Date(), d <= nextWeek {
                    becomingActionable.append((task, proj.name))
                }
            }
        }
        for (areaPath, areaName) in ConfigLoader.areaTaskFiles(forgeDir: forgeDir) {
            let content = (try? String(contentsOfFile: areaPath, encoding: .utf8)) ?? ""
            let tasks = markdownIO.parseTasks(from: content, projectName: areaName)
            for task in tasks where !task.isCompleted {
                if let d = task.deferDate, d > Date(), d <= nextWeek {
                    becomingActionable.append((task, areaName))
                }
            }
        }

        let cyan = "\u{1B}[36m"
        print("\(bold)6. Becoming actionable this week\(reset)")
        if becomingActionable.isEmpty {
            print("   \(green)✓\(reset) No deferred tasks surfacing this week")
        } else {
            for (task, proj) in becomingActionable {
                print("   \(cyan)▸\(reset) \(task.text) \(dim)← \(proj) (available \(task.deferDateString ?? "?"))\(reset)")
            }
        }
        print()

        // Step 7: Stale areas
        let allAreas = ConfigLoader.scanAreaFiles(forgeDir: forgeDir)
        let staleAreas = allAreas.filter { $0.frontmatter?.isStale(days: 14) == true }

        print("\(bold)7. Neglected areas\(reset)")
        if staleAreas.isEmpty {
            print("   \(green)✓\(reset) All areas reviewed within the last 2 weeks")
        } else {
            for area in staleAreas {
                let days = area.frontmatter?.daysSinceModified ?? 0
                print("   \(yellow)!\(reset) \(area.name) \(dim)(not touched in \(days) days)\(reset)")
            }
            print("   \(dim)Consider reviewing these areas.\(reset)")
        }
        print()

        // Step 8: Someday/Maybe
        let somedayPath = (forgeDir as NSString).appendingPathComponent("someday-maybe.md")
        let somedayTasks = FileManager.default.fileExists(atPath: somedayPath)
            ? markdownIO.parseTasks(from: (try? String(contentsOfFile: somedayPath, encoding: .utf8)) ?? "")
                .filter { !$0.isCompleted }
            : []
        let pausedProjects = projects.filter { $0.column == "Paused" }

        print("\(bold)8. Someday/Maybe\(reset)")
        let somedayCount = somedayTasks.count + pausedProjects.count
        if somedayCount == 0 {
            print("   \(dim)No someday items or paused projects.\(reset)")
        } else {
            print("   \(somedayTasks.count) someday items, \(pausedProjects.count) paused projects")
            print("   \(dim)Review: anything ready to activate?\(reset)")
        }
        print()

        // Summary
        let untagged = projects.filter { $0.column == nil }.count
        print("\(bold)Summary\(reset)")
        print("  \(active.count) active projects, \(untagged) untagged")
        print("  \(overdue.count) overdue, \(dueThisWeek.count) due this week")
        print("  \(waitingItems.count) waiting, \(withoutTasks.count) projects need next actions")
        if !becomingActionable.isEmpty {
            print("  \(becomingActionable.count) deferred task\(becomingActionable.count == 1 ? "" : "s") surfacing this week")
        }
        if !staleAreas.isEmpty {
            print("  \(staleAreas.count) neglected area\(staleAreas.count == 1 ? "" : "s")")
        }
        print()
    }
}
