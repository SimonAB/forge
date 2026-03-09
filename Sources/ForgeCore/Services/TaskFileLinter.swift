import Foundation

/// Linter for Forge task markdown files (TASKS.md and area .md files).
///
/// Enforces best practices: task IDs, canonical section headers, date formats,
/// and consistent formatting. Use with `forge lint` and `forge lint --fix`.
public struct TaskFileLinter: Sendable {

    /// A single lint issue.
    public struct Issue: Sendable {
        public let path: String
        public let line: Int
        public let ruleID: String
        public let message: String
        public let severity: Severity
        public let fixable: Bool

        public enum Severity: String, Sendable {
            case error
            case warning
        }
    }

    /// Canonical section headers in recommended order.
    public static let canonicalSections = [
        "Next Actions",
        "Waiting For",
        "Completed",
        "Notes",
    ]

    /// Derive the expected level-1 heading title from a markdown file path.
    /// E.g. `/path/to/inbox.md` -> `Inbox`, `someday-maybe.md` -> `Someday Maybe`,
    /// `/Projects/PGT/TASKS.md` -> `Pgt` (or preserves all-caps `PGT`).
    private static func expectedTitle(forPath path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let name = (path as NSString).lastPathComponent
        guard (name as NSString).pathExtension.lowercased() == "md" else { return nil }
        let stem = (name as NSString).deletingPathExtension
        let base: String
        if stem.lowercased() == "tasks" {
            let parentDir = (path as NSString).deletingLastPathComponent
            let parentName = (parentDir as NSString).lastPathComponent
            base = parentName
        } else {
            base = stem
        }
        let spaced = base
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let words = spaced.split(separator: " ")
        guard !words.isEmpty else { return nil }
        let title = words.map { word -> String in
            let s = String(word)
            let letters = s.filter { $0.isLetter }
            if !letters.isEmpty && letters.allSatisfy({ $0.isUppercase }) {
                return s
            }
            let lower = s.lowercased()
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
        return title
    }

    /// Maps a section heading to its canonical form and index (for order check). Returns nil if not a task section.
    private static func canonicalSection(for heading: String) -> (title: String, index: Int)? {
        let lower = heading.lowercased()
        if lower.contains("next action") { return ("Next Actions", 0) }
        if lower.contains("waiting") { return ("Waiting For", 1) }
        if lower.contains("completed") || lower.contains("done") { return ("Completed", 2) }
        if lower.contains("note") { return ("Notes", 3) }
        return nil
    }

    private let markdownIO: MarkdownIO

    public init(markdownIO: MarkdownIO = MarkdownIO()) {
        self.markdownIO = markdownIO
    }

    /// Lint a task file at the given path. Returns issues; does not modify the file.
    public func lint(path: String) -> [Issue] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [Issue(path: path, line: 1, ruleID: "read_error", message: "Could not read file.", severity: .error, fixable: false)]
        }
        return lint(content: content, path: path)
    }

    /// Lint markdown content. Use `path` for issue reporting.
    public func lint(content: String, path: String = "") -> [Issue] {
        let idPattern = /<!--\s*id:(\w+)\s*-->/
        let dateTagPattern = /@(due|defer|since|done)\(([^)]+)\)/
        let dateValuePattern = /^\d{4}-\d{2}-\d{2}$/

        enum Section {
            case other
            case completed
        }

        let (_, body) = Frontmatter.parse(from: content)
        let cleaned = MarkdownIO.stripRollup(body)
        let lines = cleaned.components(separatedBy: .newlines)
        var issues: [Issue] = []
        var sectionOrder: [(lineIndex: Int, title: String, canonicalIndex: Int)] = []
        var taskIDs: [String: Int] = [:]
        var i = 0
        var currentSection: Section = .other

        // Heading/title rule: require a level-1 heading that matches the file name.
        if let expectedTitle = Self.expectedTitle(forPath: path) {
            var firstNonEmptyIndex: Int?
            var firstH1Index: Int?
            var firstH1Text: String?

            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                firstNonEmptyIndex = idx
                if trimmed.hasPrefix("# ") {
                    firstH1Index = idx
                    firstH1Text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                break
            }

            if let h1Index = firstH1Index, let h1Text = firstH1Text {
                if h1Text != expectedTitle {
                    issues.append(Issue(
                        path: path,
                        line: h1Index + 1,
                        ruleID: "title_h1_mismatch",
                        message: "First heading should be \"# \(expectedTitle)\" to match the file name.",
                        severity: .warning,
                        fixable: true
                    ))
                }
            } else {
                let lineNum = (firstNonEmptyIndex ?? 0) + 1
                issues.append(Issue(
                    path: path,
                    line: lineNum,
                    ruleID: "missing_title_h1",
                    message: "Add a level-1 heading \"# \(expectedTitle)\" at the top of the file.",
                    severity: .warning,
                    fixable: true
                ))
            }
        }

        while i < lines.count {
            let lineNum = i + 1
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                let title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if let canonical = Self.canonicalSection(for: title) {
                    sectionOrder.append((i, title, canonical.index))
                    if title != canonical.title {
                        issues.append(Issue(
                            path: path, line: lineNum, ruleID: "section_casing",
                            message: "Use canonical header \"## \(canonical.title)\".",
                            severity: .warning, fixable: true
                        ))
                    }
                } else {
                    sectionOrder.append((i, title, -1))
                    issues.append(Issue(
                        path: path, line: lineNum, ruleID: "unknown_section",
                        message: "Section \"\(title)\" is not a standard task section (Next Actions, Waiting For, Completed, Notes).",
                        severity: .warning, fixable: false
                    ))
                }
                let lower = title.lowercased()
                if lower.contains("completed") || lower.contains("done") {
                    currentSection = .completed
                } else {
                    currentSection = .other
                }
                i += 1
                continue
            }

            if trimmed.hasPrefix("- [") && trimmed.count > 5 {
                if trimmed.contains("- [X]") {
                    issues.append(Issue(
                        path: path, line: lineNum, ruleID: "checkbox_casing",
                        message: "Use lowercase \"- [x]\" for completed tasks.",
                        severity: .warning, fixable: true
                    ))
                }
                if line.firstMatch(of: idPattern) == nil {
                    issues.append(Issue(
                        path: path, line: lineNum, ruleID: "missing_id",
                        message: "Task line should end with <!-- id:xxxxxx -->.",
                        severity: .error, fixable: true
                    ))
                } else if let match = line.firstMatch(of: idPattern) {
                    let id = String(match.1)
                    if id.count != 6 {
                        issues.append(Issue(
                            path: path, line: lineNum, ruleID: "id_format",
                            message: "Task ID should be 6 characters (e.g. <!-- id:a1b2c3 -->).",
                            severity: .warning, fixable: true
                        ))
                    }
                    if let prevLine = taskIDs[id] {
                        issues.append(Issue(
                            path: path, line: lineNum, ruleID: "duplicate_id",
                            message: "Duplicate task ID \"\(id)\" (also on line \(prevLine)).",
                            severity: .error, fixable: false
                        ))
                    } else {
                        taskIDs[id] = lineNum
                    }
                }
                let isChecked = trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")
                if isChecked && currentSection != .completed {
                    issues.append(Issue(
                        path: path,
                        line: lineNum,
                        ruleID: "completed_not_in_section",
                        message: "Completed task should be in the \"## Completed\" section with an @done date.",
                        severity: .warning,
                        fixable: true
                    ))
                }
                checkDateTags(in: line, path: path, lineNum: lineNum, dateTagPattern: dateTagPattern, dateValuePattern: dateValuePattern, issues: &issues)
            }

            i += 1
        }

        if !sectionOrder.isEmpty {
            var lastIndex = -1
            for item in sectionOrder where item.canonicalIndex >= 0 {
                if item.canonicalIndex < lastIndex {
                    let lineNum = item.lineIndex + 1
                    issues.append(Issue(
                        path: path, line: lineNum, ruleID: "section_order",
                        message: "Sections should appear in order: Next Actions, Waiting For, Completed, Notes.",
                        severity: .warning, fixable: true
                    ))
                    break
                }
                lastIndex = item.canonicalIndex
            }
        }

        // Spacing around headings: exactly one empty line before/after when surrounded by content.
        for idx in 0..<lines.count {
            let line = lines[idx]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }

            var prevNonEmptyIndex: Int?
            var j = idx - 1
            while j >= 0 {
                if !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    prevNonEmptyIndex = j
                    break
                }
                j -= 1
            }

            var nextNonEmptyIndex: Int?
            j = idx + 1
            while j < lines.count {
                if !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    nextNonEmptyIndex = j
                    break
                }
                j += 1
            }

            var needsSpacingFix = false

            if let prev = prevNonEmptyIndex {
                let gap = idx - prev - 1
                if gap != 1 {
                    needsSpacingFix = true
                }
            }
            if let next = nextNonEmptyIndex {
                let gap = next - idx - 1
                if gap != 1 {
                    needsSpacingFix = true
                }
            }

            if needsSpacingFix {
                issues.append(Issue(
                    path: path,
                    line: idx + 1,
                    ruleID: "spacing_heading",
                    message: "Headings should have exactly one empty line before and after when surrounded by content.",
                    severity: .warning,
                    fixable: true
                ))
            }
        }

        // Spacing between list items: no empty line between consecutive items.
        if lines.count >= 3 {
            for idx in 1..<(lines.count - 1) {
                let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { continue }
                if isListLine(lines[idx - 1]) && isListLine(lines[idx + 1]) {
                    issues.append(Issue(
                        path: path,
                        line: idx + 1,
                        ruleID: "spacing_list_items",
                        message: "Do not insert empty lines between list items within the same section.",
                        severity: .warning,
                        fixable: true
                    ))
                }
            }
        }

        if let last = content.last, last != "\n" && !content.isEmpty {
            issues.append(Issue(
                path: path, line: lines.count, ruleID: "trailing_newline",
                message: "File should end with a newline.",
                severity: .warning, fixable: true
            ))
        }

        return issues
    }

    private func checkDateTags(in line: String, path: String, lineNum: Int, dateTagPattern: Regex<(Substring, Substring, Substring)>, dateValuePattern: Regex<Substring>, issues: inout [Issue]) {
        for match in line.matches(of: dateTagPattern) {
            let tag = String(match.1)
            let value = String(match.2)
            if value.firstMatch(of: dateValuePattern) == nil && !value.isEmpty {
                issues.append(Issue(
                    path: path, line: lineNum, ruleID: "date_format",
                    message: "\(tag) date should be YYYY-MM-DD (e.g. @\(tag)(2026-03-15)).",
                    severity: .warning, fixable: false
                ))
            }
        }
    }

    /// Apply fixable issues by rewriting the file with IDs and formatting applied.
    /// Returns true if the file was modified.
    public func fix(path: String) throws -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard size <= MarkdownIO.maxTaskFileSizeBytes else { return false }
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let (frontmatter, body) = Frontmatter.parse(from: content)
        let (_, updatedBody) = markdownIO.parseTasksReturningUpdatedBody(from: content)
        var workingBody = updatedBody ?? body
        workingBody = moveCheckedTasksToCompleted(in: workingBody, path: path)
        var result = workingBody
        result = normaliseCheckboxCasing(in: result)
        result = ensureTitleHeading(in: result, path: path)
        result = normaliseHeadingAndListSpacing(in: result)
        if !result.hasSuffix("\n") {
            result += "\n"
        }
        let output = MarkdownIO.reassemble(frontmatter: frontmatter?.touchingModified(), body: result)
        try output.write(toFile: path, atomically: true, encoding: .utf8)
        return true
    }

    private func ensureTrailingNewline(path: String, frontmatter: Frontmatter?, body: String) throws -> Bool {
        guard !body.isEmpty, !body.hasSuffix("\n") else { return false }
        let result = body + "\n"
        let output = MarkdownIO.reassemble(frontmatter: frontmatter, body: result)
        try output.write(toFile: path, atomically: true, encoding: .utf8)
        return true
    }

    private func normaliseCheckboxCasing(in body: String) -> String {
        body.replacingOccurrences(of: "- [X] ", with: "- [x] ")
    }

    /// Ensure there is a level-1 heading matching the expected title for the file.
    /// Inserts or normalises `# Title` as the first non-empty line of the body.
    private func ensureTitleHeading(in body: String, path: String) -> String {
        guard let expectedTitle = Self.expectedTitle(forPath: path) else { return body }

        var lines = body.components(separatedBy: .newlines)

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }

            if trimmed.hasPrefix("# ") {
                let current = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if current != expectedTitle {
                    lines[idx] = "# \(expectedTitle)"
                }
                return lines.joined(separator: "\n")
            } else {
                var insertLines = ["# \(expectedTitle)"]
                // Keep a blank line between the title and existing content for readability.
                insertLines.append("")
                lines.insert(contentsOf: insertLines, at: idx)
                return lines.joined(separator: "\n")
            }
        }

        // Body is empty or only whitespace.
        return "# \(expectedTitle)"
    }

    /// Move checked tasks that are not already in the Completed section into Completed
    /// and ensure they have an @done(YYYY-MM-DD) tag using today's date when added.
    private func moveCheckedTasksToCompleted(in body: String, path: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        var newLines: [String] = []
        var completedBlocks: [String] = []

        enum Section {
            case other
            case completed
        }

        var currentSection: Section = .other

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_GB")
        let today = dateFormatter.string(from: Date())

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                let heading = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let lower = heading.lowercased()
                if lower.contains("completed") || lower.contains("done") {
                    currentSection = .completed
                } else {
                    currentSection = .other
                }
                newLines.append(line)
                i += 1
                continue
            }

            let isCheckedTask = trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")

            if isCheckedTask && currentSection != .completed {
                var modified = line.replacingOccurrences(of: "- [X]", with: "- [x]")
                if !modified.contains("@done(") {
                    let idPattern = /<!--\s*id:(\w+)\s*-->/
                    if let match = modified.firstMatch(of: idPattern) {
                        let idMarker = String(match.0)
                        if let range = modified.range(of: idMarker) {
                            let prefix = modified[..<range.lowerBound]
                            let suffix = modified[range.lowerBound...]
                            modified = "\(prefix)@done(\(today)) \(suffix)"
                        } else {
                            modified += " @done(\(today))"
                        }
                    } else {
                        modified += " @done(\(today))"
                    }
                }

                var blockLines: [String] = [modified]
                i += 1
                while i < lines.count {
                    let next = lines[i]
                    let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                    let isNote = nextTrimmed.hasPrefix(">") || nextTrimmed.hasPrefix("- [ ]") == false && next.hasPrefix("  >")
                    if isNote || nextTrimmed.isEmpty {
                        blockLines.append(next)
                        i += 1
                    } else {
                        break
                    }
                }

                completedBlocks.append(blockLines.joined(separator: "\n"))
                continue
            }

            newLines.append(line)
            i += 1
        }

        guard !completedBlocks.isEmpty else {
            return body
        }

        var outputLines = newLines
        var completedHeaderIndex: Int?
        for (idx, line) in outputLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                let heading = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let lower = heading.lowercased()
                if lower.contains("completed") || lower.contains("done") {
                    completedHeaderIndex = idx
                    break
                }
            }
        }

        if let headerIndex = completedHeaderIndex {
            var insertIndex = headerIndex + 1
            if insertIndex < outputLines.count &&
                outputLines[insertIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                insertIndex += 1
            }
            let blocksWithSpacing: [String] = completedBlocks.flatMap { [$0, ""] }
            outputLines.insert(contentsOf: blocksWithSpacing, at: insertIndex)
        } else {
            if !outputLines.isEmpty && !outputLines.last!.trimmingCharacters(in: .whitespaces).isEmpty {
                outputLines.append("")
            }
            outputLines.append("## Completed")
            outputLines.append("")
            for block in completedBlocks {
                outputLines.append(block)
                outputLines.append("")
            }
        }

        return outputLines.joined(separator: "\n")
    }

    /// Normalise spacing around headings and between list items:
    /// - exactly one empty line before and after headings (where there is surrounding content),
    /// - no empty lines between consecutive list items.
    private func normaliseHeadingAndListSpacing(in body: String) -> String {
        var result: [String] = []
        let lines = body.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#") {
                // Heading: ensure at most one blank line before.
                while let last = result.last,
                      last.trimmingCharacters(in: .whitespaces).isEmpty {
                    result.removeLast()
                }
                if !result.isEmpty {
                    result.append("")
                }

                // Add the heading itself.
                result.append(line)

                // Skip any blank lines following the heading in the source.
                i += 1
                while i < lines.count,
                      lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    i += 1
                }

                // If there is more content, ensure exactly one blank line after the heading.
                if i < lines.count {
                    result.append("")
                }
                continue
            }

            if trimmed.isEmpty {
                // Remove empty lines between consecutive list items.
                let prevIsList = i > 0 && isListLine(lines[i - 1])
                let nextIsList = i + 1 < lines.count && isListLine(lines[i + 1])
                if prevIsList && nextIsList {
                    i += 1
                    continue
                }
                result.append(line)
                i += 1
                continue
            }

            result.append(line)
            i += 1
        }

        return result.joined(separator: "\n")
    }

    private func isListLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("- [") { return true }
        if trimmed.hasPrefix("- ") { return true }
        if trimmed.hasPrefix("* ") { return true }
        return false
    }
}
