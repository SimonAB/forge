import ArgumentParser
import Foundation
import ForgeCore

/// OmniFocus bridge: doctor, align (dry-run default), refresh, status.
struct OmniFocusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "omnifocus",
        abstract: "OmniFocus alignment and sync (dry-run by default for mutating actions).",
        subcommands: [
            Doctor.self,
            Align.self,
            Refresh.self,
            Status.self,
            Show.self,
            Proposals.self,
            Apply.self,
        ]
    )
}

// MARK: - Shared helpers

private enum OmniFocusCLI {
    static func loadContext() throws -> (ForgeConfig, String, OmniFocusService) {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let service = OmniFocusService(config: config)
        return (config, forgeDir, service)
    }

    static func inventory(service: OmniFocusService, forgeDir: String, live: Bool) throws -> OmniFocusInventory {
        if live {
            return try service.refreshSnapshot(forgeDir: forgeDir)
        }
        if let snap = try service.loadEligibleSnapshot(forgeDir: forgeDir) {
            return snap
        }
        return try service.refreshSnapshot(forgeDir: forgeDir)
    }

    static func printPlan(_ plan: OmniFocusAlignPlan) {
        let mode = plan.dryRun ? "DRY-RUN (no changes)" : "APPLY"
        print("OmniFocus align plan — \(mode)")
        print(String(repeating: "─", count: 48))
        if plan.proposals.isEmpty {
            print("No proposals.")
            return
        }
        for (i, p) in plan.proposals.enumerated() {
            print("\(i + 1). [\(p.kind.rawValue)] \(p.summary)")
            if let tag = p.ofTag { print("    tag: \(tag)") }
            if let col = p.column { print("    column: \(col)") }
            if !p.taskIds.isEmpty { print("    tasks: \(p.taskIds.count)") }
        }
        if plan.dryRun {
            print()
            print("Re-run with --apply to perform these changes.")
        }
    }

    static func encodeJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        if let s = String(data: data, encoding: .utf8) { print(s) }
    }
}

extension OmniFocusCommand {
    struct Doctor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "doctor",
            abstract: "Compare Finder projects with OmniFocus Forge tags (read-only)."
        )

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        @Flag(name: .long, help: "Force a live OmniFocus export (refresh snapshot).")
        var live = false

        mutating func run() async throws {
            let (config, forgeDir, service) = try OmniFocusCLI.loadContext()
            try service.requireEnabled()
            let scanner = WorkspaceScanner(config: config)
            let projects = try await scanner.scanProjects()
            let inventory = try OmniFocusCLI.inventory(service: service, forgeDir: forgeDir, live: live)
            let ignore = OmniFocusAlignIgnoreStore.load(forgeDir: forgeDir)
            let report = OmniFocusAlignment.doctor(
                projects: projects,
                inventory: inventory,
                config: config,
                ignore: ignore
            )

            if json {
                try OmniFocusCLI.encodeJSON(report)
                return
            }

            print("OmniFocus doctor — \(report.isClean ? "CLEAN" : "DRIFT")")
            print(String(repeating: "─", count: 48))
            let grouped = Dictionary(grouping: report.items, by: \.bucket)
            for bucket in [
                OmniFocusDoctorBucket.forgeOnly,
                .ofOnly,
                .ambiguous,
                .columnDrift,
                .structureHint,
                .hygiene,
                .aligned,
            ] {
                guard let items = grouped[bucket], !items.isEmpty else { continue }
                print("\n\(bucket.rawValue) (\(items.count))")
                for item in items.prefix(40) {
                    let name = item.folderName ?? item.ofTag ?? "—"
                    print("  • \(name): \(item.detail)")
                }
                if items.count > 40 {
                    print("  … \(items.count - 40) more")
                }
            }
            print()
            if !report.isClean {
                print("Next: forge omnifocus align   # dry-run plan")
            }
        }
    }

    struct Align: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "align",
            abstract: "Propose (default) or apply alignment between Finder and OmniFocus."
        )

        @Flag(name: .long, help: "Perform writes. Default is dry-run.")
        var apply = false

        @Flag(name: .long, help: "With --apply, skip the interactive confirmation line.")
        var yes = false

        @Flag(name: .long, help: "Emit JSON plan.")
        var json = false

        @Flag(name: .long, help: "Force a live OmniFocus export.")
        var live = false

        @Option(name: .long, help: "On column drift: finder (default) or omnifocus.")
        var prefer: String = "finder"

        @Flag(name: .customLong("structure-hints-only"), help: "Only propose tag_matching_of_project (name-matched OF projects).")
        var structureHintsOnly = false

        @Flag(name: .customLong("column-only"), help: "Only propose OF / Finder column drift fixes.")
        var columnOnly = false

        @Flag(name: .customLong("migrate-columns-only"), help: "Only propose migrating legacy ForgeColumn tags onto the configured column markers.")
        var migrateColumnsOnly = false

        @Flag(name: .customLong("aliases-only"), help: "Only propose flat column_tag_aliases (and stripping nested KanbanStatus duplicates).")
        var aliasesOnly = false

        @Option(name: .long, help: "Limit proposals to one project folder name (exact match).")
        var folder: String?

        mutating func run() async throws {
            let (config, forgeDir, service) = try OmniFocusCLI.loadContext()
            try service.requireEnabled()
            guard let preference = OmniFocusAlignPreference(rawValue: prefer.lowercased()) else {
                throw ValidationError("--prefer must be finder or omnifocus")
            }
            let exclusiveFilters = [structureHintsOnly, columnOnly, migrateColumnsOnly, aliasesOnly].filter { $0 }.count
            if exclusiveFilters > 1 {
                throw ValidationError("Use only one of --structure-hints-only, --column-only, --migrate-columns-only, or --aliases-only")
            }
            let scanner = WorkspaceScanner(config: config)
            let projects = try await scanner.scanProjects()
            let inventory = try OmniFocusCLI.inventory(service: service, forgeDir: forgeDir, live: live)
            let ignore = OmniFocusAlignIgnoreStore.load(forgeDir: forgeDir)
            var plan = OmniFocusAlignment.alignPlan(
                projects: projects,
                inventory: inventory,
                config: config,
                preference: preference,
                ignore: ignore
            )
            if structureHintsOnly {
                let filtered = plan.proposals.filter {
                    $0.kind == .tagMatchingOfProject || $0.kind == .ensureForgeRootTag
                }
                plan = OmniFocusAlignPlan(generatedAt: plan.generatedAt, proposals: filtered, dryRun: plan.dryRun)
            }
            if columnOnly {
                let filtered = plan.proposals.filter {
                    $0.kind == .setForgeColumnFromFinder || $0.kind == .setFinderColumnFromOf
                }
                plan = OmniFocusAlignPlan(generatedAt: plan.generatedAt, proposals: filtered, dryRun: plan.dryRun)
            }
            if migrateColumnsOnly {
                let filtered = plan.proposals.filter { $0.kind == .migrateColumnTagRoot }
                plan = OmniFocusAlignPlan(generatedAt: plan.generatedAt, proposals: filtered, dryRun: plan.dryRun)
            }
            if aliasesOnly {
                let filtered = plan.proposals.filter { $0.kind == .ensureColumnAlias }
                plan = OmniFocusAlignPlan(generatedAt: plan.generatedAt, proposals: filtered, dryRun: plan.dryRun)
            }
            if let folderName = folder?.trimmingCharacters(in: .whitespacesAndNewlines), !folderName.isEmpty {
                let filtered = plan.proposals.filter { p in
                    if p.kind == .ensureForgeRootTag { return true }
                    return p.folderName == folderName
                }
                plan = OmniFocusAlignPlan(generatedAt: plan.generatedAt, proposals: filtered, dryRun: plan.dryRun)
                if !plan.proposals.contains(where: { $0.folderName == folderName }) {
                    throw ValidationError("No align proposals for folder '\(folderName)'. Check doctor / spelling.")
                }
            }

            if json && !apply {
                try OmniFocusCLI.encodeJSON(plan)
                return
            }

            if !apply {
                if json {
                    try OmniFocusCLI.encodeJSON(plan)
                } else {
                    OmniFocusCLI.printPlan(plan)
                }
                return
            }

            // Always print plan before applying.
            plan = OmniFocusAlignPlan(generatedAt: plan.generatedAt, proposals: plan.proposals, dryRun: false)
            OmniFocusCLI.printPlan(OmniFocusAlignPlan(
                generatedAt: plan.generatedAt,
                proposals: plan.proposals,
                dryRun: true
            ))
            if !yes {
                print()
                print("Type 'apply' to confirm, or anything else to abort:")
                let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line == "apply" else {
                    print("Aborted. No changes made.")
                    return
                }
            }

            let result = try OmniFocusPlanExecutor.executeAlign(
                plan: plan,
                apply: true,
                service: service,
                config: config,
                forgeDir: forgeDir
            )
            switch result {
            case .dryRun:
                break
            case .applied(let applied, let errors):
                print("Applied \(applied.count) proposal(s).")
                for e in errors {
                    print("Error: \(e)")
                }
                if errors.isEmpty {
                    _ = try? service.refreshSnapshot(forgeDir: forgeDir)
                }
            }
        }
    }

    struct Refresh: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "refresh",
            abstract: "Export OmniFocus inventory to the local snapshot cache; optionally pull columns onto Finder."
        )

        @Flag(name: .customLong("apply-finder"), help: "Like board Refresh: pull OF→Finder (and strip leftover OF kanban tags on updated folders). Does not push Finder columns onto OmniFocus.")
        var applyFinder = false

        mutating func run() async throws {
            let (config, forgeDir, service) = try OmniFocusCLI.loadContext()
            try service.requireEnabled()
            let inventory = try service.refreshSnapshot(forgeDir: forgeDir)
            print("Wrote \(OmniFocusSnapshotStore.cachePath(forgeDir: forgeDir))")
            print("\(inventory.tasks.count) linked task(s), \(inventory.linkTags.count) Forge tag(s).")

            if applyFinder {
                guard config.omnifocus.syncFromOmnifocus
                    || config.omnifocus.syncOnMove
                    || config.omnifocus.syncCompletedProjectToShipped else {
                    print("Skipped sync (omnifocus sync flags are all false).")
                    return
                }
                let scanner = WorkspaceScanner(config: config)
                let projects = try await scanner.scanProjects()
                // Same path as Forge.app board Refresh.
                let outcome = try OmniFocusMoveSync.syncBidirectionalOnRefresh(
                    config: config,
                    forgeDir: forgeDir,
                    projects: projects
                )
                if outcome.pulledFolders.isEmpty {
                    print("Finder columns: no OF→Finder updates.")
                } else {
                    print("Finder columns updated: \(outcome.pulledFolders.joined(separator: ", "))")
                }
                if outcome.pushedFolders > 0 {
                    print("OmniFocus kanban tags cleaned for \(outcome.pushedFolders) project(s).")
                }
                for e in outcome.errors {
                    print("Warning: \(e)")
                }
            }
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show OmniFocus config gate and snapshot freshness."
        )

        mutating func run() async throws {
            let (config, forgeDir, service) = try OmniFocusCLI.loadContext()
            let of = config.omnifocus
            print("omnifocus.enabled: \(of.enabled)")
            print("omnifocus.link_tag_root: \(of.linkTagRoot)")
            print("omnifocus.column_tag_root: \(of.columnTagRoot)")
            print("omnifocus.sync_on_move: \(of.syncOnMove)")
            print("omnifocus.sync_from_omnifocus: \(of.syncFromOmnifocus)")
            print("omnifocus.allow_sync_with_drift: \(of.allowSyncWithDrift)")
            if let payload = try OmniFocusSnapshotStore.read(forgeDir: forgeDir) {
                let age = Date().timeIntervalSince(payload.inventory.generatedAt)
                print("snapshot: \(OmniFocusSnapshotStore.cachePath(forgeDir: forgeDir))")
                print("snapshot_age_seconds: \(Int(age))")
                print("linked_tasks: \(payload.inventory.tasks.count)")
            } else {
                print("snapshot: (none)")
            }
            if of.enabled {
                let scanner = WorkspaceScanner(config: config)
                let projects = try await scanner.scanProjects()
                if let inv = try service.loadEligibleSnapshot(forgeDir: forgeDir)
                    ?? (try? service.fetchInventory()) {
                    let report = OmniFocusAlignment.doctor(projects: projects, inventory: inv, config: config)
                    print("doctor: \(report.isClean ? "clean" : "drift")")
                }
            }
        }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show linked OmniFocus tasks for a Forge project folder."
        )

        @Argument(help: "Project directory name or unique substring.")
        var project: String

        @Flag(name: .long, help: "Force a live OmniFocus export instead of the snapshot cache.")
        var live = false

        mutating func run() async throws {
            let (config, forgeDir, service) = try OmniFocusCLI.loadContext()
            try service.requireEnabled()
            let scanner = WorkspaceScanner(config: config)
            let projects = try await scanner.scanProjects()
            let lower = project.lowercased()
            let matches = projects.filter {
                $0.name.lowercased() == lower || $0.name.lowercased().contains(lower)
            }
            guard matches.count == 1, let matched = matches.first else {
                throw ValidationError("No unique project matching '\(project)'.")
            }
            let inventory = try OmniFocusCLI.inventory(service: service, forgeDir: forgeDir, live: live)
            let tasks = inventory.tasks.filter { $0.projectFolderName == matched.name }
            print("\(matched.name) — \(tasks.count) linked active task(s)")
            for t in tasks {
                let due = t.due.map { " due \($0)" } ?? ""
                let col = t.forgeColumn.map { " [\($0)]" } ?? ""
                let alias = t.columnAliasTag.map { " alias \($0)" } ?? ""
                print("  • \(t.title)\(col)\(alias)\(due)")
            }
        }
    }

    struct Proposals: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "proposals",
            abstract: "List ongoing OF→Forge sync proposals (read-only; same as align dry-run for drift/idle)."
        )

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        mutating func run() async throws {
            let (config, forgeDir, service) = try OmniFocusCLI.loadContext()
            try service.requireEnabled()
            let scanner = WorkspaceScanner(config: config)
            let projects = try await scanner.scanProjects()
            let inventory = try OmniFocusCLI.inventory(service: service, forgeDir: forgeDir, live: false)
            let ignore = OmniFocusAlignIgnoreStore.load(forgeDir: forgeDir)
            let plan = OmniFocusAlignment.alignPlan(
                projects: projects,
                inventory: inventory,
                config: config,
                preference: .finder,
                ignore: ignore
            )
            // Add idle/overdue proposals
            var extras = plan.proposals
            let now = Date()
            if config.omnifocus.proposeUrgentOnOverdue {
                for project in projects {
                    let tasks = inventory.tasks.filter { $0.projectFolderName == project.name }
                    let overdue = tasks.contains { t in
                        guard let due = t.due else { return false }
                        return due < now
                    }
                    if overdue, !KanbanRadar.isUrgent(metaTags: project.metaTags) {
                        extras.append(OmniFocusAlignProposal(
                            kind: .setFinderColumnFromOf,
                            folderName: project.name,
                            path: project.path,
                            summary: "Propose: add URGENT meta tag to \(project.name) (overdue OF task)"
                        ))
                    }
                }
            }
            let out = OmniFocusAlignPlan(generatedAt: now, proposals: extras, dryRun: true)
            if json {
                try OmniFocusCLI.encodeJSON(out)
            } else {
                OmniFocusCLI.printPlan(out)
            }
        }
    }

    struct Apply: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "apply",
            abstract: "Apply align proposals. Defaults to dry-run; pass --apply to write."
        )

        @Flag(name: .long, help: "Perform writes. Default is dry-run.")
        var apply = false

        @Flag(name: .long, help: "With --apply, skip confirmation.")
        var yes = false

        @Option(name: .long, help: "finder or omnifocus for column drift.")
        var prefer: String = "finder"

        mutating func run() async throws {
            var align = Align()
            align.apply = apply
            align.yes = yes
            align.prefer = prefer
            align.live = true
            try await align.run()
        }
    }
}
