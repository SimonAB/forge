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
        let bareMessagePattern = /message:%3C[^ \t)]+%3E/

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

                // Message URL formatting: detect bare "message:%3C...%3E" tokens that are not already inside a markdown link.
                if line.firstMatch(of: bareMessagePattern) != nil,
                   !line.contains("](message://") {
                    issues.append(Issue(
                        path: path,
                        line: lineNum,
                        ruleID: "message_url_format",
                        message: "Format bare Mail message URLs as markdown links, e.g. [email](message://…).",
                        severity: .warning,
                        fixable: true
                    ))
                }
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

        // Trailing whitespace on any line.
        for (idx, line) in lines.enumerated() {
            if let lastChar = line.last, lastChar == " " || lastChar == "\t" {
                issues.append(Issue(
                    path: path,
                    line: idx + 1,
                    ruleID: "trailing_whitespace",
                    message: "Remove trailing spaces from this line.",
                    severity: .warning,
                    fixable: true
                ))
            }
        }

        // Ensure documents end with exactly one empty line (single trailing blank line).
        if !lines.isEmpty {
            var trailingBlankCount = 0
            for line in lines.reversed() {
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    trailingBlankCount += 1
                } else {
                    break
                }
            }
            if trailingBlankCount > 1 {
                issues.append(Issue(
                    path: path,
                    line: lines.count,
                    ruleID: "trailing_blank_lines",
                    message: "Document should end with exactly one empty line; remove extra blank lines at the end.",
                    severity: .warning,
                    fixable: true
                ))
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
        workingBody = fixBareMessageURLs(in: workingBody)
        var result = workingBody
        result = normaliseCheckboxCasing(in: result)
        result = ensureTitleHeading(in: result, path: path)
        result = reorderCanonicalSections(in: result)
        result = sortCompletedSectionByDoneDate(in: result)
        result = normaliseHeadingAndListSpacing(in: result)
        result = normaliseTrailingWhitespaceAndEOF(in: result)
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

                // Normalise canonical section headings (e.g. "Next Action" -> "Next Actions").
                let normalisedHeading: String
                if trimmed.hasPrefix("## ") {
                    let title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    if let canonical = Self.canonicalSection(for: title) {
                        normalisedHeading = "## \(canonical.title)"
                    } else {
                        normalisedHeading = line
                    }
                } else {
                    normalisedHeading = line
                }

                // Add the heading itself.
                result.append(normalisedHeading)

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
                // Remove all empty lines that sit between two list items.
                var prevNonEmptyIndex: Int?
                var j = i - 1
                while j >= 0 {
                    if !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                        prevNonEmptyIndex = j
                        break
                    }
                    j -= 1
                }

                var nextNonEmptyIndex: Int?
                j = i + 1
                while j < lines.count {
                    if !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                        nextNonEmptyIndex = j
                        break
                    }
                    j += 1
                }

                if let prev = prevNonEmptyIndex,
                   let next = nextNonEmptyIndex,
                   isListLine(lines[prev]),
                   isListLine(lines[next]) {
                    // Skip this empty line entirely.
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

    /// Remove trailing spaces from all lines and ensure the document ends with
    /// exactly one empty line (a single trailing blank line terminated by a newline).
    private func normaliseTrailingWhitespaceAndEOF(in body: String) -> String {
        var lines = body.components(separatedBy: .newlines)

        // Strip trailing spaces and tabs from each line.
        for i in 0..<lines.count {
            var line = lines[i]
            while let last = line.last, last == " " || last == "\t" {
                line.removeLast()
            }
            lines[i] = line
        }

        // Remove extra trailing blank lines, but keep at least one line.
        while lines.count > 1,
              let last = lines.last,
              last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }

        // Ensure the last line is empty so the document ends with exactly one blank line.
        if lines.isEmpty {
            lines = [""]
        } else if !lines.last!.isEmpty {
            lines.append("")
        }

        var result = lines.joined(separator: "\n")
        if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    /// Reorder canonical sections into the standard order:
    /// # Title
    /// ## Next Actions
    /// ## Waiting For
    /// ## Completed
    /// ## Notes
    /// while keeping each section's content attached to its heading.
    private func reorderCanonicalSections(in body: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return body }

        // Identify section blocks: heading line index + lines until next heading or EOF.
        struct SectionBlock {
            let canonicalIndex: Int?  // 0: Next Actions, 1: Waiting For, 2: Completed, 3: Notes, nil: other
            let start: Int
            let end: Int   // inclusive
        }

        var blocks: [SectionBlock] = []
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                let title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let canonical = Self.canonicalSection(for: title)?.index
                var end = i
                var j = i + 1
                while j < lines.count {
                    let t = lines[j].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("## ") { break }
                    end = j
                    j += 1
                }
                blocks.append(SectionBlock(canonicalIndex: canonical, start: i, end: end))
                i = end + 1
            } else {
                i += 1
            }
        }

        guard !blocks.isEmpty else { return body }

        // Collect pre-section content (everything before first section heading).
        let firstBlockStart = blocks[0].start
        let preSectionLines: [String] = Array(lines[0..<firstBlockStart])

        // Group blocks by canonical index, preserving original order within each group.
        var byCanonical: [Int: [SectionBlock]] = [:]
        var others: [SectionBlock] = []
        for block in blocks {
            if let idx = block.canonicalIndex {
                byCanonical[idx, default: []].append(block)
            } else {
                others.append(block)
            }
        }

        // Build new body: pre-section content + canonical sections in order + other sections.
        var newLines: [String] = preSectionLines

        func appendBlock(_ block: SectionBlock) {
            if !newLines.isEmpty,
               !newLines.last!.trimmingCharacters(in: .whitespaces).isEmpty {
                newLines.append("")
            }
            for idx in block.start...block.end {
                newLines.append(lines[idx])
            }
        }

        // Canonical order: Next Actions (0), Waiting For (1), Completed (2), Notes (3)
        for canonicalIndex in 0...3 {
            if let group = byCanonical[canonicalIndex] {
                for block in group {
                    appendBlock(block)
                }
            }
        }

        // Append all non-canonical sections in their original order.
        for block in others {
            appendBlock(block)
        }

        // Append any trailing content after the last section block (if any).
        if let lastBlock = blocks.last, lastBlock.end + 1 < lines.count {
            if !newLines.isEmpty,
               !newLines.last!.trimmingCharacters(in: .whitespaces).isEmpty {
                newLines.append("")
            }
            for idx in (lastBlock.end + 1)..<lines.count {
                newLines.append(lines[idx])
            }
        }

        return newLines.joined(separator: "\n")
    }

    /// Inside the Completed section, sort task blocks by @done(YYYY-MM-DD) date, most recent first.
    /// Notes under each task are kept with their task.
    private func sortCompletedSectionByDoneDate(in body: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return body }

        // Find the first Completed section heading.
        var completedHeadingIndex: Int?
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("## ") else { continue }
            let title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if let canonical = Self.canonicalSection(for: title), canonical.index == 2 {
                completedHeadingIndex = idx
                break
            }
        }
        guard let headerIndex = completedHeadingIndex else { return body }

        // Determine the range of the Completed section (from the heading to just before the next heading or EOF).
        var sectionEnd = lines.count - 1
        var i = headerIndex + 1
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## ") {
                sectionEnd = i - 1
                break
            }
            i += 1
        }
        if sectionEnd < headerIndex + 1 {
            return body
        }

        let completedBodyLines = Array(lines[(headerIndex + 1)...sectionEnd])
        if completedBodyLines.isEmpty {
            return body
        }

        struct TaskBlock {
            let lines: [String]
            let doneDate: Date?
            let order: Int
        }

        var blocks: [TaskBlock] = []
        var prefixLines: [String] = []

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_GB")

        var idx = 0
        var blockOrder = 0
        while idx < completedBodyLines.count {
            let line = completedBodyLines[idx]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [") {
                var block: [String] = [line]
                var j = idx + 1
                while j < completedBodyLines.count {
                    let next = completedBodyLines[j]
                    let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.hasPrefix("- [") || nextTrimmed.hasPrefix("## ") {
                        break
                    }
                    block.append(next)
                    j += 1
                }

                // Extract @done date from the task line (first line of the block).
                let donePattern = /@done\(([^)]+)\)/
                var doneDate: Date? = nil
                if let match = line.firstMatch(of: donePattern) {
                    let value = String(match.1)
                    doneDate = df.date(from: value)
                }

                blocks.append(TaskBlock(lines: block, doneDate: doneDate, order: blockOrder))
                blockOrder += 1
                idx = j
            } else {
                if blocks.isEmpty {
                    prefixLines.append(line)
                } else {
                    // Lines after the first block that are not part of a task are left as-is for now.
                    prefixLines.append(line)
                }
                idx += 1
            }
        }

        guard !blocks.isEmpty else { return body }

        // Sort blocks by done date (most recent first); tasks without dates go last, preserving relative order.
        blocks.sort { lhs, rhs in
            switch (lhs.doneDate, rhs.doneDate) {
            case let (l?, r?):
                if l != r { return l > r } // descending
                return lhs.order < rhs.order
            case (nil, nil):
                return lhs.order < rhs.order
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }

        var newLines: [String] = []
        // Content before the Completed heading.
        if headerIndex > 0 {
            newLines.append(contentsOf: lines[0..<headerIndex])
        }
        // The Completed heading itself.
        newLines.append(lines[headerIndex])

        // Rebuild the Completed section body.
        var completedNew: [String] = prefixLines
        for (index, block) in blocks.enumerated() {
            if !completedNew.isEmpty,
               !completedNew.last!.trimmingCharacters(in: .whitespaces).isEmpty {
                completedNew.append("")
            }
            completedNew.append(contentsOf: block.lines)
            if index != blocks.count - 1 {
                completedNew.append("")
            }
        }

        newLines.append(contentsOf: completedNew)

        // Append any content after the Completed section.
        if sectionEnd + 1 < lines.count {
            if !newLines.isEmpty,
               !newLines.last!.trimmingCharacters(in: .whitespaces).isEmpty {
                newLines.append("")
            }
            newLines.append(contentsOf: lines[(sectionEnd + 1)...])
        }

        return newLines.joined(separator: "\n")
    }

    /// Convert bare Mail message URLs of the form `message:%3C...%3E` into markdown links:
    /// - [email](message://%3C...%3E)
    /// Skips lines where the URL is already inside a markdown link.
    private func fixBareMessageURLs(in body: String) -> String {
        let pattern = /message:%3C[^ \t)]+%3E/
        var changed = false
        let lines = body.components(separatedBy: .newlines)
        var newLines: [String] = []

        for line in lines {
            if line.contains("](message://") {
                newLines.append(line)
                continue
            }
            if let match = line.firstMatch(of: pattern) {
                let token = String(match.0)
                let suffix = token.dropFirst("message:".count)
                let converted = "message://\(suffix)"
                let replacement = "[email](\(converted))"
                let updated = line.replacingOccurrences(of: token, with: replacement)
                newLines.append(updated)
                if updated != line { changed = true }
            } else {
                newLines.append(line)
            }
        }

        return changed ? newLines.joined(separator: "\n") : body
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
