import Foundation

/// YAML frontmatter parsed from the top of a markdown area file.
///
/// Expected format:
/// ```
/// ---
/// id: admin
/// tags: [work]
/// date_created: 2026-03-07
/// date_modified: 2026-03-07
/// ---
/// ```
public struct Frontmatter: Sendable, Equatable {
    public var id: String
    public var tags: [String]
    public var dateCreated: Date
    public var dateModified: Date

    public init(id: String, tags: [String], dateCreated: Date, dateModified: Date) {
        self.id = id
        self.tags = tags
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }

    /// Create default frontmatter for a new area file.
    public static func defaultFrontmatter(id: String, tags: [String] = []) -> Frontmatter {
        let now = Date()
        return Frontmatter(id: id, tags: tags, dateCreated: now, dateModified: now)
    }

    // MARK: - Parsing

    /// Parse frontmatter from the beginning of a markdown string.
    ///
    /// Returns the parsed frontmatter (or nil if absent/malformed) and the
    /// remaining body content after the closing `---`.
    public static func parse(from content: String) -> (frontmatter: Frontmatter?, body: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else {
            return (nil, content)
        }

        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return (nil, content)
        }

        var closingIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = i
                break
            }
        }

        guard let endIdx = closingIndex else {
            return (nil, content)
        }

        let yamlLines = lines[1..<endIdx]
        let body = lines[(endIdx + 1)...].joined(separator: "\n")

        var id: String?
        var tags: [String] = []
        var dateCreated: Date?
        var dateModified: Date?

        for line in yamlLines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if let value = extractValue("id", from: stripped) {
                id = value
            } else if stripped.hasPrefix("tags:") {
                tags = parseTags(stripped)
            } else if let value = extractValue("date_created", from: stripped) {
                dateCreated = dateFormatter.date(from: value)
            } else if let value = extractValue("date_modified", from: stripped) {
                dateModified = dateFormatter.date(from: value)
            }
        }

        guard let parsedID = id else {
            return (nil, content)
        }

        let now = Date()
        let fm = Frontmatter(
            id: parsedID,
            tags: tags,
            dateCreated: dateCreated ?? now,
            dateModified: dateModified ?? now
        )
        return (fm, body)
    }

    // MARK: - Serialisation

    /// Serialise frontmatter to a YAML block including the `---` delimiters.
    public func serialise() -> String {
        let created = Self.dateFormatter.string(from: dateCreated)
        let modified = Self.dateFormatter.string(from: dateModified)
        let tagList = tags.isEmpty ? "[]" : "[\(tags.joined(separator: ", "))]"

        return """
        ---
        id: \(id)
        tags: \(tagList)
        date_created: \(created)
        date_modified: \(modified)
        ---
        """
    }

    /// Return a copy with `dateModified` set to now.
    public func touchingModified() -> Frontmatter {
        var copy = self
        copy.dateModified = Date()
        return copy
    }

    /// True if the file has not been modified in the given number of days.
    public func isStale(days: Int = 14) -> Bool {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return dateModified < cutoff
    }

    /// Days since the file was last modified.
    public var daysSinceModified: Int {
        let components = Calendar.current.dateComponents([.day], from: dateModified, to: Date())
        return components.day ?? 0
    }

    // MARK: - Private Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    private static func extractValue(_ key: String, from line: String) -> String? {
        guard line.hasPrefix("\(key):") else { return nil }
        let value = String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func parseTags(_ line: String) -> [String] {
        guard let bracketStart = line.firstIndex(of: "["),
              let bracketEnd = line.lastIndex(of: "]") else {
            return []
        }
        let inner = line[line.index(after: bracketStart)..<bracketEnd]
        return inner
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
