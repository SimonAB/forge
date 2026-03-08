import Foundation

/// Parses and writes TASKS.md files with inline tags and HTML comment IDs.
///
/// Expected format:
/// ```
/// ## Next Actions
/// - [ ] Do something @due(2026-03-15) @ctx(lab) <!-- id:a1b2c3 -->
///   > Optional notes for this task (blockquote style).
///
/// ## Waiting For
/// - [ ] Something from John @waiting(John) @since(2026-03-01) <!-- id:d4e5f6 -->
///
/// ## Completed
/// - [x] Done thing @done(2026-03-01) <!-- id:g7h8i9 -->
///
/// ## Notes
/// - Reference info
/// ```
public struct MarkdownIO: Sendable {

    /// Maximum file size (bytes) to load for parsing; larger files are skipped to avoid excessive memory use.
    public static let maxTaskFileSizeBytes: Int = 5 * 1024 * 1024  // 5 MB

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    public init() {}

    // MARK: - Parsing

    /// Parse a TASKS.md file and return all tasks found.
    /// Files larger than `maxTaskFileSizeBytes` are not loaded; returns an empty array.
    public func parseTasks(at path: String, projectName: String? = nil) throws -> [ForgeTask] {
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard size <= Self.maxTaskFileSizeBytes else { return [] }
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return parseTasks(from: content, projectName: projectName)
    }

    /// Parse frontmatter and tasks from a markdown file at the given path.
    /// Files larger than `maxTaskFileSizeBytes` are not loaded; returns (nil, []).
    public func parseFile(at path: String, projectName: String? = nil) throws
        -> (frontmatter: Frontmatter?, tasks: [ForgeTask])
    {
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard size <= Self.maxTaskFileSizeBytes else { return (nil, []) }
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let (fm, body) = Frontmatter.parse(from: content)
        let tasks = parseTasks(from: body, projectName: projectName)
        return (fm, tasks)
    }

    /// Parse tasks from markdown content string.
    ///
    /// Rollup sections (`<!-- forge:rollup -->` … `<!-- /forge:rollup -->`) are
    /// stripped before parsing to avoid double-counting project tasks that are
    /// mirrored into area files.
    /// Note lines are indented and start with `>` (blockquote style), e.g. `  > note text`.
    public func parseTasks(from content: String, projectName: String? = nil) -> [ForgeTask] {
        let (_, body) = Frontmatter.parse(from: content)
        let cleaned = Self.stripRollup(body)
        let lines = cleaned.components(separatedBy: .newlines)
        var currentSection: ForgeTask.Section = .nextActions
        var tasks: [ForgeTask] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                let heading = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if let section = parseSection(heading) {
                    currentSection = section
                }
                i += 1
                continue
            }

            if currentSection == .notes {
                i += 1
                continue
            }

            if let task = parseTaskLine(trimmed, section: currentSection, projectName: projectName) {
                var taskWithNotes = task
                var notesLines: [String] = []
                i += 1
                while i < lines.count {
                    let next = lines[i]
                    let (isNoteLine, noteContent) = Self.parseNoteLine(next)
                    if isNoteLine {
                        notesLines.append(noteContent)
                        i += 1
                    } else if next.trimmingCharacters(in: .whitespaces).isEmpty && !notesLines.isEmpty {
                        notesLines.append("")
                        i += 1
                    } else {
                        break
                    }
                }
                if !notesLines.isEmpty {
                    taskWithNotes.notes = notesLines.joined(separator: "\n")
                }
                tasks.append(taskWithNotes)
            } else {
                i += 1
            }
        }

        return tasks
    }

    /// True if the line is an indented blockquote (note); returns (true, content) or (false, "").
    private static func parseNoteLine(_ line: String) -> (Bool, String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return (false, "") }
        guard line.hasPrefix("  ") || line.hasPrefix("\t") else { return (false, "") }
        let afterIndent = line.drop(while: { $0 == " " || $0 == "\t" })
        guard afterIndent.hasPrefix(">") else { return (false, "") }
        let content = afterIndent.dropFirst().trimmingCharacters(in: .whitespaces)
        return (true, String(content))
    }

    /// Create a new empty TASKS.md file with section headers.
    public func createEmptyTasksFile(at path: String) throws {
        let content = """
        ## Next Actions

        ## Waiting For

        ## Completed

        ## Notes

        """
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Append a task to the correct section of a TASKS.md file.
    /// Creates the file if it doesn't exist. Updates `date_modified` in frontmatter.
    public func appendTask(_ task: ForgeTask, toFileAt path: String) throws {
        if !FileManager.default.fileExists(atPath: path) {
            try createEmptyTasksFile(at: path)
        }

        let raw = try String(contentsOfFile: path, encoding: .utf8)
        let (frontmatter, body) = Frontmatter.parse(from: raw)

        var content = body
        let taskBlock = formatTaskBlock(task)
        let sectionHeader = "## \(task.section.rawValue)"

        if let range = content.range(of: sectionHeader) {
            var insertionPoint = range.upperBound
            let remaining = content[insertionPoint...]
            if let nextNewline = remaining.firstIndex(of: "\n") {
                insertionPoint = content.index(after: nextNewline)
            }
            content.insert(contentsOf: taskBlock + "\n", at: insertionPoint)
        } else {
            content += "\n\(sectionHeader)\n\(taskBlock)\n"
        }

        let output = Self.reassemble(frontmatter: frontmatter?.touchingModified(), body: content)
        try output.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Mark a task as completed in a TASKS.md file by its ID.
    /// Checks the checkbox and adds @done(date). Moves to Completed section.
    /// Matches both unchecked (- [ ]) and already-checked (- [x]) lines so that
    /// editor-toggled tasks are still moved to Completed and get @done when forge done runs.
    /// For repeating tasks, spawns a new instance with the next due date.
    /// Updates `date_modified` in frontmatter.
    public func completeTask(withID taskID: String, inFileAt path: String) throws -> Bool {
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        let idMarker = "<!-- id:\(taskID) -->"

        guard raw.contains(idMarker) else { return false }

        let (frontmatter, body) = Frontmatter.parse(from: raw)
        let lines = body.components(separatedBy: "\n")
        var newLines: [String] = []
        var completedBlock: String?
        var matchedTask: ForgeTask?
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let isUnchecked = line.contains("- [ ]")
            let isChecked = line.contains("- [x]") || line.contains("- [X]")
            if line.contains(idMarker) && (isUnchecked || isChecked) {
                matchedTask = parseTaskLine(line, section: .nextActions, projectName: nil)

                var modified = line
                if isUnchecked {
                    modified = modified.replacingOccurrences(of: "- [ ]", with: "- [x]")
                }
                let today = Self.dateFormatter.string(from: Date())
                if !modified.contains("@done(") {
                    modified = modified.replacingOccurrences(
                        of: idMarker,
                        with: "@done(\(today)) \(idMarker)"
                    )
                }
                var block = modified
                i += 1
                while i < lines.count {
                    let next = lines[i]
                    let (isNote, _) = Self.parseNoteLine(next)
                    let isEmpty = next.trimmingCharacters(in: .whitespaces).isEmpty
                    if isNote || (isEmpty && block.contains("\n")) {
                        block += "\n" + next
                        i += 1
                    } else if isEmpty {
                        i += 1
                    } else {
                        break
                    }
                }
                completedBlock = block
            } else {
                newLines.append(line)
                i += 1
            }
        }

        guard let movedBlock = completedBlock else { return false }

        var result = newLines.joined(separator: "\n")

        // Spawn next instance for repeating tasks, preserving the defer-to-due gap.
        if let task = matchedTask, let rule = task.repeatRule {
            let today = Date()
            let nextDue = rule.nextDueDate(previousDue: task.dueDate, completionDate: today)
            var nextTask = task
            nextTask.id = ForgeTask.newID()
            nextTask.isCompleted = false
            nextTask.doneDate = nil
            nextTask.dueDate = nextDue

            if let deferDate = task.deferDate, let dueDate = task.dueDate {
                let gap = Calendar.current.dateComponents(
                    [.day], from: dueDate, to: deferDate
                ).day ?? 0
                nextTask.deferDate = Calendar.current.date(byAdding: .day, value: gap, to: nextDue)
            } else if task.deferDate != nil {
                nextTask.deferDate = rule.nextDueDate(previousDue: task.deferDate, completionDate: today)
            }

            let nextLine = formatTaskLine(nextTask)
            result = insertLineIntoSection(nextLine, section: "## Next Actions", body: result)
        }

        let completedHeader = "## Completed"

        if let range = result.range(of: completedHeader) {
            var insertionPoint = range.upperBound
            let remaining = result[insertionPoint...]
            if let nextNewline = remaining.firstIndex(of: "\n") {
                insertionPoint = result.index(after: nextNewline)
            }
            result.insert(contentsOf: movedBlock + "\n", at: insertionPoint)
        } else {
            result += "\n\(completedHeader)\n\(movedBlock)\n"
        }

        let output = Self.reassemble(frontmatter: frontmatter?.touchingModified(), body: result)
        try output.write(toFile: path, atomically: true, encoding: .utf8)
        return true
    }

    /// Remove a task from a markdown file by its ID (e.g. when merging duplicate tasks from Reminders).
    /// Removes the task line and any following note lines (indented blockquote). Returns true if the task was found and removed.
    /// Updates `date_modified` in frontmatter.
    public func removeTask(withID taskID: String, inFileAt path: String) throws -> Bool {
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        let idMarker = "<!-- id:\(taskID) -->"

        guard raw.contains(idMarker) else { return false }

        let (frontmatter, body) = Frontmatter.parse(from: raw)
        let lines = body.components(separatedBy: "\n")
        var newLines: [String] = []
        var found = false
        var i = 0

        while i < lines.count {
            let line = lines[i]
            if line.contains(idMarker) {
                found = true
                i += 1
                while i < lines.count {
                    let next = lines[i]
                    let (isNote, _) = Self.parseNoteLine(next)
                    if isNote {
                        i += 1
                    } else if next.trimmingCharacters(in: .whitespaces).isEmpty {
                        i += 1
                    } else {
                        break
                    }
                }
            } else {
                newLines.append(line)
                i += 1
            }
        }

        guard found else { return false }

        let result = newLines.joined(separator: "\n")
        let output = Self.reassemble(frontmatter: frontmatter?.touchingModified(), body: result)
        try output.write(toFile: path, atomically: true, encoding: .utf8)
        return true
    }

    /// Update a task's due date in a markdown file by its ID (e.g. when the date was changed in Calendar).
    /// Updates the @due(...) tag and touches `date_modified` in frontmatter. Returns true if the task was found and updated.
    public func updateTaskDueDate(withID taskID: String, to date: Date, inFileAt path: String) throws -> Bool {
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        let idMarker = "<!-- id:\(taskID) -->"

        guard raw.contains(idMarker) else { return false }

        let (frontmatter, body) = Frontmatter.parse(from: raw)
        let lines = body.components(separatedBy: "\n")
        var updated = false
        var newLines: [String] = []
        var currentSection: ForgeTask.Section = .nextActions

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                let heading = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if let section = parseSection(heading) {
                    currentSection = section
                }
                newLines.append(line)
                continue
            }

            if line.contains(idMarker), let task = parseTaskLine(line, section: currentSection, projectName: nil) {
                var revised = task
                revised.dueDate = date
                newLines.append(formatTaskLine(revised))
                updated = true
            } else {
                newLines.append(line)
            }
        }

        guard updated else { return false }

        let result = newLines.joined(separator: "\n")
        let output = Self.reassemble(frontmatter: frontmatter?.touchingModified(), body: result)
        try output.write(toFile: path, atomically: true, encoding: .utf8)
        return true
    }

    /// Insert a line into a named section, or create the section if it does not exist.
    private func insertLineIntoSection(_ line: String, section header: String, body: String) -> String {
        var result = body
        if let range = result.range(of: header) {
            var insertionPoint = range.upperBound
            let remaining = result[insertionPoint...]
            if let nextNewline = remaining.firstIndex(of: "\n") {
                insertionPoint = result.index(after: nextNewline)
            }
            result.insert(contentsOf: line + "\n", at: insertionPoint)
        } else {
            result += "\n\(header)\n\(line)\n"
        }
        return result
    }

    // MARK: - Private Parsing Helpers

    /// Remove the auto-generated rollup section so its mirrored tasks are not parsed.
    static func stripRollup(_ text: String) -> String {
        guard let startRange = text.range(of: "<!-- forge:rollup -->"),
              let endRange = text.range(of: "<!-- /forge:rollup -->") else {
            return text
        }
        var result = text
        result.removeSubrange(startRange.lowerBound ..< endRange.upperBound)
        return result
    }

    private func parseSection(_ heading: String) -> ForgeTask.Section? {
        let lower = heading.lowercased()
        if lower.contains("next action") { return .nextActions }
        if lower.contains("waiting") { return .waitingFor }
        if lower.contains("completed") || lower.contains("done") { return .completed }
        if lower.contains("note") { return .notes }
        return nil
    }

    private func parseTaskLine(
        _ line: String, section: ForgeTask.Section, projectName: String?
    ) -> ForgeTask? {
        guard line.hasPrefix("- [") else { return nil }

        let isCompleted = line.hasPrefix("- [x]") || line.hasPrefix("- [X]")
        guard line.count > 5 else { return nil }

        let idPattern = /<!--\s*id:(\w+)\s*-->/
        let id: String
        if let match = line.firstMatch(of: idPattern) {
            id = String(match.1)
        } else {
            id = ForgeTask.newID()
        }

        var text = line
        text = text.replacingOccurrences(of: "- [x] ", with: "")
        text = text.replacingOccurrences(of: "- [X] ", with: "")
        text = text.replacingOccurrences(of: "- [ ] ", with: "")

        text = text.replacing(/<!--\s*id:\w+\s*-->/, with: "")
        text = text.trimmingCharacters(in: .whitespaces)

        let dueDate = extractDate(tag: "due", from: text)
        let deferDate = extractDate(tag: "defer", from: text)
        let context = extractValue(tag: "ctx", from: text)
        let energy = extractValue(tag: "energy", from: text)
        let waitingOn = extractValue(tag: "waiting", from: text)
        let sinceDate = extractDate(tag: "since", from: text)
        let doneDate = extractDate(tag: "done", from: text)
        let source = extractValue(tag: "source", from: text)
        let repeatRule: RepeatRule? = extractValue(tag: "repeat", from: text).flatMap {
            RepeatRule.parse($0)
        }

        let cleanText = text
            .replacing(/@\w+\([^)]*\)/, with: "")
            .trimmingCharacters(in: .whitespaces)

        return ForgeTask(
            id: id,
            text: cleanText,
            isCompleted: isCompleted,
            section: section,
            dueDate: dueDate,
            context: context,
            energy: energy,
            waitingOn: waitingOn,
            sinceDate: sinceDate,
            doneDate: doneDate,
            source: source,
            deferDate: deferDate,
            repeatRule: repeatRule,
            projectName: projectName
        )
    }

    private func extractValue(tag: String, from text: String) -> String? {
        let pattern = try! Regex("@\(tag)\\(([^)]*)\\)")
        guard let match = text.firstMatch(of: pattern) else { return nil }
        return String(match.output[1].substring!)
    }

    private func extractDate(tag: String, from text: String) -> Date? {
        guard let value = extractValue(tag: tag, from: text) else { return nil }
        return Self.dateFormatter.date(from: value)
    }

    /// Reassemble a markdown file from optional frontmatter and body content.
    static func reassemble(frontmatter: Frontmatter?, body: String) -> String {
        guard let fm = frontmatter else { return body }
        return fm.serialise() + "\n" + body
    }

    // MARK: - Formatting

    /// Format a task as a markdown line with inline tags and ID comment.
    public func formatTaskLine(_ task: ForgeTask) -> String {
        let checkbox = task.isCompleted ? "- [x]" : "- [ ]"
        var parts = ["\(checkbox) \(task.text)"]

        if let date = task.deferDate {
            parts.append("@defer(\(Self.dateFormatter.string(from: date)))")
        }
        if let date = task.dueDate {
            parts.append("@due(\(Self.dateFormatter.string(from: date)))")
        }
        if let ctx = task.context {
            parts.append("@ctx(\(ctx))")
        }
        if let energy = task.energy {
            parts.append("@energy(\(energy))")
        }
        if let waiting = task.waitingOn {
            parts.append("@waiting(\(waiting))")
        }
        if let since = task.sinceDate {
            parts.append("@since(\(Self.dateFormatter.string(from: since)))")
        }
        if let rule = task.repeatRule {
            parts.append("@repeat(\(rule.serialise()))")
        }
        if let done = task.doneDate {
            parts.append("@done(\(Self.dateFormatter.string(from: done)))")
        }

        parts.append("<!-- id:\(task.id) -->")
        return parts.joined(separator: " ")
    }

    /// Format a task as a markdown block: task line plus optional notes (indented `>` blockquote lines).
    func formatTaskBlock(_ task: ForgeTask) -> String {
        var out = formatTaskLine(task)
        if let notes = task.notes, !notes.isEmpty {
            let quoted = notes.components(separatedBy: .newlines).map { line in
                line.isEmpty ? "  >" : "  > \(line)"
            }.joined(separator: "\n")
            out += "\n" + quoted
        }
        return out
    }
}
