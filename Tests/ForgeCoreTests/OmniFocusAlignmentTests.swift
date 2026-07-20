import Foundation
import ForgeCore
import Testing

@Suite("OmniFocus alignment")
struct OmniFocusAlignmentTests {

    private func project(name: String, column: String?, path: String = "/tmp/p") -> Project {
        Project(
            name: name,
            path: path + "/" + name,
            tags: [],
            workflowTag: column.map { "\($0) tag" },
            column: column,
            metaTags: [],
            assignees: []
        )
    }

    private func inventory(
        hasRoot: Bool = true,
        tags: [OmniFocusLinkTag] = [],
        tasks: [OmniFocusTaskRecord] = [],
        ofProjects: [String] = [],
        ofProjectSummaries: [OmniFocusProjectSummary] = []
    ) -> OmniFocusInventory {
        OmniFocusInventory(
            generatedAt: Date(),
            hasForgeRootTag: hasRoot,
            linkTags: tags,
            tasks: tasks,
            ofProjectNames: ofProjects,
            ofProjectSummaries: ofProjectSummaries.isEmpty
                ? ofProjects.map { OmniFocusProjectSummary(name: $0, activeTaskCount: 0) }
                : ofProjectSummaries
        )
    }

    @Test("Doctor marks forge-only projects")
    func forgeOnly() {
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let projects = [project(name: "Alpha", column: "Watch")]
        let inv = inventory()
        let report = OmniFocusAlignment.doctor(projects: projects, inventory: inv, config: config)
        #expect(report.items.contains { $0.bucket == .forgeOnly && $0.folderName == "Alpha" })
        #expect(!report.isClean)
    }

    @Test("Doctor marks OF-only tags")
    func ofOnly() {
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let inv = inventory(tags: [
            OmniFocusLinkTag(path: "🔥 Forge:Ghost", folderName: "Ghost", taskCount: 1),
        ])
        let report = OmniFocusAlignment.doctor(projects: [], inventory: inv, config: config)
        #expect(report.items.contains { $0.bucket == .ofOnly && $0.folderName == "Ghost" })
    }

    @Test("Doctor reports column drift")
    func columnDrift() {
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let projects = [project(name: "Alpha", column: "Coding")]
        let inv = inventory(
            tags: [OmniFocusLinkTag(path: "🔥 Forge:Alpha", folderName: "Alpha", taskCount: 1)],
            tasks: [
                OmniFocusTaskRecord(
                    id: "1",
                    title: "Do thing",
                    projectFolderName: "Alpha",
                    projectTag: "🔥 Forge:Alpha",
                    forgeColumn: "Watch",
                    due: nil,
                    completed: false,
                    ofProjectName: nil
                ),
            ]
        )
        let report = OmniFocusAlignment.doctor(projects: projects, inventory: inv, config: config)
        #expect(report.items.contains { $0.bucket == .columnDrift && $0.folderName == "Alpha" })
    }

    @Test("Structure hint proposes tag_matching_of_project only")
    func structureHintTagsProject() {
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let projects = [project(name: "Lepto", column: "Watch")]
        let inv = inventory(
            hasRoot: true,
            ofProjects: ["Lepto"],
            ofProjectSummaries: [OmniFocusProjectSummary(name: "Lepto", activeTaskCount: 3)]
        )
        let plan = OmniFocusAlignment.alignPlan(projects: projects, inventory: inv, config: config)
        #expect(plan.dryRun)
        #expect(plan.proposals.contains {
            $0.kind == .tagMatchingOfProject && $0.folderName == "Lepto" && $0.summary.contains("3 active")
        })
        #expect(!plan.proposals.contains { $0.kind == .createOfLinkTag && $0.folderName == "Lepto" })
    }

    @Test("Align plan dry-run proposes create link tag")
    func alignProposesCreate() {
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let projects = [project(name: "Alpha", column: "Watch")]
        let inv = inventory(hasRoot: false)
        let plan = OmniFocusAlignment.alignPlan(projects: projects, inventory: inv, config: config)
        #expect(plan.dryRun)
        #expect(plan.proposals.contains { $0.kind == .ensureForgeRootTag })
        #expect(plan.proposals.contains { $0.kind == .createOfLinkTag && $0.folderName == "Alpha" })
        #expect(!plan.proposals.contains { $0.kind == .tagMatchingOfProject })
    }

    @Test("Plan executor dry-run does not call writes")
    func executorDryRun() throws {
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let plan = OmniFocusAlignPlan(
            generatedAt: Date(),
            proposals: [
                OmniFocusAlignProposal(kind: .ensureForgeRootTag, summary: "Create Forge"),
            ],
            dryRun: true
        )
        let service = OmniFocusService(config: config)
        let result = try OmniFocusPlanExecutor.executeAlign(
            plan: plan,
            apply: false,
            service: service,
            config: config
        )
        guard case .dryRun(let out) = result else {
            Issue.record("Expected dry-run result")
            return
        }
        #expect(out.dryRun)
        #expect(out.proposals.count == 1)
    }

    @Test("Enrichment groups tasks by folder")
    func enrichment() {
        let inv = inventory(tasks: [
            OmniFocusTaskRecord(
                id: "1",
                title: "First",
                projectFolderName: "Alpha",
                projectTag: "🔥 Forge:Alpha",
                forgeColumn: "Coding",
                due: Date().addingTimeInterval(3600),
                completed: false,
                ofProjectName: nil
            ),
        ])
        let map = OmniFocusAlignment.enrichmentByFolder(inventory: inv)
        #expect(map["Alpha"]?.taskCount == 1)
        #expect(map["Alpha"]?.nextTask == "First")
    }

    @Test("Legacy Forge: tags still count as linked")
    func legacyRootReadable() {
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let projects = [project(name: "Alpha", column: "Coding")]
        let inv = inventory(
            tags: [OmniFocusLinkTag(path: "Forge:Alpha", folderName: "Alpha", taskCount: 1)],
            tasks: [
                OmniFocusTaskRecord(
                    id: "1",
                    title: "Legacy link",
                    projectFolderName: "Alpha",
                    projectTag: "Forge:Alpha",
                    forgeColumn: "Coding",
                    columnTagRoot: "KanbanStatus",
                    due: nil,
                    completed: false,
                    ofProjectName: nil
                ),
            ]
        )
        let report = OmniFocusAlignment.doctor(projects: projects, inventory: inv, config: config)
        #expect(report.items.contains { $0.bucket == .aligned && $0.folderName == "Alpha" })
    }

    @Test("Legacy ForgeColumn tags propose migrate to nested KanbanStatus when no flat alias")
    func migrateLegacyColumnRoot() {
        var of = OmniFocusConfig()
        of.flatColumnTags = true
        let base = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let config = ForgeConfig(
            projectRoots: base.projectRoots,
            board: base.board,
            calendar: base.calendar,
            omnifocus: of,
            gtd: base.gtd,
            workspaceTags: base.workspaceTags,
            projectAreas: base.projectAreas,
            terminal: base.terminal,
            projectTag: base.projectTag,
            projectScanDepth: base.projectScanDepth,
            dueConflictPolicy: base.dueConflictPolicy
        )
        let projects = [project(name: "Alpha", column: "Write")]
        let inv = inventory(
            tags: [OmniFocusLinkTag(path: "🔥 Forge:Alpha", folderName: "Alpha", taskCount: 1)],
            tasks: [
                OmniFocusTaskRecord(
                    id: "1",
                    title: "Old column tag",
                    projectFolderName: "Alpha",
                    projectTag: "🔥 Forge:Alpha",
                    forgeColumn: "Write",
                    columnTagRoot: "ForgeColumn",
                    due: nil,
                    completed: false,
                    ofProjectName: nil
                ),
            ]
        )
        let plan = OmniFocusAlignment.alignPlan(projects: projects, inventory: inv, config: config)
        #expect(plan.proposals.contains {
            $0.kind == .migrateColumnTagRoot
                && $0.folderName == "Alpha"
                && $0.column == "Write"
                && $0.summary.contains("KanbanStatus/Write")
        })
    }

    @Test("sync_on_move is not blocked by unrelated forge_only drift")
    func syncOnMoveIgnoresBoardWideForgeOnly() {
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let projects = [
            project(name: "Alpha", column: "Watch"),
            project(name: "Other", column: "Watch"),
        ]
        let inv = inventory(
            tags: [OmniFocusLinkTag(path: "🔥 Forge:Alpha", folderName: "Alpha", taskCount: 1)],
            tasks: [
                OmniFocusTaskRecord(
                    id: "1",
                    title: "Linked",
                    projectFolderName: "Alpha",
                    projectTag: "🔥 Forge:Alpha",
                    forgeColumn: "Watch",
                    columnTagRoot: "KanbanStatus",
                    due: nil,
                    completed: false,
                    ofProjectName: nil
                ),
            ]
        )
        let report = OmniFocusAlignment.doctor(projects: projects, inventory: inv, config: config)
        #expect(!report.isClean) // Other is forge_only
        #expect(!OmniFocusAlignment.shouldBlockSyncOnMove(folderName: "Alpha", report: report, force: false))
    }

    @Test("unanimousOmniFocusColumn requires a single column")
    func unanimousColumn() {
        let watch = OmniFocusTaskRecord(
            id: "1", title: "A", projectFolderName: "P", projectTag: "🔥 Forge:P",
            forgeColumn: "Watch", due: nil, completed: false, ofProjectName: nil
        )
        let coding = OmniFocusTaskRecord(
            id: "2", title: "B", projectFolderName: "P", projectTag: "🔥 Forge:P",
            forgeColumn: "Coding", due: nil, completed: false, ofProjectName: nil
        )
        #expect(OmniFocusMoveSync.unanimousOmniFocusColumn(tasks: [watch]) == "Watch")
        #expect(OmniFocusMoveSync.unanimousOmniFocusColumn(tasks: [watch, watch]) == "Watch")
        #expect(OmniFocusMoveSync.unanimousOmniFocusColumn(tasks: [watch, coding]) == nil)
        #expect(OmniFocusMoveSync.unanimousOmniFocusColumn(tasks: []) == nil)
    }

    @Test("Multi-tag task prefers Finder match then furthest column")
    func multiTagResolution() {
        let resolution = OmniFocusColumnResolution.resolveTask(
            columns: ["Watch", "Coding", "Write"],
            preferFinder: "Coding"
        )
        #expect(resolution.resolved == "Coding")
        #expect(resolution.isAmbiguous)

        let furthest = OmniFocusColumnResolution.resolveTask(columns: ["Plan", "Review", "Watch"])
        #expect(furthest.resolved == "Review")

        let multi = OmniFocusTaskRecord(
            id: "1", title: "Mixed", projectFolderName: "P", projectTag: "🔥 Forge:P",
            forgeColumn: "Review",
            forgeColumns: ["Watch", "Review"],
            due: nil, completed: false, ofProjectName: nil
        )
        let single = OmniFocusTaskRecord(
            id: "2", title: "One", projectFolderName: "P", projectTag: "🔥 Forge:P",
            forgeColumn: "Review",
            forgeColumns: ["Review"],
            due: nil, completed: false, ofProjectName: nil
        )
        #expect(OmniFocusMoveSync.resolvedOmniFocusColumn(tasks: [multi, single]) == "Review")
        #expect(
            OmniFocusMoveSync.resolvedOmniFocusColumn(
                tasks: [multi],
                preferFinder: "Watch"
            ) == "Watch"
        )
    }

    @Test("Completed OF project proposes Finder Shipped")
    func completedProjectToShipped() {
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let projects = [project(name: "Alpha", column: "Coding")]
        let inv = inventory(
            tags: [OmniFocusLinkTag(path: "🔥 Forge:Alpha", folderName: "Alpha", taskCount: 0)],
            ofProjects: ["Alpha"],
            ofProjectSummaries: [
                OmniFocusProjectSummary(name: "Alpha", activeTaskCount: 0, isCompleted: true),
            ]
        )
        let report = OmniFocusAlignment.doctor(projects: projects, inventory: inv, config: config)
        #expect(report.items.contains {
            $0.bucket == .hygiene && $0.detail.contains("completed/dropped") && $0.folderName == "Alpha"
        })
        let plan = OmniFocusAlignment.alignPlan(projects: projects, inventory: inv, config: config)
        #expect(plan.proposals.contains {
            $0.kind == .setFinderColumnFromOf && $0.column == "Shipped" && $0.folderName == "Alpha"
        })
    }

    @Test("Ignore list suppresses OF-only doctor items")
    func ignoreList() {
        let config = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let inv = inventory(tags: [
            OmniFocusLinkTag(path: "🔥 Forge:Ghost", folderName: "Ghost", taskCount: 1),
        ])
        let ignore = OmniFocusAlignIgnoreStore.Payload(folderNames: ["Ghost"])
        let report = OmniFocusAlignment.doctor(
            projects: [],
            inventory: inv,
            config: config,
            ignore: ignore
        )
        #expect(!report.items.contains { $0.bucket == .ofOnly && $0.folderName == "Ghost" })
    }

    @Test("OF→Finder pull prefers stacked tag that differs from Finder")
    func pullPrefersDifferingStackedTag() {
        let multi = OmniFocusTaskRecord(
            id: "1", title: "Mixed", projectFolderName: "P", projectTag: "🔥 Forge:P",
            forgeColumn: "Review",
            forgeColumns: ["Watch", "Review"],
            due: nil, completed: false, ofProjectName: nil
        )
        // User added Watch while Review remained — pull must take Watch, not furthest (Review).
        #expect(
            OmniFocusColumnResolution.resolveForPull(
                columns: ["Watch", "Review"],
                finderColumn: "Review"
            ) == "Watch"
        )
        #expect(
            OmniFocusMoveSync.resolvedOmniFocusColumnForPull(
                tasks: [multi],
                finderColumn: "Review"
            ) == "Watch"
        )
        // Single differing tag still wins when Finder already matches one of them.
        #expect(
            OmniFocusColumnResolution.resolveForPull(
                columns: ["Watch"],
                finderColumn: "Review"
            ) == "Watch"
        )
        // No difference from Finder → keep normal furthest pick.
        #expect(
            OmniFocusColumnResolution.resolveForPull(
                columns: ["Watch", "Review"],
                finderColumn: "Review"
            ) == "Watch"
        )
        #expect(
            OmniFocusColumnResolution.resolveForPull(
                columns: ["Review"],
                finderColumn: "Review"
            ) == "Review"
        )
    }

    @Test("OF→Finder resolution does not prefer stale Finder column")
    func pullIgnoresPreferFinder() {
        let multi = OmniFocusTaskRecord(
            id: "1", title: "Mixed", projectFolderName: "P", projectTag: "🔥 Forge:P",
            forgeColumn: "Coding",
            forgeColumns: ["Watch", "Coding"],
            due: nil, completed: false, ofProjectName: nil
        )
        // Default resolve still prefers furthest when preferFinder is nil.
        #expect(
            OmniFocusMoveSync.resolvedOmniFocusColumn(
                tasks: [multi],
                preferFinder: nil
            ) == "Coding"
        )
        // Both differ from Review — furthest among differing is Coding.
        #expect(
            OmniFocusMoveSync.resolvedOmniFocusColumnForPull(
                tasks: [multi],
                finderColumn: "Review"
            ) == "Coding"
        )
        #expect(
            OmniFocusColumnResolution.resolveTask(
                columns: ["Watch", "Coding"],
                preferFinder: nil
            ).resolved == "Coding"
        )
    }

    @Test("Missing flat column tag proposes ensure_column_alias")
    func ensureColumnAlias() {
        var of = OmniFocusConfig()
        of.flatColumnTags = true
        of.columnTagAliases = ["Write": "Write ✒️"]
        let base = ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
        let config = ForgeConfig(
            projectRoots: base.projectRoots,
            board: base.board,
            calendar: base.calendar,
            omnifocus: of,
            gtd: base.gtd,
            workspaceTags: base.workspaceTags,
            projectAreas: base.projectAreas,
            terminal: base.terminal,
            projectTag: base.projectTag,
            projectScanDepth: base.projectScanDepth,
            dueConflictPolicy: base.dueConflictPolicy
        )
        let projects = [project(name: "Alpha", column: "Write")]
        let inv = inventory(
            tags: [OmniFocusLinkTag(path: "🔥 Forge:Alpha", folderName: "Alpha", taskCount: 1)],
            tasks: [
                OmniFocusTaskRecord(
                    id: "1",
                    title: "Needs alias",
                    projectFolderName: "Alpha",
                    projectTag: "🔥 Forge:Alpha",
                    forgeColumn: "Write",
                    columnTagRoot: "KanbanStatus",
                    columnAliasTag: nil,
                    due: nil,
                    completed: false,
                    ofProjectName: nil
                ),
            ]
        )
        let plan = OmniFocusAlignment.alignPlan(projects: projects, inventory: inv, config: config)
        #expect(plan.proposals.filter { $0.kind == .ensureColumnAlias && $0.folderName == "Alpha" }.count == 1)
        #expect(plan.proposals.contains {
            $0.kind == .ensureColumnAlias
                && $0.folderName == "Alpha"
                && $0.summary.contains("Strip nested KanbanStatus")
                && $0.summary.contains("Write ✒️")
        })
    }
}

@Suite("OmniFocus snapshot store")
struct OmniFocusSnapshotStoreTests {
    @Test("Round-trip snapshot payload")
    func roundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let inventory = OmniFocusInventory(
            generatedAt: Date(),
            hasForgeRootTag: true,
            linkTags: [],
            tasks: [],
            ofProjectNames: ["X"]
        )
        try OmniFocusSnapshotStore.write(forgeDir: dir.path, inventory: inventory)
        let loaded = try OmniFocusSnapshotStore.loadIfEligible(
            forgeDir: dir.path,
            maxAge: 900
        )
        #expect(loaded?.ofProjectNames == ["X"])
    }

    @Test("Stale snapshot is ineligible")
    func stale() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let inventory = OmniFocusInventory(
            generatedAt: Date().addingTimeInterval(-10_000),
            hasForgeRootTag: true,
            linkTags: [],
            tasks: [],
            ofProjectNames: []
        )
        try OmniFocusSnapshotStore.write(forgeDir: dir.path, inventory: inventory)
        let loaded = try OmniFocusSnapshotStore.loadIfEligible(forgeDir: dir.path, maxAge: 60)
        #expect(loaded == nil)
    }
}
