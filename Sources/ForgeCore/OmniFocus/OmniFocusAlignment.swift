import Foundation

/// Prefer Finder or OmniFocus when resolving column drift during align.
public enum OmniFocusAlignPreference: String, Sendable {
    case finder
    case omnifocus
}

/// Compares Finder projects with an OmniFocus inventory (doctor + align plans).
public enum OmniFocusAlignment {

    /// Blocking buckets that keep board-level doctor "unclean" (status / allow_sync_with_drift).
    public static let blockingBuckets: Set<OmniFocusDoctorBucket> = [
        .forgeOnly, .ofOnly, .ambiguous, .columnDrift,
    ]

    /// Buckets that block `sync_on_move` for a *specific* project (not board-wide forge_only noise).
    public static let syncOnMoveBlockingBuckets: Set<OmniFocusDoctorBucket> = [
        .ambiguous,
    ]

    /// Whether `sync_on_move` should be skipped for `folderName` given a doctor report.
    ///
    /// Board-wide `forge_only` / unrelated drift must not block mirroring a linked project.
    public static func shouldBlockSyncOnMove(
        folderName: String,
        report: OmniFocusDoctorReport,
        force: Bool
    ) -> Bool {
        if force { return false }
        return report.items.contains {
            $0.folderName == folderName && syncOnMoveBlockingBuckets.contains($0.bucket)
        }
    }

    /// Build a doctor report from scanned projects and an OF inventory.
    public static func doctor(
        projects: [Project],
        inventory: OmniFocusInventory,
        config: ForgeConfig,
        ignore: OmniFocusAlignIgnoreStore.Payload = OmniFocusAlignIgnoreStore.Payload(),
        now: Date = Date()
    ) -> OmniFocusDoctorReport {
        let ofConfig = config.omnifocus
        var items: [OmniFocusDoctorItem] = []

        if !inventory.hasCanonicalRootTag {
            items.append(OmniFocusDoctorItem(
                bucket: .hygiene,
                detail: "OmniFocus has no root tag named \(ofConfig.linkTagRoot). align can create it."
            ))
        }

        let alias = ofConfig.folderAliases
        func resolveFolder(_ name: String) -> String {
            alias[name] ?? name
        }

        var tagsByFolder: [String: [OmniFocusLinkTag]] = [:]
        for tag in inventory.linkTags {
            let key = resolveFolder(tag.folderName)
            tagsByFolder[key, default: []].append(tag)
        }

        var tasksByFolder: [String: [OmniFocusTaskRecord]] = [:]
        for task in inventory.tasks {
            guard let raw = task.projectFolderName else { continue }
            let key = resolveFolder(raw)
            tasksByFolder[key, default: []].append(task)
        }

        let projectByName = Dictionary(uniqueKeysWithValues: projects.map { ($0.name, $0) })
        let projectNames = Set(projects.map(\.name))
        let ofFolders = Set(tagsByFolder.keys).union(tasksByFolder.keys)

        for name in projectNames.sorted() {
            let project = projectByName[name]!
            let tags = tagsByFolder[name] ?? []
            let tasks = tasksByFolder[name] ?? []

            if project.column == nil {
                items.append(OmniFocusDoctorItem(
                    bucket: .hygiene,
                    folderName: name,
                    path: project.path,
                    detail: "Finder folder has no workflow column tag."
                ))
            }

            if tags.count > 1 {
                items.append(OmniFocusDoctorItem(
                    bucket: .ambiguous,
                    folderName: name,
                    path: project.path,
                    detail: "Multiple OmniFocus Forge tags map to this folder: \(tags.map(\.path).joined(separator: ", "))."
                ))
                continue
            }

            if tags.isEmpty && tasks.isEmpty {
                items.append(OmniFocusDoctorItem(
                    bucket: .forgeOnly,
                    folderName: name,
                    path: project.path,
                    finderColumn: project.column,
                    detail: "Forge project has no matching OmniFocus \(ofConfig.linkTagRoot):… tag or linked tasks."
                ))
                continue
            }

            let boardOrder = config.board.columns.map(\.name)
            let ofColumns = Set(tasks.compactMap(\.forgeColumn))
            let resolvedOf = OmniFocusColumnResolution.resolveProject(
                tasks: tasks,
                boardOrder: boardOrder,
                preferFinder: project.column
            )
            if let finderCol = project.column, !tasks.isEmpty {
                let columnMarker = ofConfig.writesFlatAlias(for: finderCol)
                    ? (ofConfig.columnAlias(for: finderCol) ?? finderCol)
                    : "\(ofConfig.columnTagRoot)/*"
                if resolvedOf == nil {
                    items.append(OmniFocusDoctorItem(
                        bucket: .columnDrift,
                        folderName: name,
                        path: project.path,
                        finderColumn: finderCol,
                        detail: "Linked OF tasks have no column tag (expected \(columnMarker); Finder is \(finderCol))."
                    ))
                } else if resolvedOf != finderCol {
                    items.append(OmniFocusDoctorItem(
                        bucket: .columnDrift,
                        folderName: name,
                        path: project.path,
                        finderColumn: finderCol,
                        ofColumn: ofColumns.sorted().joined(separator: ","),
                        detail: "Finder column \(finderCol) disagrees with OF column \(resolvedOf!) (task tags: \(ofColumns.sorted().joined(separator: ", ")))."
                    ))
                } else {
                    items.append(OmniFocusDoctorItem(
                        bucket: .aligned,
                        folderName: name,
                        path: project.path,
                        ofTag: tags.first?.path,
                        finderColumn: finderCol,
                        ofColumn: finderCol,
                        detail: "Aligned (\(tasks.count) active linked task(s))."
                    ))
                    appendColumnHygiene(
                        items: &items,
                        name: name,
                        path: project.path,
                        finderCol: finderCol,
                        tasks: tasks,
                        ofConfig: ofConfig
                    )
                }
            } else if tags.isEmpty == false || tasks.isEmpty == false {
                items.append(OmniFocusDoctorItem(
                    bucket: .aligned,
                    folderName: name,
                    path: project.path,
                    ofTag: tags.first?.path,
                    finderColumn: project.column,
                    detail: "Linked (\(tasks.count) task(s))."
                ))
                if let finderCol = project.column {
                    appendColumnHygiene(
                        items: &items,
                        name: name,
                        path: project.path,
                        finderCol: finderCol,
                        tasks: tasks,
                        ofConfig: ofConfig
                    )
                }
            }
        }

        for folder in ofFolders.subtracting(projectNames).sorted() {
            if ignore.folderSet.contains(folder) { continue }
            let tag = tagsByFolder[folder]?.first
            if let path = tag?.path, ignore.ofTagSet.contains(path) { continue }
            items.append(OmniFocusDoctorItem(
                bucket: .ofOnly,
                folderName: folder,
                ofTag: tag?.path,
                detail: "OmniFocus Forge tag/tasks have no matching scanned Finder project folder."
            ))
        }

        let completedOF = Set(inventory.ofProjectSummaries.filter { $0.isCompleted }.map(\.name))
        for name in projectNames.sorted() {
            let project = projectByName[name]!
            let ofDone = completedOF.contains(name)
                || completedOF.contains(ofConfig.folderAliases[name] ?? "")
            if ofDone, project.column != "Shipped", !ignore.folderSet.contains(name) {
                items.append(OmniFocusDoctorItem(
                    bucket: .hygiene,
                    folderName: name,
                    path: project.path,
                    finderColumn: project.column,
                    ofColumn: "Shipped",
                    detail: "OmniFocus project is completed/dropped; Finder is \(project.column ?? "untagged"). Refresh can move to Shipped."
                ))
            }
        }

        let ofProjectSet = Set(inventory.ofProjectNames)
        for name in projectNames.sorted() {
            if ofProjectSet.contains(name), (tagsByFolder[name] ?? []).isEmpty, (tasksByFolder[name] ?? []).isEmpty {
                items.append(OmniFocusDoctorItem(
                    bucket: .structureHint,
                    folderName: name,
                    path: projectByName[name]?.path,
                    detail: "OmniFocus has a project/folder named \(name) but no \(ofConfig.linkTagRoot): link tag yet."
                ))
            }
        }

        return OmniFocusDoctorReport(generatedAt: now, items: items)
    }

    /// Hygiene notes for nested/legacy column tags vs flat aliases.
    private static func appendColumnHygiene(
        items: inout [OmniFocusDoctorItem],
        name: String,
        path: String?,
        finderCol: String,
        tasks: [OmniFocusTaskRecord],
        ofConfig: OmniFocusConfig
    ) {
        let legacyCount = tasks.filter { ofConfig.isLegacyColumnTagRoot($0.columnTagRoot) }.count
        if legacyCount > 0 {
            let target = ofConfig.columnTagLabel(for: finderCol)
            items.append(OmniFocusDoctorItem(
                bucket: .hygiene,
                folderName: name,
                path: path,
                finderColumn: finderCol,
                ofColumn: finderCol,
                detail: "\(legacyCount) task(s) still use a legacy column tag root; migrate to \(target)."
            ))
        }
        if ofConfig.writesFlatAlias(for: finderCol) {
            let nestedCount = tasks.filter { $0.columnTagRoot != nil }.count
            if nestedCount > 0 {
                items.append(OmniFocusDoctorItem(
                    bucket: .hygiene,
                    folderName: name,
                    path: path,
                    finderColumn: finderCol,
                    ofColumn: finderCol,
                    detail: "\(nestedCount) task(s) still have nested \(ofConfig.columnTagRoot) tags; strip to flat column tags only."
                ))
            }
        }
        if let alias = ofConfig.columnAlias(for: finderCol) {
            let missingAlias = tasks.filter { $0.columnAliasTag != alias }.count
            if missingAlias > 0 {
                let label = ofConfig.flatColumnTags ? "column tag" : "column alias tag"
                items.append(OmniFocusDoctorItem(
                    bucket: .hygiene,
                    folderName: name,
                    path: path,
                    finderColumn: finderCol,
                    ofColumn: finderCol,
                    detail: "\(missingAlias) task(s) missing \(label) \(alias)."
                ))
            }
        }
        let multiTag = tasks.filter(\.hasMultipleColumnTags)
        if !multiTag.isEmpty {
            let kept = OmniFocusColumnResolution.resolveProject(
                tasks: tasks,
                preferFinder: finderCol
            ) ?? finderCol
            items.append(OmniFocusDoctorItem(
                bucket: .hygiene,
                folderName: name,
                path: path,
                finderColumn: finderCol,
                ofColumn: kept,
                detail: "\(multiTag.count) task(s) have multiple kanban tags; policy keeps \(kept). Next sync strips extras."
            ))
        }
    }

    /// Build an align plan (always a dry-run description until applied elsewhere).
    public static func alignPlan(
        projects: [Project],
        inventory: OmniFocusInventory,
        config: ForgeConfig,
        preference: OmniFocusAlignPreference = .finder,
        ignore: OmniFocusAlignIgnoreStore.Payload = OmniFocusAlignIgnoreStore.Payload(),
        now: Date = Date()
    ) -> OmniFocusAlignPlan {
        let ofConfig = config.omnifocus
        let report = doctor(
            projects: projects,
            inventory: inventory,
            config: config,
            ignore: ignore,
            now: now
        )
        var proposals: [OmniFocusAlignProposal] = []

        if !inventory.hasCanonicalRootTag {
            proposals.append(OmniFocusAlignProposal(
                kind: .ensureForgeRootTag,
                summary: "Create OmniFocus root tag \(ofConfig.linkTagRoot)"
            ))
        }

        let structureHintNames = Set(
            report.items.filter { $0.bucket == .structureHint }.compactMap(\.folderName)
        )
        let taskCountByProject = Dictionary(
            inventory.ofProjectSummaries.map { ($0.name, $0.activeTaskCount) },
            uniquingKeysWith: { max($0, $1) }
        )

        for item in report.items {
            switch item.bucket {
            case .forgeOnly:
                // Name-matched OF projects are handled as tag_matching_of_project (structure_hint).
                if let name = item.folderName, !structureHintNames.contains(name) {
                    proposals.append(OmniFocusAlignProposal(
                        kind: .createOfLinkTag,
                        folderName: name,
                        path: item.path,
                        ofTag: ofConfig.linkTagPath(folderName: name),
                        summary: "Create OmniFocus tag \(ofConfig.linkTagPath(folderName: name)) (no matching OF project yet)"
                    ))
                }
            case .columnDrift:
                guard let name = item.folderName else { break }
                let tasks = inventory.tasks.filter { $0.projectFolderName == name || config.omnifocus.folderAliases[$0.projectFolderName ?? ""] == name }
                if preference == .finder, let col = item.finderColumn ?? projects.first(where: { $0.name == name })?.column {
                    proposals.append(OmniFocusAlignProposal(
                        kind: .setForgeColumnFromFinder,
                        folderName: name,
                        path: item.path,
                        column: col,
                        taskIds: tasks.map(\.id),
                        summary: "Set \(ofConfig.columnTagLabel(for: col)) on \(tasks.count) OF task(s) for \(name)"
                    ))
                } else if preference == .omnifocus, let ofCol = item.ofColumn?.split(separator: ",").first.map(String.init) {
                    proposals.append(OmniFocusAlignProposal(
                        kind: .setFinderColumnFromOf,
                        folderName: name,
                        path: item.path,
                        column: ofCol,
                        summary: "Move Finder project \(name) to column \(ofCol) to match OF"
                    ))
                }
            case .ofOnly:
                proposals.append(OmniFocusAlignProposal(
                    kind: .suggestRename,
                    folderName: item.folderName,
                    ofTag: item.ofTag,
                    summary: "Manual: OF-only tag \(item.ofTag ?? item.folderName ?? "?") — rename, alias, or ignore"
                ))
                if let name = item.folderName {
                    proposals.append(OmniFocusAlignProposal(
                        kind: .ignore,
                        folderName: name,
                        ofTag: item.ofTag,
                        summary: "Ignore OF-only \(item.ofTag ?? name) in future doctor/align"
                    ))
                }
            case .structureHint:
                if let name = item.folderName {
                    let n = taskCountByProject[name] ?? 0
                    proposals.append(OmniFocusAlignProposal(
                        kind: .tagMatchingOfProject,
                        folderName: name,
                        path: item.path,
                        ofTag: ofConfig.linkTagPath(folderName: name),
                        summary: "Tag OF project \(name) and \(n) active task(s) with \(ofConfig.linkTagPath(folderName: name))"
                    ))
                }
            case .hygiene:
                if item.detail.contains("legacy column tag root"),
                   let name = item.folderName,
                   let col = item.finderColumn ?? projects.first(where: { $0.name == name })?.column {
                    let tasks = inventory.tasks.filter {
                        ($0.projectFolderName == name || config.omnifocus.folderAliases[$0.projectFolderName ?? ""] == name)
                            && ofConfig.isLegacyColumnTagRoot($0.columnTagRoot)
                    }
                    let legacyRoots = Set(tasks.compactMap(\.columnTagRoot)).sorted()
                    proposals.append(OmniFocusAlignProposal(
                        kind: .migrateColumnTagRoot,
                        folderName: name,
                        path: item.path,
                        column: col,
                        taskIds: tasks.map(\.id),
                        summary: "Migrate \(legacyRoots.joined(separator: ", "))/\(col) → \(ofConfig.columnTagLabel(for: col)) on \(tasks.count) task(s) for \(name)"
                    ))
                } else if item.detail.contains("nested \(ofConfig.columnTagRoot) tags"),
                          let name = item.folderName,
                          let col = item.finderColumn ?? projects.first(where: { $0.name == name })?.column {
                    let tasks = inventory.tasks.filter {
                        ($0.projectFolderName == name || config.omnifocus.folderAliases[$0.projectFolderName ?? ""] == name)
                            && $0.columnTagRoot != nil
                    }
                    proposals.append(OmniFocusAlignProposal(
                        kind: .ensureColumnAlias,
                        folderName: name,
                        path: item.path,
                        column: col,
                        taskIds: tasks.map(\.id),
                        summary: "Strip nested \(ofConfig.columnTagRoot) and keep \(ofConfig.columnTagLabel(for: col)) on \(tasks.count) task(s) for \(name)"
                    ))
                } else if item.detail.contains("OmniFocus project is completed"),
                          let name = item.folderName,
                          let path = item.path {
                    proposals.append(OmniFocusAlignProposal(
                        kind: .setFinderColumnFromOf,
                        folderName: name,
                        path: path,
                        column: "Shipped",
                        summary: "Move Finder \(name) to Shipped (OF project completed)"
                    ))
                } else if item.detail.contains("multiple kanban tags"),
                          let name = item.folderName,
                          let col = item.finderColumn ?? item.ofColumn ?? projects.first(where: { $0.name == name })?.column {
                    let tasks = inventory.tasks.filter {
                        ($0.projectFolderName == name || config.omnifocus.folderAliases[$0.projectFolderName ?? ""] == name)
                            && $0.hasMultipleColumnTags
                    }
                    proposals.append(OmniFocusAlignProposal(
                        kind: .ensureColumnAlias,
                        folderName: name,
                        path: item.path,
                        column: col,
                        taskIds: tasks.map(\.id),
                        summary: "Keep single column tag \(ofConfig.columnTagLabel(for: col)) on \(tasks.count) multi-tagged task(s) for \(name)"
                    ))
                } else if item.detail.contains("missing column"),
                          let name = item.folderName,
                          let col = item.finderColumn ?? projects.first(where: { $0.name == name })?.column,
                          let alias = ofConfig.columnAlias(for: col) {
                    let tasks = inventory.tasks.filter {
                        ($0.projectFolderName == name || config.omnifocus.folderAliases[$0.projectFolderName ?? ""] == name)
                            && $0.columnAliasTag != alias
                    }
                    proposals.append(OmniFocusAlignProposal(
                        kind: .ensureColumnAlias,
                        folderName: name,
                        path: item.path,
                        column: col,
                        taskIds: tasks.map(\.id),
                        summary: "Set \(alias) on \(tasks.count) task(s) for \(name)"
                    ))
                } else if item.detail.contains("root tag") {
                    break
                }
            case .aligned, .ambiguous:
                break
            }
        }

        return OmniFocusAlignPlan(
            generatedAt: now,
            proposals: dedupeColumnAliasProposals(proposals),
            dryRun: true
        )
    }

    /// Prefer a single rewrite per folder/column when strip-nested and missing-tag both fire.
    private static func dedupeColumnAliasProposals(
        _ proposals: [OmniFocusAlignProposal]
    ) -> [OmniFocusAlignProposal] {
        var seen: Set<String> = []
        var result: [OmniFocusAlignProposal] = []
        for proposal in proposals {
            guard proposal.kind == .ensureColumnAlias,
                  let folder = proposal.folderName,
                  let column = proposal.column
            else {
                result.append(proposal)
                continue
            }
            let key = "\(folder)|\(column)"
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(proposal)
        }
        return result
    }

    /// Enrichment map for board JSON.
    public static func enrichmentByFolder(
        inventory: OmniFocusInventory,
        now: Date = Date()
    ) -> [String: OmniFocusBoardEnrichment] {
        let age = now.timeIntervalSince(inventory.generatedAt)
        var grouped: [String: [OmniFocusTaskRecord]] = [:]
        for task in inventory.tasks {
            guard let name = task.projectFolderName else { continue }
            grouped[name, default: []].append(task)
        }
        var result: [String: OmniFocusBoardEnrichment] = [:]
        for (name, tasks) in grouped {
            let sorted = tasks.sorted { a, b in
                switch (a.due, b.due) {
                case let (ad?, bd?): return ad < bd
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.title < b.title
                }
            }
            let next = sorted.first
            result[name] = OmniFocusBoardEnrichment(
                taskCount: tasks.count,
                nextTask: next?.title,
                due: next?.due,
                forgeColumn: next?.forgeColumn,
                snapshotAgeSeconds: age
            )
        }
        return result
    }
}
