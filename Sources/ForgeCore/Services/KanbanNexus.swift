import Foundation

/// Central write path for project kanban: sidecar + local tags (+ archive side effects).
public enum KanbanNexus {

    public enum Source {
        public static let forgeMove = "forge-move"
        public static let projectTag = "project-tag"
        public static let fsImport = "fs-import"
        public static let ofRefresh = "of-refresh"
        public static let migrate = "migrate"
        public static let fsSync = "fs-sync"
    }

    /// Set the workflow column on local tags and, when enabled, the portable sidecar.
    public static func setWorkflowColumn(
        path: String,
        column: String,
        config: ForgeConfig,
        tagStore: any TagWriting = PlatformTagStore.makeDefault(),
        forgeDir: String? = nil,
        folderName: String? = nil,
        previousColumn: String? = nil,
        source: String = Source.forgeMove,
        writeSidecar: Bool? = nil
    ) throws {
        guard let colConfig = config.board.columns.first(where: { $0.name == column }) else {
            throw OmniJSBridgeError.evaluationFailed("Unknown board column \(column)")
        }

        let shouldSidecar = writeSidecar ?? config.nexus.sidecarEnabled
        var inferredPrevious = previousColumn
        var existingTags = (try? readAllTags(tagStore, at: path)) ?? []

        if inferredPrevious == nil {
            for tag in existingTags {
                if let col = config.column(forTag: tag) {
                    inferredPrevious = col.name
                    break
                }
            }
        }

        // Strip other workflow tags; keep meta / assignees / project_tag / unknowns.
        existingTags.removeAll { config.column(forTag: $0) != nil }
        if !existingTags.contains(colConfig.tag) {
            existingTags.append(colConfig.tag)
        }
        try tagStore.writeTags(existingTags, at: path)

        if let forgeDir, let folderName {
            try KanbanArchivePolicy.noteColumnTransition(
                folderName: folderName,
                path: path,
                previousColumn: inferredPrevious,
                newColumn: column,
                config: config,
                forgeDir: forgeDir,
                tagStore: tagStore
            )
            // Re-read after archive policy (may strip Completed).
            existingTags = (try? readAllTags(tagStore, at: path)) ?? existingTags
        }

        if shouldSidecar {
            let classified = classifyTags(existingTags, config: config)
            let sidecar = KanbanSidecarStore.make(
                column: column,
                workflowTag: colConfig.tag,
                meta: classified.meta,
                assignees: classified.assignees,
                source: source
            )
            try KanbanSidecarStore.save(sidecar, projectPath: path)
        }
    }

    /// Persist meta/assignee changes into the sidecar (when enabled) without changing column.
    public static func syncSidecarFromTags(
        path: String,
        config: ForgeConfig,
        tagStore: any TagWriting = PlatformTagStore.makeDefault(),
        source: String = Source.projectTag
    ) throws {
        guard config.nexus.sidecarEnabled else { return }
        let tags = try readAllTags(tagStore, at: path)
        let classified = classifyTags(tags, config: config)
        let sidecar = KanbanSidecarStore.make(
            column: classified.column,
            workflowTag: classified.workflowTag,
            meta: classified.meta,
            assignees: classified.assignees,
            source: source
        )
        try KanbanSidecarStore.save(sidecar, projectPath: path)
    }

    /// Paint local tags from sidecar (workflow + meta + assignees; preserves other tags).
    public static func applySidecarToTags(
        path: String,
        sidecar: KanbanSidecar,
        config: ForgeConfig,
        tagStore: any TagWriting = PlatformTagStore.makeDefault()
    ) throws {
        var tags = (try? readAllTags(tagStore, at: path)) ?? []
        tags.removeAll { config.column(forTag: $0) != nil }
        let metaSet = Set(config.board.metaTags)
        tags.removeAll { metaSet.contains($0) }
        tags.removeAll { AssigneeTag.normalisedIdentifier(fromRawTag: $0) != nil }

        if let workflow = sidecar.workflowTag ?? config.board.columns.first(where: { $0.name == sidecar.column })?.tag {
            tags.append(workflow)
        }
        tags.append(contentsOf: sidecar.meta)
        for person in sidecar.assignees {
            let tag = person.hasPrefix("#") ? person : "#\(person)"
            if !tags.contains(tag) { tags.append(tag) }
        }
        try tagStore.writeTags(tags, at: path)
    }

    public struct ClassifiedTags: Sendable {
        public let workflowTag: String?
        public let column: String?
        public let meta: [String]
        public let assignees: [String]
    }

    public static func classifyTags(_ tags: [String], config: ForgeConfig) -> ClassifiedTags {
        var workflowTag: String?
        var columnName: String?
        var metaTags: [String] = []
        var assignees: [String] = []
        let metaTagSet = Set(config.board.metaTags)
        for tag in tags {
            if let person = AssigneeTag.normalisedIdentifier(fromRawTag: tag) {
                assignees.append(person.hasPrefix("#") ? person : "#\(person)")
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
        return ClassifiedTags(
            workflowTag: workflowTag,
            column: columnName,
            meta: metaTags,
            assignees: assignees
        )
    }

    private static func readAllTags(_ store: any TagWriting, at path: String) throws -> [String] {
        if let finder = store as? FinderTagStore {
            return try finder.readTags(at: path)
        }
        if let xattr = store as? XattrTagStore {
            return try xattr.readTags(at: path)
        }
        return store.tags(at: path)
    }
}
