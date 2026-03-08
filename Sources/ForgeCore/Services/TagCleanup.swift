import Foundation

/// Performs tag cleanup operations: resolving aliases, setting correct Finder colours,
/// and detecting likely miscategorised directories.
public struct TagCleanup: Sendable {

    private let tagStore: FinderTagStore
    private let config: ForgeConfig

    private static let availabilityTimeout = FinderTagStore.defaultAvailabilityTimeout

    public init(config: ForgeConfig, tagStore: FinderTagStore = FinderTagStore()) {
        self.config = config
        self.tagStore = tagStore
    }

    /// A single cleanup action that was performed or is recommended.
    public struct CleanupAction: Sendable {
        public enum Kind: Sendable {
            case aliasResolved(old: String, new: String)
            case duplicateRemoved(tag: String)
            case flagged(reason: String)
        }

        public let projectName: String
        public let projectPath: String
        public let kind: Kind

        public var description: String {
            switch kind {
            case .aliasResolved(let old, let new):
                return "\(projectName): '\(old)' → '\(new)'"
            case .duplicateRemoved(let tag):
                return "\(projectName): removed duplicate '\(tag)'"
            case .flagged(let reason):
                return "\(projectName): ⚠ \(reason)"
            }
        }
    }

    /// Scan all projects and apply tag aliases, returning a log of all changes made.
    /// When project_tag is set, pass the list of project paths from WorkspaceScanner so nested projects are included.
    public func cleanupAliases(at workspacePath: String) throws -> [CleanupAction] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(atPath: workspacePath)
        var actions: [CleanupAction] = []

        for item in contents.sorted() {
            guard !item.hasPrefix(".") else { continue }
            let fullPath = (workspacePath as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            if let requiredTag = config.projectTag {
                let tags = tagStore.readTagsIfAvailable(at: fullPath) ?? []
                guard tags.contains(requiredTag) else { continue }
            }

            actions.append(contentsOf: try cleanupAliasesAtSinglePath(fullPath, name: item, timeout: Self.availabilityTimeout))
        }

        return actions
    }

    /// Apply tag aliases and duplicate check to a single directory (used when cleaning recursively discovered projects).
    /// When `timeout` is set, skips the path if tags cannot be read within that time (e.g. undownloaded cloud path).
    public func cleanupAliasesAtSinglePath(_ fullPath: String, name: String? = nil, timeout: TimeInterval? = nil) throws -> [CleanupAction] {
        var actions: [CleanupAction] = []
        let projectName = name ?? (fullPath as NSString).lastPathComponent

        let replacements = try tagStore.applyAliases(config.board.tagAliases, at: fullPath, timeout: timeout)
        for (old, new) in replacements {
            actions.append(CleanupAction(
                projectName: projectName, projectPath: fullPath,
                kind: .aliasResolved(old: old, new: new)
            ))
        }

        let tags: [String]
        if let t = timeout {
            guard let available = tagStore.readTagsIfAvailable(at: fullPath, timeout: t) else { return actions }
            tags = available
        } else {
            tags = try tagStore.readTags(at: fullPath)
        }
        let workflowTags = tags.filter { tag in
            config.board.columns.contains { $0.tag == tag }
        }
        if workflowTags.count > 1 {
            actions.append(CleanupAction(
                projectName: projectName, projectPath: fullPath,
                kind: .flagged(reason: "multiple workflow tags: \(workflowTags.joined(separator: ", "))")
            ))
        }
        return actions
    }
}
