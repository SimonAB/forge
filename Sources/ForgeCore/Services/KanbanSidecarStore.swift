import Foundation

/// Portable kanban state stored at `<project>/.forge/kanban.toml`.
public struct KanbanSidecar: Sendable, Equatable {
    public var schema: Int
    public var column: String?
    public var workflowTag: String?
    public var meta: [String]
    public var assignees: [String]
    public var updatedAt: Date
    public var source: String

    public init(
        schema: Int = 1,
        column: String? = nil,
        workflowTag: String? = nil,
        meta: [String] = [],
        assignees: [String] = [],
        updatedAt: Date = Date(),
        source: String = "forge-move"
    ) {
        self.schema = schema
        self.column = column
        self.workflowTag = workflowTag
        self.meta = meta
        self.assignees = assignees
        self.updatedAt = updatedAt
        self.source = source
    }
}

/// Read/write `<project>/.forge/kanban.toml` (minimal TOML, no extra dependency).
public enum KanbanSidecarStore {
    public static let relativePath = ".forge/kanban.toml"

    /// Absolute path to the sidecar for a project directory.
    public static func path(forProjectDirectory projectPath: String) -> String {
        (projectPath as NSString).appendingPathComponent(relativePath)
    }

    /// Load sidecar if present; returns nil when missing.
    public static func load(projectPath: String) throws -> KanbanSidecar? {
        let url = URL(fileURLWithPath: path(forProjectDirectory: projectPath))
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try decode(text)
    }

    /// Write sidecar (creates `.forge/` as needed).
    public static func save(_ sidecar: KanbanSidecar, projectPath: String) throws {
        let filePath = path(forProjectDirectory: projectPath)
        let dir = (filePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try encode(sidecar).write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    /// Build a sidecar snapshot from classified tag lists.
    public static func make(
        column: String?,
        workflowTag: String?,
        meta: [String],
        assignees: [String],
        source: String,
        updatedAt: Date = Date()
    ) -> KanbanSidecar {
        KanbanSidecar(
            column: column,
            workflowTag: workflowTag,
            meta: meta,
            assignees: assignees.map { $0.hasPrefix("#") ? $0 : "#\($0)" },
            updatedAt: updatedAt,
            source: source
        )
    }

    // MARK: - TOML

    public static func encode(_ sidecar: KanbanSidecar) -> String {
        var lines: [String] = [
            "schema = \(sidecar.schema)",
        ]
        if let column = sidecar.column {
            lines.append("column = \(tomlString(column))")
        }
        if let workflowTag = sidecar.workflowTag {
            lines.append("workflow_tag = \(tomlString(workflowTag))")
        }
        lines.append("meta = \(tomlArray(sidecar.meta))")
        lines.append("assignees = \(tomlArray(sidecar.assignees))")
        lines.append("updated_at = \(tomlString(iso8601(sidecar.updatedAt)))")
        lines.append("source = \(tomlString(sidecar.source))")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    public static func decode(_ text: String) throws -> KanbanSidecar {
        var schema = 1
        var column: String?
        var workflowTag: String?
        var meta: [String] = []
        var assignees: [String] = []
        var updatedAt = Date()
        var source = "migrate"

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "schema":
                schema = Int(value) ?? 1
            case "column":
                column = unquote(value)
            case "workflow_tag":
                workflowTag = unquote(value)
            case "meta":
                meta = parseArray(value)
            case "assignees":
                assignees = parseArray(value)
            case "updated_at":
                if let date = parseISO8601(unquote(value) ?? value) {
                    updatedAt = date
                }
            case "source":
                source = unquote(value) ?? value
            default:
                break
            }
        }
        return KanbanSidecar(
            schema: schema,
            column: column,
            workflowTag: workflowTag,
            meta: meta,
            assignees: assignees,
            updatedAt: updatedAt,
            source: source
        )
    }

    private static func tomlString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func tomlArray(_ values: [String]) -> String {
        "[" + values.map(tomlString).joined(separator: ", ") + "]"
    }

    private static func unquote(_ value: String) -> String? {
        var v = value.trimmingCharacters(in: .whitespaces)
        guard v.count >= 2, v.first == "\"", v.last == "\"" else {
            return v.isEmpty ? nil : v
        }
        v.removeFirst()
        v.removeLast()
        return v
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func parseArray(_ value: String) -> [String] {
        var v = value.trimmingCharacters(in: .whitespaces)
        guard v.hasPrefix("["), v.hasSuffix("]") else { return [] }
        v.removeFirst()
        v.removeLast()
        if v.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        var items: [String] = []
        var current = ""
        var inQuote = false
        var escape = false
        for ch in v {
            if escape {
                current.append(ch)
                escape = false
                continue
            }
            if ch == "\\" {
                escape = true
                continue
            }
            if ch == "\"" {
                inQuote.toggle()
                continue
            }
            if ch == ",", !inQuote {
                let item = current.trimmingCharacters(in: .whitespaces)
                if !item.isEmpty { items.append(item) }
                current = ""
                continue
            }
            current.append(ch)
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { items.append(last) }
        return items
    }

    private static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }
}
