import Foundation

/// Executes align / sync proposals. Dry-run returns the same plan without side effects.
public enum OmniFocusPlanExecutor {

    public enum ApplyResult: Sendable {
        case dryRun(OmniFocusAlignPlan)
        case applied(applied: [OmniFocusAlignProposal], errors: [String])
    }

    /// Apply an align plan. When `apply` is false, returns dry-run and performs no writes.
    public static func executeAlign(
        plan: OmniFocusAlignPlan,
        apply: Bool,
        service: OmniFocusService,
        tagStore: FinderTagStore = FinderTagStore(),
        config: ForgeConfig,
        forgeDir: String? = nil
    ) throws -> ApplyResult {
        if !apply {
            return .dryRun(OmniFocusAlignPlan(
                generatedAt: plan.generatedAt,
                proposals: plan.proposals,
                dryRun: true
            ))
        }

        var applied: [OmniFocusAlignProposal] = []
        var errors: [String] = []

        let ensureRoot = plan.proposals.contains { $0.kind == .ensureForgeRootTag }
        let folders = plan.proposals.compactMap { p -> String? in
            guard p.kind == .createOfLinkTag else { return nil }
            return p.folderName
        }

        if ensureRoot || !folders.isEmpty {
            do {
                _ = try service.applyEnsureTags(folders: folders, ensureRoot: ensureRoot)
                for p in plan.proposals where p.kind == .ensureForgeRootTag || p.kind == .createOfLinkTag {
                    applied.append(p)
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        // Batch KanbanStatus / alias writes into one OmniJS evaluation.
        let columnKinds: Set<OmniFocusAlignKind> = [
            .setForgeColumnFromFinder, .migrateColumnTagRoot, .ensureColumnAlias,
        ]
        let columnProposals = plan.proposals.filter { columnKinds.contains($0.kind) }
        if !columnProposals.isEmpty {
            let updates: [OmniFocusService.ColumnUpdate] = columnProposals.compactMap { p in
                guard let folder = p.folderName, let column = p.column else { return nil }
                return OmniFocusService.ColumnUpdate(
                    folderName: folder,
                    column: column,
                    taskIds: p.taskIds
                )
            }
            do {
                let outcome = try service.applyForgeColumns(updates)
                if !outcome.missingAlias.isEmpty {
                    errors.append(
                        "Missing OF alias tag(s): \(outcome.missingAlias.joined(separator: ", "))"
                    )
                }
                applied.append(contentsOf: columnProposals)
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        for p in plan.proposals {
            switch p.kind {
            case .setForgeColumnFromFinder, .migrateColumnTagRoot, .ensureColumnAlias:
                break // batched above
            case .setFinderColumnFromOf:
                guard let path = p.path, let column = p.column else {
                    errors.append("Cannot apply Finder move for \(p.folderName ?? "?")")
                    continue
                }
                do {
                    try OmniFocusMoveSync.setFinderWorkflowColumn(
                        path: path,
                        column: column,
                        config: config,
                        tagStore: tagStore,
                        forgeDir: forgeDir,
                        folderName: p.folderName
                    )
                    applied.append(p)
                } catch {
                    errors.append("\(p.folderName ?? path): \(error.localizedDescription)")
                }
            case .suggestRename:
                break
            case .ignore:
                guard let forgeDir else {
                    errors.append("Cannot record ignore without forge directory")
                    continue
                }
                do {
                    try OmniFocusAlignIgnoreStore.add(
                        forgeDir: forgeDir,
                        folderName: p.folderName,
                        ofTag: p.ofTag
                    )
                    applied.append(p)
                } catch {
                    errors.append("ignore \(p.folderName ?? "?"): \(error.localizedDescription)")
                }
            case .ensureForgeRootTag, .createOfLinkTag:
                break
            case .tagMatchingOfProject:
                guard let folder = p.folderName else { continue }
                do {
                    _ = try service.applyTagMatchingOfProject(folderName: folder)
                    applied.append(p)
                } catch {
                    errors.append("\(folder): \(error.localizedDescription)")
                }
            }
        }

        return .applied(applied: applied, errors: errors)
    }
}
