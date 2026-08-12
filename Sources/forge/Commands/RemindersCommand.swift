import ArgumentParser
import Foundation
import ForgeCore

/// Apple Reminders bridge: list, status, show, doctor, align (optional).
struct RemindersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "Apple Reminders linked to Forge projects (optional).",
        subcommands: [
            List.self, Status.self, Show.self, Refresh.self, Doctor.self, Align.self,
            PaintColours.self, PaintPriorities.self,
        ],
        defaultSubcommand: List.self
    )
}

// MARK: - Shared helpers

private enum RemindersCLI {
    static func loadContext() throws -> (ForgeConfig, String) {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        return (config, forgeDir)
    }

    static func projectNames(_ config: ForgeConfig) async throws -> [String] {
        let scanner = WorkspaceScanner(config: config)
        return try await scanner.scanProjects().map(\.name)
    }

    static func projects(_ config: ForgeConfig) async throws -> [Project] {
        let scanner = WorkspaceScanner(config: config)
        return try await scanner.scanProjects()
    }

    static func resolveProjectName(_ query: String, in names: [String]) throws -> String {
        switch RemindersMatching.resolveProjectName(query, in: names) {
        case .ok(let name):
            return name
        case .ambiguous(let matches):
            throw ValidationError(
                "Ambiguous match for '\(query)': \(matches.joined(separator: ", "))."
            )
        case .none:
            throw ValidationError(
                "No project matching '\(query)'. Use 'forge board --list' to see all projects."
            )
        }
    }

    static func encodeJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        if let s = String(data: data, encoding: .utf8) { print(s) }
    }

    static func printInventory(
        _ inventory: RemindersInventory,
        source: RemindersInventoryResolution.Source,
        listFilter: String?,
        projectFilter: String?
    ) {
        print(
            RemindersTextFormatter.inventoryText(
                inventory,
                source: source,
                listFilter: listFilter,
                projectFilter: projectFilter
            )
        )
    }

    static func printDoctor(_ report: RemindersDoctorReport) {
        print("Reminders doctor — \(report.isClean ? "CLEAN" : "DRIFT")")
        print(String(repeating: "─", count: 48))
        if report.items.isEmpty {
            print("No findings.")
            return
        }
        for item in report.items where item.bucket != .aligned {
            let target = item.folderName ?? item.listTitle ?? "—"
            print("[\(item.bucket.rawValue)] \(target): \(item.detail)")
        }
        let forgeOnly = report.items.filter { $0.bucket == .forgeOnly }.count
        if forgeOnly > 0 {
            print()
            print("\(forgeOnly) folder(s) have no Reminders list. Preview: forge reminders align. Create: forge reminders align --apply.")
        }
        let shipped = report.items.filter {
            $0.bucket == .hygiene && $0.detail.localizedCaseInsensitiveContains("Shipped")
        }
        if !shipped.isEmpty {
            print()
            print("\(shipped.count) list(s) look complete. Align proposes Finder Shipped (not applied automatically).")
        }
    }

    static func printPlan(_ plan: RemindersAlignPlan) {
        let mode = plan.dryRun ? "DRY-RUN (no changes)" : "APPLY"
        print("Reminders align plan — \(mode)")
        print(String(repeating: "─", count: 48))
        if plan.proposals.isEmpty {
            print("No proposals.")
            return
        }
        for (i, p) in plan.proposals.enumerated() {
            print("\(i + 1). [\(p.kind.rawValue)] \(p.summary)")
        }
        if plan.dryRun {
            print()
            print("Re-run with --apply to perform these changes.")
        }
    }
}

extension RemindersCommand {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List reminders grouped by matched project and unmatched lists."
        )

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        @Option(name: .long, help: "Filter by Reminders list title.")
        var list: String?

        @Option(name: .long, help: "Filter by Forge project folder (name or unique substring).")
        var project: String?

        @Flag(name: .long, help: "Include completed reminders.")
        var completed = false

        @Flag(name: .long, help: "Force a live EventKit fetch (ignore snapshot).")
        var live = false

        mutating func run() async throws {
            let (config, forgeDir) = try RemindersCLI.loadContext()
            try RemindersService(config: config).requireEnabled()
            let names = try await RemindersCLI.projectNames(config)
            var projectFilter: String?
            if let project {
                projectFilter = try RemindersCLI.resolveProjectName(project, in: names)
            }
            let includeCompleted = completed || config.reminders.includeCompleted
            let resolved = try await RemindersInventoryResolution.resolve(
                forgeDir: forgeDir,
                config: config,
                projectNames: names,
                live: live,
                includeCompleted: includeCompleted
            )
            if json {
                try RemindersCLI.encodeJSON(resolved.inventory)
                return
            }
            RemindersCLI.printInventory(
                resolved.inventory,
                source: resolved.source,
                listFilter: list,
                projectFilter: projectFilter
            )
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show Reminders config gate and snapshot freshness."
        )

        mutating func run() async throws {
            let (config, forgeDir) = try RemindersCLI.loadContext()
            let rem = config.reminders
            print("reminders.enabled: \(rem.enabled)")
            print("reminders.list: \(rem.list)")
            print("reminders.include_completed: \(rem.includeCompleted)")
            print("reminders.snapshot_max_age_seconds: \(Int(rem.snapshotMaxAgeSeconds))")
            print("reminders.sync_on_move: \(rem.syncOnMove)")
            print("reminders.sync_from_reminders: \(rem.syncFromReminders)")
            print("reminders.sentinel_prefix: \(rem.sentinelPrefix)")
            if let source = rem.source { print("reminders.source: \(source)") }
            if config.omnifocus.enabled, rem.enabled {
                print("warning: OmniFocus and Reminders are both enabled; Refresh applies OmniFocus column pull first.")
            }
            print(RemindersSnapshotStore.statusSummary(forgeDir: forgeDir))
            if let payload = try RemindersSnapshotStore.read(forgeDir: forgeDir) {
                let age = Date().timeIntervalSince(payload.inventory.generatedAt)
                print("snapshot_path: \(RemindersSnapshotStore.cachePath(forgeDir: forgeDir))")
                print("snapshot_age_seconds: \(Int(age))")
                print("lists: \(payload.inventory.lists.count)")
                print("reminders: \(payload.inventory.reminders.count)")
                let incomplete = payload.inventory.reminders.filter { !$0.isCompleted }.count
                print("incomplete: \(incomplete)")
            }
            if !rem.enabled {
                print("Set reminders.enabled: true in config.yaml, or enable it in Forge → Preferences → Reminders.")
            }
        }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show reminders for a Forge project folder."
        )

        @Argument(help: "Project directory name (or a unique substring).")
        var project: String

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        @Flag(name: .long, help: "Include completed reminders.")
        var completed = false

        @Flag(name: .long, help: "Force a live EventKit fetch (ignore snapshot).")
        var live = false

        mutating func run() async throws {
            let (config, forgeDir) = try RemindersCLI.loadContext()
            try RemindersService(config: config).requireEnabled()
            let names = try await RemindersCLI.projectNames(config)
            let resolvedName = try RemindersCLI.resolveProjectName(project, in: names)
            let includeCompleted = completed || config.reminders.includeCompleted
            let resolved = try await RemindersInventoryResolution.resolve(
                forgeDir: forgeDir,
                config: config,
                projectNames: names,
                live: live,
                includeCompleted: includeCompleted
            )
            if json {
                let filtered = resolved.inventory.reminders.filter {
                    $0.matchedProject?.lowercased() == resolvedName.lowercased()
                }
                try RemindersCLI.encodeJSON(filtered)
                return
            }
            RemindersCLI.printInventory(
                resolved.inventory,
                source: resolved.source,
                listFilter: nil,
                projectFilter: resolvedName
            )
        }
    }

    struct Refresh: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "refresh",
            abstract: "Fetch Reminders, write the snapshot, and paint list colours / URGENT priority (does not create lists)."
        )

        @Flag(
            name: .customLong("apply-finder"),
            help: "Pull sentinel column onto Finder (single-column steps only). Requires sync_from_reminders."
        )
        var applyFinder = false

        mutating func run() async throws {
            let (config, forgeDir) = try RemindersCLI.loadContext()
            let service = RemindersService(config: config)
            try service.requireEnabled()
            let projects = try await RemindersCLI.projects(config)
            let names = projects.map(\.name)
            let inventory = try await service.refreshSnapshot(
                forgeDir: forgeDir,
                projectNames: names,
                writer: "forge"
            )
            print("Wrote \(RemindersSnapshotStore.cachePath(forgeDir: forgeDir))")
            print(RemindersSnapshotStore.statusSummary(forgeDir: forgeDir))
            print("\(inventory.lists.count) list(s), \(inventory.reminders.count) reminder(s).")

            let report = RemindersAlignment.doctor(
                projects: projects,
                inventory: inventory,
                config: config
            )
            let forgeOnly = report.items.filter { $0.bucket == .forgeOnly }.count
            if forgeOnly == 0 {
                print("Reminders lists: none missing.")
            } else {
                print("\(forgeOnly) folder(s) have no Reminders list. Preview: forge reminders align. Create: forge reminders align --apply.")
            }

            if applyFinder, !config.reminders.syncFromReminders {
                throw ValidationError(
                    "reminders.sync_from_reminders is false. Enable it in Preferences → Reminders or config.yaml."
                )
            }

            let tagStore = FinderTagStore()
            let outcome = await RemindersMoveSync.applyRefreshAppearance(
                config: config,
                projects: projects,
                inventory: inventory,
                writer: RemindersWriter(),
                pullSentinels: applyFinder,
                setColumn: { project, column in
                    try OmniFocusMoveSync.setFinderWorkflowColumn(
                        path: project.path,
                        column: column,
                        config: config,
                        tagStore: tagStore,
                        forgeDir: forgeDir,
                        folderName: project.name,
                        previousColumn: project.column
                    )
                }
            )
            if outcome.paintedColours.isEmpty {
                print("List colours: none updated.")
            } else {
                print("List colours: \(outcome.paintedColours.count).")
                for line in outcome.paintedColours {
                    print("  \(line)")
                }
            }
            if outcome.paintedPriorities.isEmpty {
                print("Sentinel priorities: none updated.")
            } else {
                print("Sentinel priorities: \(outcome.paintedPriorities.count).")
                for line in outcome.paintedPriorities {
                    print("  \(line)")
                }
            }
            if applyFinder {
                if outcome.updatedFolders.isEmpty, outcome.errors.isEmpty {
                    print("Finder: no sentinel column updates.")
                } else {
                    if !outcome.updatedFolders.isEmpty {
                        print("Finder updated: \(outcome.updatedFolders.joined(separator: ", ")).")
                    }
                    for err in outcome.errors {
                        print("Finder skip: \(err)")
                    }
                }
            }
        }
    }

    struct Doctor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "doctor",
            abstract: "Compare Forge folders with Reminders lists (read-only)."
        )

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        @Flag(name: .long, help: "Force a live EventKit fetch (ignore snapshot).")
        var live = false

        mutating func run() async throws {
            let (config, forgeDir) = try RemindersCLI.loadContext()
            try RemindersService(config: config).requireEnabled()
            let projects = try await RemindersCLI.projects(config)
            let resolved = try await RemindersInventoryResolution.resolve(
                forgeDir: forgeDir,
                config: config,
                projectNames: projects.map(\.name),
                live: live,
                includeCompleted: true
            )
            let report = RemindersAlignment.doctor(
                projects: projects,
                inventory: resolved.inventory,
                config: config
            )
            if json {
                try RemindersCLI.encodeJSON(report)
                return
            }
            RemindersCLI.printDoctor(report)
        }
    }

    struct Align: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "align",
            abstract: "Propose creating missing Reminders lists (dry-run by default)."
        )

        @Flag(name: .long, help: "Emit JSON.")
        var json = false

        @Flag(name: .long, help: "Force a live EventKit fetch before planning.")
        var live = false

        @Flag(name: .long, help: "Apply the plan (creates lists / sentinels).")
        var apply = false

        @Flag(name: .long, help: "Skip the interactive confirmation when using --apply.")
        var yes = false

        mutating func run() async throws {
            let (config, forgeDir) = try RemindersCLI.loadContext()
            let service = RemindersService(config: config)
            try service.requireEnabled()
            let projects = try await RemindersCLI.projects(config)
            let resolved = try await RemindersInventoryResolution.resolve(
                forgeDir: forgeDir,
                config: config,
                projectNames: projects.map(\.name),
                live: live,
                includeCompleted: true
            )
            var plan = RemindersAlignment.alignPlan(
                projects: projects,
                inventory: resolved.inventory,
                config: config,
                dryRun: !apply
            )

            if json && !apply {
                try RemindersCLI.encodeJSON(plan)
                return
            }

            if !apply {
                if json {
                    try RemindersCLI.encodeJSON(plan)
                } else {
                    RemindersCLI.printPlan(plan)
                }
                return
            }

            plan = RemindersAlignPlan(
                generatedAt: plan.generatedAt,
                proposals: plan.proposals,
                dryRun: false
            )
            RemindersCLI.printPlan(RemindersAlignPlan(
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

            let result = try await service.apply(
                plan: plan,
                writer: RemindersWriter(),
                projects: projects
            )
            print("Created \(result.createdLists.count) list(s), wrote \(result.sentinelsWritten) sentinel(s).")
            for skip in result.skipped {
                print("Skipped: \(skip)")
            }
            _ = try await service.refreshSnapshot(
                forgeDir: forgeDir,
                projectNames: projects.map(\.name),
                writer: "forge"
            )
            print("Snapshot refreshed.")
        }
    }

    struct PaintColours: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "paint-colours",
            abstract: "Set each matched Reminders list colour from the Finder column (dry-run by default)."
        )

        @Flag(name: .long, help: "Force a live EventKit fetch before painting.")
        var live = false

        @Flag(name: .long, help: "Write list colours (otherwise print the plan only).")
        var apply = false

        @Flag(name: .long, help: "Skip the interactive confirmation when using --apply.")
        var yes = false

        mutating func run() async throws {
            let (config, forgeDir) = try RemindersCLI.loadContext()
            let service = RemindersService(config: config)
            try service.requireEnabled()
            let projects = try await RemindersCLI.projects(config)
            let resolved = try await RemindersInventoryResolution.resolve(
                forgeDir: forgeDir,
                config: config,
                projectNames: projects.map(\.name),
                live: live,
                includeCompleted: true
            )

            if !apply {
                let preview = await RemindersMoveSync.paintAllMatchedListColours(
                    config: config,
                    projects: projects,
                    inventory: resolved.inventory,
                    writer: PreviewColourMutator()
                )
                print("Reminders list colours — DRY-RUN (no changes)")
                print(String(repeating: "─", count: 48))
                print("Would paint \(preview.painted.count) list(s).")
                for line in preview.painted {
                    print("  \(line)")
                }
                for skip in preview.skipped {
                    print("Skip: \(skip)")
                }
                print()
                print("Re-run with --apply to write colours.")
                return
            }

            print("Reminders list colours — APPLY")
            print(String(repeating: "─", count: 48))
            if !yes {
                print("Type 'apply' to paint matched list colours, or anything else to abort:")
                let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line == "apply" else {
                    print("Aborted. No changes made.")
                    return
                }
            }

            let result = await RemindersMoveSync.paintAllMatchedListColours(
                config: config,
                projects: projects,
                inventory: resolved.inventory,
                writer: RemindersWriter()
            )
            print("Painted \(result.painted.count) list(s).")
            for line in result.painted {
                print("  \(line)")
            }
            for skip in result.skipped {
                print("Skip: \(skip)")
            }
        }
    }

    struct PaintPriorities: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "paint-priorities",
            abstract: "Set each matched sentinel’s priority from Finder URGENT (dry-run by default)."
        )

        @Flag(name: .long, help: "Force a live EventKit fetch before painting.")
        var live = false

        @Flag(name: .long, help: "Write sentinel priorities (otherwise print the plan only).")
        var apply = false

        @Flag(name: .long, help: "Skip the interactive confirmation when using --apply.")
        var yes = false

        mutating func run() async throws {
            let (config, forgeDir) = try RemindersCLI.loadContext()
            let service = RemindersService(config: config)
            try service.requireEnabled()
            let projects = try await RemindersCLI.projects(config)
            let resolved = try await RemindersInventoryResolution.resolve(
                forgeDir: forgeDir,
                config: config,
                projectNames: projects.map(\.name),
                live: live,
                includeCompleted: true
            )

            if !apply {
                let preview = await RemindersMoveSync.paintAllMatchedSentinelPriorities(
                    config: config,
                    projects: projects,
                    inventory: resolved.inventory,
                    writer: PreviewColourMutator()
                )
                print("Reminders sentinel priorities — DRY-RUN (no changes)")
                print(String(repeating: "─", count: 48))
                print("Would update \(preview.painted.count) sentinel(s).")
                for line in preview.painted {
                    print("  \(line)")
                }
                for skip in preview.skipped {
                    print("Skip: \(skip)")
                }
                print()
                print("Re-run with --apply to write priorities.")
                return
            }

            print("Reminders sentinel priorities — APPLY")
            print(String(repeating: "─", count: 48))
            if !yes {
                print("Type 'apply' to set sentinel priorities from Finder URGENT, or anything else to abort:")
                let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line == "apply" else {
                    print("Aborted. No changes made.")
                    return
                }
            }

            let result = await RemindersMoveSync.paintAllMatchedSentinelPriorities(
                config: config,
                projects: projects,
                inventory: resolved.inventory,
                writer: RemindersWriter()
            )
            print("Updated \(result.painted.count) sentinel(s).")
            for line in result.painted {
                print("  \(line)")
            }
            for skip in result.skipped {
                print("Skip: \(skip)")
            }
        }
    }
}

/// Records colour / priority updates without calling EventKit (dry-run preview).
private struct PreviewColourMutator: RemindersMutating {
    func createList(title: String, sourceTitle: String?, colourIndex: Int?) async throws -> String {
        "preview"
    }

    func saveSentinel(listId: String, column: String, prefix: String) async throws -> String {
        "preview"
    }

    func updateSentinel(reminderId: String, column: String, prefix: String) async throws {}

    func updateListColour(listId: String, colourIndex: Int) async throws {}

    func updateReminderPriority(reminderId: String, priority: Int) async throws {}
}
