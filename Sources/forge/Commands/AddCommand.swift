import ArgumentParser
import Foundation
import ForgeCore

struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a task to a project's TASKS.md."
    )

    @Argument(help: "Project directory name (or a unique substring).")
    var project: String

    @Argument(help: "Task description. Inline tags like @due(2026-03-15) @ctx(lab) are parsed.")
    var text: [String]

    mutating func run() throws {
        let config = try ConfigLoader.load()
        let scanner = WorkspaceScanner(config: config)
        let projects = try scanner.scanProjects()

        guard let matched = findProject(named: project, in: projects) else {
            throw ValidationError(
                "No project matching '\(project)'. Use 'forge board --list' to see all projects."
            )
        }

        let fullText = text.joined(separator: " ")
        let markdownIO = MarkdownIO()
        let task = parseInlineTask(fullText)

        let tasksPath = (matched.path as NSString).appendingPathComponent("TASKS.md")
        try markdownIO.appendTask(task, toFileAt: tasksPath)

        let dueInfo = task.dueDate.map { " (due \(ForgeTask.dateString(from: $0)))" } ?? ""
        let deferInfo = task.deferDate.map { " (deferred until \(ForgeTask.dateString(from: $0)))" } ?? ""
        let ctxInfo = task.context.map { " @\($0)" } ?? ""
        let repeatInfo = task.repeatRule.map { " ↻ \($0.serialise())" } ?? ""
        print("Added to \(matched.name): \(task.text)\(deferInfo)\(dueInfo)\(ctxInfo)\(repeatInfo)")
        print("  id: \(task.id)")
    }

    private func parseInlineTask(_ text: String) -> ForgeTask {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var dueDate: Date?
        var deferDate: Date?
        var context: String?
        var energy: String?
        var waitingOn: String?
        var repeatRule: RepeatRule?
        var section: ForgeTask.Section = .nextActions

        if let match = text.firstMatch(of: /@due\(([^)]*)\)/) {
            dueDate = dateFormatter.date(from: String(match.1))
        }
        if let match = text.firstMatch(of: /@defer\(([^)]*)\)/) {
            deferDate = dateFormatter.date(from: String(match.1))
        }
        if let match = text.firstMatch(of: /@ctx\(([^)]*)\)/) {
            context = String(match.1)
        }
        if let match = text.firstMatch(of: /@energy\(([^)]*)\)/) {
            energy = String(match.1)
        }
        if let match = text.firstMatch(of: /@waiting\(([^)]*)\)/) {
            waitingOn = String(match.1)
            section = .waitingFor
        }
        if let match = text.firstMatch(of: /@repeat\(([^)]*)\)/) {
            repeatRule = RepeatRule.parse(String(match.1))
        }

        let cleanText = text
            .replacing(/@\w+\([^)]*\)/, with: "")
            .trimmingCharacters(in: .whitespaces)

        return ForgeTask(
            id: ForgeTask.newID(),
            text: cleanText,
            section: section,
            dueDate: dueDate,
            context: context,
            energy: energy,
            waitingOn: waitingOn,
            deferDate: deferDate,
            repeatRule: repeatRule
        )
    }

    private func findProject(named query: String, in projects: [Project]) -> Project? {
        let lower = query.lowercased()
        if let exact = projects.first(where: { $0.name.lowercased() == lower }) {
            return exact
        }
        let matches = projects.filter { $0.name.lowercased().contains(lower) }
        if matches.count == 1 { return matches.first }
        if matches.count > 1 {
            print("Ambiguous match for '\(query)':")
            for m in matches { print("  • \(m.name)") }
        }
        return nil
    }
}

extension ForgeTask {
    static func dateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
