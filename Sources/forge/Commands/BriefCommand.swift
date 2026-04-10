import ArgumentParser
import Foundation
import ForgeCore

/// Print a concise “morning brief” (commitments, inbox, and next actions).
///
/// This is designed to be pasted into an LLM chat to produce a short assistant-style greeting
/// and a proposed Top 3 for the day.
struct BriefCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "brief",
        abstract: "Print a concise morning brief for review."
    )

    @Option(name: .long, help: "Show tasks due within the next N days (default: 7).")
    var days: Int = 7

    @Option(name: .long, help: "Limit how many items are listed per section (default: 10).")
    var limit: Int = 10

    @Option(name: .long, help: "Focus on a specific tag (e.g. work, personal). Overrides persistent focus.")
    var focus: String?

    enum IDFormat: String, ExpressibleByArgument, CaseIterable {
        case brackets
        case comment
        case both
    }

    @Option(name: .long, help: "How to render task IDs: brackets, comment, or both. Default: brackets.")
    var idFormat: IDFormat = .brackets

    @Flag(name: .long, inversion: .prefixedNo, help: "Show the source file path for each task. Default: off.")
    var paths = false

    enum PathFormat: String, ExpressibleByArgument, CaseIterable {
        case relative
        case absolute
    }

    @Option(name: .long, help: "How to render file paths when --paths is enabled: relative or absolute. Default: relative.")
    var pathFormat: PathFormat = .relative

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

        let now = Date()
        let dateLabel = Self.briefDateFormatter.string(from: now)
        print("\n\(bold)Good morning.\(reset) \(dim)\(dateLabel)\(reset)")
        let pathsArg = paths ? " --paths" : ""
        let pathFormatArg = paths ? " --path-format \(pathFormat.rawValue)" : ""
        print("\(dim)Command: forge brief --days \(days) --limit \(limit) --id-format \(idFormat.rawValue)\(pathsArg)\(pathFormatArg)\(reset)")
        if paths && pathFormat == .absolute {
            print("\(dim)Forge dir:\(reset) \(forgeDir)")
            let roots = config.resolvedProjectRoots
            if !roots.isEmpty {
                print("\(dim)Project roots:\(reset) \(roots.joined(separator: ", "))")
            }
        }
        print()

        let activeFocus = focus ?? ConfigLoader.currentFocus(forgeDir: forgeDir)
        let showProjects = ConfigLoader.includesProjects(focusTag: activeFocus, config: config)
        if let tag = activeFocus {
            print("\(dim)Focus: \(tag)\(reset)\n")
        }

        let inboxPath = ConfigLoader.inboxPath(forgeDir: forgeDir)
        let inboxPathLabel = paths ? " \(dim)\(formatPath(inboxPath, config: config, forgeDir: forgeDir))\(reset)" : ""
        let inboxTasks: [ForgeTask] = {
            guard FileManager.default.fileExists(atPath: inboxPath) else { return [] }
            let content = (try? String(contentsOfFile: inboxPath, encoding: .utf8)) ?? ""
            return markdownIO.parseTasks(from: content, projectName: "Inbox")
                .filter { !$0.isCompleted }
        }()

        // Collect tasks across active projects and selected areas.
        var taskSources: [(label: String, sourcePath: String, tasks: [ForgeTask])] = []

        if showProjects {
            let projects = try await scanner.scanProjects()
            let activeProjects = projects.filter { p in
                p.column != nil && p.column != "Shipped" && p.column != "Paused"
            }
            for proj in activeProjects {
                let tasksPath = (proj.path as NSString).appendingPathComponent("TASKS.md")
                guard FileManager.default.fileExists(atPath: tasksPath) else { continue }
                let tasks = (try? markdownIO.parseTasks(at: tasksPath, projectName: proj.name)) ?? []
                taskSources.append((label: proj.name, sourcePath: tasksPath, tasks: tasks))
            }
        }

        let areas = ConfigLoader.areaFiles(forgeDir: forgeDir, focusTag: activeFocus)
        for area in areas {
            guard area.name != "Inbox" else { continue }
            let content = (try? String(contentsOfFile: area.path, encoding: .utf8)) ?? ""
            let tasks = markdownIO.parseTasks(from: content, projectName: area.name)
            taskSources.append((label: area.name, sourcePath: area.path, tasks: tasks))
        }

        let flatNextActions = taskSources.flatMap { source in
            source.tasks
                .filter { !$0.isCompleted && $0.section == .nextActions && !$0.isDeferred }
                .map { (task: $0, label: source.label, sourcePath: source.sourcePath) }
        }

        let flatWaiting = taskSources.flatMap { source in
            source.tasks
                .filter { !$0.isCompleted && $0.section == .waitingFor && !$0.isDeferred }
                .map { (task: $0, label: source.label, sourcePath: source.sourcePath) }
        }

        // Due / commitments view (based on @due).
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: days, to: todayStart) ?? now

        let dueItems = taskSources.flatMap { source in
            source.tasks
                .filter { !$0.isCompleted && $0.dueDate != nil }
                .map { (task: $0, label: source.label, sourcePath: source.sourcePath) }
        }

        let overdue = dueItems.filter { $0.task.isOverdue }
            .sorted(by: { ($0.task.dueDate ?? .distantPast) < ($1.task.dueDate ?? .distantPast) })

        let dueToday = dueItems.filter { $0.task.isDueToday }
            .sorted(by: { ($0.task.dueDate ?? .distantPast) < ($1.task.dueDate ?? .distantPast) })

        let upcoming = dueItems.filter { item in
            guard let due = item.task.dueDate else { return false }
            return !item.task.isOverdue && !item.task.isDueToday && due <= horizon
        }
        .sorted(by: { ($0.task.dueDate ?? .distantFuture) < ($1.task.dueDate ?? .distantFuture) })

        print("\(bold)Commitments\(reset) \(dim)(from @due)\(reset)")
        if overdue.isEmpty && dueToday.isEmpty && upcoming.isEmpty {
            print("  \(green)✓\(reset) Nothing overdue or due soon")
        } else {
            if !overdue.isEmpty {
                print("  \(red)Overdue (\(overdue.count))\(reset)")
                for item in overdue.prefix(max(0, limit)) {
                    print("    \(red)▸\(reset) \(formatLine(item.task, label: item.label, dim: dim, reset: reset))")
                }
            }
            if !dueToday.isEmpty {
                print("  \(yellow)Due today (\(dueToday.count))\(reset)")
                for item in dueToday.prefix(max(0, limit)) {
                    print("    \(yellow)▸\(reset) \(formatLine(item.task, label: item.label, dim: dim, reset: reset))")
                }
            }
            if !upcoming.isEmpty {
                print("  \(cyan)Due within \(days) days (\(upcoming.count))\(reset)")
                for item in upcoming.prefix(max(0, limit)) {
                    print("    \(cyan)▸\(reset) \(formatLine(item.task, label: item.label, dim: dim, reset: reset))")
                }
            }
        }
        print()

        print("\(bold)Inbox\(reset)")
        if inboxTasks.isEmpty {
            print("  \(green)✓\(reset) Inbox is empty")
        } else {
            print("  \(yellow)!\(reset) \(inboxTasks.count) item\(inboxTasks.count == 1 ? "" : "s") to process \(dim)(run: forge process)\(reset)")
            if paths {
                print("  \(dim)File:\(reset)\(inboxPathLabel)")
            }
            for task in inboxTasks.prefix(max(0, limit)) {
                print("    • \(task.text) \(dim)\(formatID(task.id))\(reset)")
            }
        }
        print()

        // Suggested “today candidates”: prioritise overdue, then due today, then due soon, then everything else.
        let candidates = flatNextActions.sorted { a, b in
            let aRank = rank(task: a.task, horizon: horizon)
            let bRank = rank(task: b.task, horizon: horizon)
            if aRank != bRank { return aRank < bRank }
            let aDue = a.task.dueDate ?? .distantFuture
            let bDue = b.task.dueDate ?? .distantFuture
            if aDue != bDue { return aDue < bDue }
            return a.task.text.lowercased() < b.task.text.lowercased()
        }

        print("\(bold)Next actions (top candidates)\(reset)")
        if candidates.isEmpty {
            print("  \(yellow)!\(reset) No next actions found \(dim)(add with: forge add <project> \"task\")\(reset)")
        } else {
            for item in candidates.prefix(max(0, limit)) {
                let ctxLabel = item.task.context.map { "\(dim)@ctx(\($0))\(reset)" } ?? ""
                let dueLabel = item.task.dueDateString.map { "\(dim)due \($0)\(reset)" } ?? ""
                let parts = [dueLabel, ctxLabel].filter { !$0.isEmpty }.joined(separator: " ")
                let suffix = parts.isEmpty ? "" : " \(parts)"
                let pathSuffix = paths ? " \(dim)\(formatPath(item.sourcePath, config: config, forgeDir: forgeDir))\(reset)" : ""
                print("  • \(item.task.text)\(suffix) \(dim)← \(item.label)\(reset) \(dim)\(formatID(item.task.id))\(reset)\(pathSuffix)")
            }
        }
        print()

        print("\(bold)Waiting for\(reset)")
        if flatWaiting.isEmpty {
            print("  \(green)✓\(reset) No waiting items")
        } else {
            print("  \(flatWaiting.count) item\(flatWaiting.count == 1 ? "" : "s")")
            for item in flatWaiting.prefix(max(0, limit)) {
                let who = item.task.waitingOn ?? "?"
                let since = item.task.sinceDate.map { " since \(ForgeTask.dateString(from: $0))" } ?? ""
                let pathSuffix = paths ? " \(dim)\(formatPath(item.sourcePath, config: config, forgeDir: forgeDir))\(reset)" : ""
                print("  ⏳ \(item.task.text) \(dim)← \(who)\(since)\(reset) \(dim)← \(item.label)\(reset) \(dim)\(formatID(item.task.id))\(reset)\(pathSuffix)")
            }
        }
        print()

        let contextSuggestion = suggestContext(from: candidates.map(\.task))
        if let suggestion = contextSuggestion {
            print("\(dim)Suggested first batch:\(reset) \(bold)@ctx(\(suggestion))\(reset)")
        }
        print("\(dim)Suggested next step:\(reset) pick a Top 3, then start the first one.")
        print("\(dim)After editing tasks:\(reset) run \(bold)forge sync\(reset) to keep Reminders and indexes up to date.\n")
    }

    private func formatLine(_ task: ForgeTask, label: String, dim: String, reset: String) -> String {
        // This is used for the Commitments section only; keep it dense.
        let due = task.dueDateString.map { "\(dim)due \($0)\(reset)" } ?? ""
        let ctx = task.context.map { " \(dim)@ctx(\($0))\(reset)" } ?? ""
        return "\(task.text) \(dim)← \(label)\(reset) \(due)\(ctx) \(dim)\(formatID(task.id))\(reset)"
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private func formatID(_ id: String) -> String {
        switch idFormat {
        case .brackets:
            return "[\(id)]"
        case .comment:
            return "<!-- id:\(id) -->"
        case .both:
            return "[\(id)] <!-- id:\(id) -->"
        }
    }

    /// Prefer a relative path rooted at one of the configured project roots or at the Forge directory's parent.
    private func formatPath(_ path: String, config: ForgeConfig, forgeDir: String) -> String {
        if pathFormat == .absolute {
            return (path as NSString).standardizingPath
        }

        let candidates = config.resolvedProjectRoots + [(forgeDir as NSString).deletingLastPathComponent]
        let standardPath = (path as NSString).standardizingPath

        func makeRelative(to base: String) -> String? {
            let standardBase = (base as NSString).standardizingPath
            let prefix = standardBase.hasSuffix("/") ? standardBase : standardBase + "/"
            guard standardPath.hasPrefix(prefix) else { return nil }
            let rel = String(standardPath.dropFirst(prefix.count))
            return rel.isEmpty ? "." : rel
        }

        let rels = candidates.compactMap { makeRelative(to: $0) }
        if let best = rels.min(by: { $0.count < $1.count }) {
            return best
        }
        return standardPath
    }

    /// Lower rank means “more urgent / more relevant today”.
    private func rank(task: ForgeTask, horizon: Date) -> Int {
        if task.isOverdue { return 0 }
        if task.isDueToday { return 1 }
        if let due = task.dueDate, due <= horizon { return 2 }
        if task.context != nil { return 3 }
        return 4
    }

    /// Suggest a single context for the first work block, based on frequency.
    private func suggestContext(from tasks: [ForgeTask]) -> String? {
        let contexts = tasks.compactMap { $0.context?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !contexts.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for ctx in contexts {
            counts[ctx, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private static let briefDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE d MMM yyyy • HH:mm"
        return f
    }()
}

