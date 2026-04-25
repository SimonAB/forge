import Foundation

/// A brief produced by an LLM/provider, optionally including actionable proposals.
public struct BriefResult: Codable, Sendable {
    public let briefMarkdown: String
    public let proposals: [BriefProposal]

    public init(briefMarkdown: String, proposals: [BriefProposal]) {
        self.briefMarkdown = briefMarkdown
        self.proposals = proposals
    }
}

/// A single proposed action to apply to the board (approval-gated by the UI).
public struct BriefProposal: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case move = "move"
        case tagAdd = "tag_add"
        case tagRemove = "tag_remove"
    }

    public let kind: Kind
    public let projectPath: String
    public let columnName: String?
    public let tag: String?
    public let why: String

    public init(kind: Kind, projectPath: String, columnName: String?, tag: String?, why: String) {
        self.kind = kind
        self.projectPath = projectPath
        self.columnName = columnName
        self.tag = tag
        self.why = why
    }
}
