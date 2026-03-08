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

        let (_, body) = Frontmatter.parse(from: content)
        let cleaned = MarkdownIO.stripRollup(body)
        let lines = cleaned.components(separatedBy: .newlines)
        var issues: [Issue] = []
        var sectionOrder: [(lineIndex: Int, title: String, canonicalIndex: Int)] = []
        var taskIDs: [String: Int] = [:]
        var i = 0

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
        guard var result = updatedBody else {
            return try ensureTrailingNewline(path: path, frontmatter: frontmatter, body: body)
        }
        result = normaliseCheckboxCasing(in: result)
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
}
