import Foundation

/// Doctor / sync between portable sidecar and local folder tags.
public enum KanbanFsSync {

    public enum Prefer: String, Sendable {
        case sidecar
        case finder
    }

    public struct Drift: Sendable, Equatable {
        public let project: String
        public let path: String
        public let sidecarColumn: String?
        public let tagColumn: String?
        public let issue: String

        public init(project: String, path: String, sidecarColumn: String?, tagColumn: String?, issue: String) {
            self.project = project
            self.path = path
            self.sidecarColumn = sidecarColumn
            self.tagColumn = tagColumn
            self.issue = issue
        }
    }

    public struct Change: Sendable, Equatable {
        public let project: String
        public let path: String
        public let action: String
        public let detail: String

        public init(project: String, path: String, action: String, detail: String) {
            self.project = project
            self.path = path
            self.action = action
            self.detail = detail
        }
    }

    /// Report portable state disagreements (and missing sidecars when enabled).
    public static func doctor(
        projects: [Project],
        config: ForgeConfig,
        tagStore: any TagWriting = PlatformTagStore.makeDefault()
    ) throws -> [Drift] {
        var drifts: [Drift] = []
        for project in projects {
            let tags = syncTags(from: tagStore, at: project.path)
            let classified = KanbanNexus.classifyTags(tags, config: config)
            let sidecar = try KanbanSidecarStore.load(projectPath: project.path)
            if sidecar == nil, config.nexus.sidecarEnabled, classified.column != nil {
                drifts.append(Drift(
                    project: project.name,
                    path: project.path,
                    sidecarColumn: nil,
                    tagColumn: classified.column,
                    issue: "missing-sidecar"
                ))
                continue
            }
            guard let sidecar else { continue }
            if !matches(sidecar, classified) {
                drifts.append(Drift(
                    project: project.name,
                    path: project.path,
                    sidecarColumn: sidecar.column,
                    tagColumn: classified.column,
                    issue: sidecar.column != classified.column ? "column-drift" : "metadata-drift"
                ))
            }
        }
        return drifts
    }

    /// Reconcile sidecar and tags. Dry-run when `apply` is false.
    public static func sync(
        projects: [Project],
        config: ForgeConfig,
        prefer: Prefer = .sidecar,
        apply: Bool,
        tagStore: any TagWriting = PlatformTagStore.makeDefault()
    ) throws -> [Change] {
        var changes: [Change] = []
        for project in projects {
            let tags = syncTags(from: tagStore, at: project.path)
            let classified = KanbanNexus.classifyTags(tags, config: config)
            let sidecar = try KanbanSidecarStore.load(projectPath: project.path)

            if sidecar == nil {
                if classified.column == nil, classified.meta.isEmpty, classified.assignees.isEmpty {
                    continue
                }
                let built = KanbanSidecarStore.make(
                    column: classified.column,
                    workflowTag: classified.workflowTag,
                    meta: classified.meta,
                    assignees: classified.assignees,
                    source: KanbanNexus.Source.migrate
                )
                changes.append(Change(
                    project: project.name,
                    path: project.path,
                    action: "create-sidecar",
                    detail: built.column ?? "(untagged)"
                ))
                if apply {
                    try KanbanSidecarStore.save(built, projectPath: project.path)
                }
                continue
            }

            guard let current = sidecar else { continue }
            if matches(current, classified) {
                continue
            }

            switch prefer {
            case .sidecar:
                changes.append(Change(
                    project: project.name,
                    path: project.path,
                    action: "sidecar-to-tags",
                    detail: changeDetail(from: classified.column, to: current.column)
                ))
                if apply {
                    try KanbanNexus.applySidecarToTags(
                        path: project.path,
                        sidecar: current,
                        config: config,
                        tagStore: tagStore
                    )
                }
            case .finder:
                let built = KanbanSidecarStore.make(
                    column: classified.column,
                    workflowTag: classified.workflowTag,
                    meta: classified.meta,
                    assignees: classified.assignees,
                    source: KanbanNexus.Source.fsImport
                )
                changes.append(Change(
                    project: project.name,
                    path: project.path,
                    action: "tags-to-sidecar",
                    detail: changeDetail(from: current.column, to: built.column)
                ))
                if apply {
                    try KanbanSidecarStore.save(built, projectPath: project.path)
                }
            }
        }
        return changes
    }

    /// Bootstrap sidecars from local tags for all projects (dry-run unless apply).
    public static func migrate(
        projects: [Project],
        config: ForgeConfig,
        apply: Bool,
        tagStore: any TagWriting = PlatformTagStore.makeDefault(),
        overwrite: Bool = false
    ) throws -> [Change] {
        var changes: [Change] = []
        for project in projects {
            if !overwrite, try KanbanSidecarStore.load(projectPath: project.path) != nil {
                continue
            }
            let tags = syncTags(from: tagStore, at: project.path)
            let classified = KanbanNexus.classifyTags(tags, config: config)
            let built = KanbanSidecarStore.make(
                column: classified.column,
                workflowTag: classified.workflowTag,
                meta: classified.meta,
                assignees: classified.assignees,
                source: KanbanNexus.Source.migrate
            )
            changes.append(Change(
                project: project.name,
                path: project.path,
                action: overwrite ? "overwrite-sidecar" : "create-sidecar",
                detail: built.column ?? "(untagged)"
            ))
            if apply {
                try KanbanSidecarStore.save(built, projectPath: project.path)
            }
        }
        return changes
    }

    /// Paint all projects' tags from sidecars (used on Refresh).
    @discardableResult
    public static func paintAllFromSidecar(
        projects: [Project],
        config: ForgeConfig,
        tagStore: any TagWriting = PlatformTagStore.makeDefault()
    ) throws -> [Change] {
        var changes: [Change] = []
        for project in projects {
            guard let sidecar = try KanbanSidecarStore.load(projectPath: project.path) else { continue }
            let tags = syncTags(from: tagStore, at: project.path)
            let classified = KanbanNexus.classifyTags(tags, config: config)
            if matches(sidecar, classified) { continue }
            try KanbanNexus.applySidecarToTags(
                path: project.path,
                sidecar: sidecar,
                config: config,
                tagStore: tagStore
            )
            changes.append(Change(
                project: project.name,
                path: project.path,
                action: "sidecar-to-tags",
                detail: sidecar.column ?? "(untagged)"
            ))
        }
        return changes
    }

    /// Tag order does not change the portable state; assignees accept either spelling.
    private static func matches(_ sidecar: KanbanSidecar, _ tags: KanbanNexus.ClassifiedTags) -> Bool {
        let assignees = Set(sidecar.assignees.map { $0.hasPrefix("#") ? $0 : "#\($0)" })
        return sidecar.column == tags.column
            && Set(sidecar.meta) == Set(tags.meta)
            && assignees == Set(tags.assignees)
    }

    private static func changeDetail(from previous: String?, to next: String?) -> String {
        if previous == next { return "\(next ?? "Untagged"): meta tags or assignees changed" }
        return "\(previous ?? "Untagged") → \(next ?? "Untagged")"
    }
}
