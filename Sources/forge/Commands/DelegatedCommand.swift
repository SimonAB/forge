import ArgumentParser
import Foundation
import ForgeCore

struct DelegatedCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delegated",
        abstract: "List all delegated tasks grouped by assignee."
    )

    @Option(name: .long, help: "Focus on a specific tag (e.g. work, personal). Overrides persistent focus.")
    var focus: String?

    @Option(name: .long, help: "Restrict output to a single assignee name (matches #Person tags and waiting-on names, case-insensitive).")
    var assignee: String?

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let scanner = WorkspaceScanner(config: config)
        let markdownIO = MarkdownIO()

        let dim = "\u{1B}[2m"
        let bold = "\u{1B}[1m"
        let reset = "\u{1B}[0m"

        let activeFocus = focus ?? ConfigLoader.currentFocus(forgeDir: forgeDir)
        let showProjects = ConfigLoader.includesProjects(focusTag: activeFocus, config: config)

        if let tag = activeFocus {
            print("\(dim)Focus: \(tag)\(reset)\n")
        }

        let assigneeNeedle: String? = {
            guard let value = assignee, !value.isEmpty else { return nil }
            return value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .lowercased()
        }()

        // Map from assignee identifier → [(label, task)]
        var grouped: [String: [(label: String, task: ForgeTask)]] = [:]

        if showProjects {
            let projects = try await scanner.scanProjects()
            for proj in projects {
                let tasksPath = (proj.path as NSString).appendingPathComponent("TASKS.md")
                guard FileManager.default.fileExists(atPath: tasksPath) else { continue }

                let tasks = (try? markdownIO.parseTasks(at: tasksPath, projectName: proj.name)) ?? []
                collectDelegatedTasks(
                    from: tasks,
                    label: proj.name,
                    assigneeNeedle: assigneeNeedle,
                    into: &grouped
                )
            }
        }

        let areas = ConfigLoader.areaFiles(forgeDir: forgeDir, focusTag: activeFocus)
        for area in areas {
            let content = (try? String(contentsOfFile: area.path, encoding: .utf8)) ?? ""
            let tasks = markdownIO.parseTasks(from: content, projectName: area.name)
            collectDelegatedTasks(
                from: tasks,
                label: area.name,
                assigneeNeedle: assigneeNeedle,
                into: &grouped
            )
        }

        if grouped.isEmpty {
            print("No delegated tasks found.")
            return
        }

        print("\(bold)Delegated tasks by assignee\(reset)\n")

        for assigneeName in grouped.keys.sorted(by: { $0.lowercased() < $1.lowercased() }) {
            print("\(bold)\(assigneeName)\(reset)")

            // Group this assignee's tasks by label (project/area)
            var byLabel: [String: [ForgeTask]] = [:]
            for entry in grouped[assigneeName] ?? [] {
                byLabel[entry.label, default: []].append(entry.task)
            }

            for label in byLabel.keys.sorted(by: { $0.lowercased() < $1.lowercased() }) {
                print("  \(dim)← \(label)\(reset)")
                for task in byLabel[label]!.sorted(by: { $0.text.lowercased() < $1.text.lowercased() }) {
                    let dueLabel: String
                    if task.isOverdue {
                        dueLabel = " \(dim)OVERDUE \(task.dueDateString ?? "")\(reset)"
                    } else if task.isDueToday {
                        dueLabel = " \(dim)TODAY\(reset)"
                    } else if let due = task.dueDateString {
                        dueLabel = " \(dim)due \(due)\(reset)"
                    } else {
                        dueLabel = ""
                    }
                    let ctxLabel = task.context.map { " \(dim)@\($0)\(reset)" } ?? ""
                    let waitLabel = task.waitingOn.map { " \(dim)⏳\($0)\(reset)" } ?? ""
                    let idLabel = " \(dim)[\(task.id)]\(reset)"
                    print("    • \(task.text)\(dueLabel)\(ctxLabel)\(waitLabel)\(idLabel)")
                }
            }

            print()
        }
    }

    private func collectDelegatedTasks(
        from tasks: [ForgeTask],
        label: String,
        assigneeNeedle: String?,
        into grouped: inout [String: [(label: String, task: ForgeTask)]]
    ) {
        for task in tasks where !task.isCompleted && !task.isDeferred {
            let identifiers = task.allAssigneeIdentifiers
            guard !identifiers.isEmpty else { continue }

            let canonicalIdentifiers = identifiers.map {
                $0
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            }.filter { !$0.isEmpty }

            guard !canonicalIdentifiers.isEmpty else { continue }

            if let needle = assigneeNeedle {
                let matches = canonicalIdentifiers.contains { $0.lowercased() == needle }
                if !matches { continue }
            }

            for name in canonicalIdentifiers {
                grouped[name, default: []].append((label: label, task: task))
            }
        }
    }
}
