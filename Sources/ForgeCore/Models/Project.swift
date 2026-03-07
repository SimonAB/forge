import Foundation

/// A project represented by a directory in the workspace, with Finder tags as metadata.
public struct Project: Sendable {
    /// Directory name (not the full path).
    public let name: String

    /// Full filesystem path to the project directory.
    public let path: String

    /// All Finder tags currently on the directory.
    public let tags: [String]

    /// The workflow tag (kanban column), if any. Resolved from aliases.
    public let workflowTag: String?

    /// The kanban column name this project belongs to, or nil if untagged.
    public let column: String?

    /// Meta tags (e.g. Mine, Collab, Student) present on the directory.
    public let metaTags: [String]

    public init(
        name: String,
        path: String,
        tags: [String],
        workflowTag: String?,
        column: String?,
        metaTags: [String]
    ) {
        self.name = name
        self.path = path
        self.tags = tags
        self.workflowTag = workflowTag
        self.column = column
        self.metaTags = metaTags
    }
}

extension Project: CustomStringConvertible {
    public var description: String {
        let col = column ?? "Untagged"
        let meta = metaTags.isEmpty ? "" : " [\(metaTags.joined(separator: ", "))]"
        return "\(name) (\(col))\(meta)"
    }
}
