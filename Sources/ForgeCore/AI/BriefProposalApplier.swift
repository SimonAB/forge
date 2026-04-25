import Foundation

/// Validates and applies `BriefProposal` actions using the same tagging rules as the CLI.
public struct BriefProposalApplier: Sendable {
    public struct AppliedChange: Sendable, Equatable {
        public let description: String
        public init(description: String) { self.description = description }
    }

    private let config: ForgeConfig
    private let tagStore: FinderTagStore

    public init(config: ForgeConfig, tagStore: FinderTagStore = FinderTagStore()) {
        self.config = config
        self.tagStore = tagStore
    }

    /// Validate proposals and apply them to the filesystem (Finder tags), returning a log of changes.
    ///
    /// The caller must obtain explicit user approval before invoking this.
    public func apply(_ proposals: [BriefProposal]) throws -> [AppliedChange] {
        var changes: [AppliedChange] = []
        for proposal in proposals {
            try validate(proposal)
            switch proposal.kind {
            case .move:
                let target = try resolveColumn(name: proposal.columnName)
                let from = try currentColumnName(at: proposal.projectPath) ?? "Untagged"
                try moveProject(at: proposal.projectPath, to: target)
                changes.append(AppliedChange(description: "\(lastPathComponent(proposal.projectPath)): \(from) → \(target.name)"))
            case .tagAdd:
                let tag = try requireTag(proposal.tag)
                try tagStore.addTag(tag, at: proposal.projectPath)
                changes.append(AppliedChange(description: "Added \(tag) on \(lastPathComponent(proposal.projectPath))"))
            case .tagRemove:
                let tag = try requireTag(proposal.tag)
                try tagStore.removeTag(tag, at: proposal.projectPath)
                changes.append(AppliedChange(description: "Removed \(tag) from \(lastPathComponent(proposal.projectPath))"))
            }
        }
        return changes
    }

    public func validate(_ proposal: BriefProposal) throws {
        let path = proposal.projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw ForgeAIError.invalidResponse("Proposal projectPath must not be empty.")
        }
        guard isUnderProjectRoots(path) else {
            throw ForgeAIError.invalidResponse("Refusing to touch path outside configured project roots: \(path)")
        }

        switch proposal.kind {
        case .move:
            _ = try resolveColumn(name: proposal.columnName)
        case .tagAdd, .tagRemove:
            let tag = try requireTag(proposal.tag)
            if config.column(forTag: tag) != nil {
                throw ForgeAIError.invalidResponse("Refusing to add/remove workflow column tags via proposals. Use a move proposal instead.")
            }
            switch ProjectFolderTagPolicy.validationResult(tag: tag, config: config) {
            case .workflowColumn:
                throw ForgeAIError.invalidResponse("That tag is a workflow column tag.")
            case .unrecognized:
                throw ForgeAIError.invalidResponse("Tag is not a configured meta tag or #Person assignee tag: \(tag)")
            case .allowed:
                break
            }
        }
    }

    // MARK: - Helpers

    private func resolveColumn(name: String?) throws -> ColumnConfig {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ForgeAIError.invalidResponse("Move proposal is missing columnName.")
        }
        let lower = trimmed.lowercased()
        if let exact = config.board.columns.first(where: { $0.name.lowercased() == lower }) {
            return exact
        }
        if let prefix = config.board.columns.first(where: { $0.name.lowercased().hasPrefix(lower) }) {
            return prefix
        }
        let valid = config.board.columns.map(\.name).joined(separator: ", ")
        throw ForgeAIError.invalidResponse("Unknown column '\(trimmed)'. Valid columns: \(valid)")
    }

    private func requireTag(_ tag: String?) throws -> String {
        let trimmed = (tag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ForgeAIError.invalidResponse("Tag proposal is missing tag.")
        }
        return trimmed
    }

    private func isUnderProjectRoots(_ path: String) -> Bool {
        let expandedPath = (path as NSString).expandingTildeInPath
        for root in config.resolvedProjectRoots {
            let canonicalRoot = (root as NSString).standardizingPath
            let canonicalPath = (expandedPath as NSString).standardizingPath
            if canonicalPath == canonicalRoot { return true }
            if canonicalPath.hasPrefix(canonicalRoot + "/") { return true }
        }
        return false
    }

    private func currentColumnName(at path: String) throws -> String? {
        let tags = try tagStore.readTags(at: path)
        for tag in tags {
            if let col = config.column(forTag: tag) {
                return col.name
            }
        }
        return nil
    }

    private func moveProject(at path: String, to column: ColumnConfig) throws {
        let tags = try tagStore.readTags(at: path)
        if let existingWorkflow = tags.first(where: { config.column(forTag: $0) != nil }) {
            try tagStore.removeTag(existingWorkflow, at: path)
        }
        try tagStore.addTag(column.tag, at: path)
    }

    private func lastPathComponent(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
