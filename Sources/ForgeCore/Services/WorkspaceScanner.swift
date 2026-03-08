import Foundation

/// Scans the workspace directory and builds a list of projects with their Finder tag metadata.
public struct WorkspaceScanner: Sendable {

    private let tagStore: FinderTagStore
    private let config: ForgeConfig

    public init(config: ForgeConfig, tagStore: FinderTagStore = FinderTagStore()) {
        self.config = config
        self.tagStore = tagStore
    }

    /// Scan the workspace and return all project directories as Project values.
    /// Scans direct children of each project root only. When project_tag is set, only those children with that tag are included.
    /// Skips hidden directories (starting with '.') and build artefacts.
    public func scanProjects() throws -> [Project] {
        let fm = FileManager.default
        var projects: [Project] = []

        for workspacePath in config.resolvedProjectRoots {
            guard let contents = try? fm.contentsOfDirectory(atPath: workspacePath) else { continue }

            for item in contents.sorted() {
                guard !item.hasPrefix(".") else { continue }

                let fullPath = (workspacePath as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                let tags = tagStore.readTagsIfAvailable(at: fullPath) ?? []
                if let requiredTag = config.projectTag, !tags.contains(requiredTag) {
                    continue
                }
                let project = classify(name: item, path: fullPath, tags: tags)
                projects.append(project)
            }
        }

        return projects
    }

    /// Classify a directory's tags into workflow column and meta tags.
    private func classify(name: String, path: String, tags: [String]) -> Project {
        var workflowTag: String?
        var columnName: String?
        var metaTags: [String] = []

        let metaTagSet = Set(config.board.metaTags)

        for tag in tags {
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
            metaTags: metaTags
        )
    }
}
