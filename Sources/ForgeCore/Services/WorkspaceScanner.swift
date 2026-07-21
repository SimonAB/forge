import Foundation

/// Scans the workspace directory and builds a list of projects with their Finder tag metadata.
public struct WorkspaceScanner: Sendable {

    private let tagStore: any TagReading
    private let config: ForgeConfig

    public init(config: ForgeConfig, tagStore: some TagReading = FinderTagStore()) {
        self.config = config
        self.tagStore = tagStore
    }

    /// Scan the workspace and return all project directories as Project values.
    /// Respects `project_scan_depth` on the config (default: direct children only).
    /// When `project_tag` is set, only directories with that tag qualify; untagged folders
    /// at intermediate levels are treated as grouping containers and their children are scanned.
    /// Skips hidden directories (starting with '.') and build artefacts.
    public func scanProjects() throws -> [Project] {
        let fm = FileManager.default
        var projects: [Project] = []

        for workspacePath in config.resolvedProjectRoots {
            try collectProjects(
                at: workspacePath,
                remainingDepth: config.resolvedProjectScanDepth,
                fileManager: fm,
                tagReader: { path in tagStore.tags(at: path) },
                into: &projects
            )
        }

        return projects
    }

    /// Async version: scan the workspace without blocking the calling thread on tag I/O.
    public func scanProjects() async throws -> [Project] {
        let fm = FileManager.default
        var projects: [Project] = []

        for workspacePath in config.resolvedProjectRoots {
            try await collectProjects(
                at: workspacePath,
                remainingDepth: config.resolvedProjectScanDepth,
                fileManager: fm,
                tagReader: { path in await tagStore.tags(at: path) },
                into: &projects
            )
        }

        return projects
    }

    private func collectProjects(
        at directoryPath: String,
        remainingDepth: Int,
        fileManager: FileManager,
        tagReader: (String) -> [String],
        into projects: inout [Project]
    ) throws {
        guard remainingDepth > 0 else { return }
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directoryPath) else { return }

        for item in contents.sorted() {
            guard !item.hasPrefix(".") else { continue }

            let fullPath = (directoryPath as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let tags = tagReader(fullPath)
            if qualifiesAsProject(tags: tags) {
                let project = classify(name: item, path: fullPath, tags: tags)
                projects.append(project)
            } else if remainingDepth > 1 {
                try collectProjects(
                    at: fullPath,
                    remainingDepth: remainingDepth - 1,
                    fileManager: fileManager,
                    tagReader: tagReader,
                    into: &projects
                )
            }
        }
    }

    private func collectProjects(
        at directoryPath: String,
        remainingDepth: Int,
        fileManager: FileManager,
        tagReader: (String) async -> [String],
        into projects: inout [Project]
    ) async throws {
        guard remainingDepth > 0 else { return }
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directoryPath) else { return }

        for item in contents.sorted() {
            guard !item.hasPrefix(".") else { continue }

            let fullPath = (directoryPath as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let tags = await tagReader(fullPath)
            if qualifiesAsProject(tags: tags) {
                let project = classify(name: item, path: fullPath, tags: tags)
                projects.append(project)
            } else if remainingDepth > 1 {
                try await collectProjects(
                    at: fullPath,
                    remainingDepth: remainingDepth - 1,
                    fileManager: fileManager,
                    tagReader: tagReader,
                    into: &projects
                )
            }
        }
    }

    private func qualifiesAsProject(tags: [String]) -> Bool {
        guard let requiredTag = config.projectTag else { return true }
        return tags.contains(requiredTag)
    }

    /// Classify a directory's tags into workflow column and meta tags.
    private func classify(name: String, path: String, tags: [String]) -> Project {
        var workflowTag: String?
        var columnName: String?
        var metaTags: [String] = []
        var assignees: [String] = []

        let metaTagSet = Set(config.board.metaTags)

        for tag in tags {
            if let person = AssigneeTag.normalisedIdentifier(fromRawTag: tag) {
                assignees.append(person)
                continue
            }

            if metaTagSet.contains(tag) {
                metaTags.append(tag)
                continue
            }

            if workflowTag == nil, let col = config.column(forTag: tag) {
                workflowTag = col.tag
                columnName = col.name
            }
        }

        return Project(
            name: name,
            path: path,
            tags: tags,
            workflowTag: workflowTag,
            column: columnName,
            metaTags: metaTags,
            assignees: assignees
        )
    }
}
