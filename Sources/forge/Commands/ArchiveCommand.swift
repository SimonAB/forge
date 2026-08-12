import ArgumentParser
import Foundation
import ForgeCore

struct ArchiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Apply due Completed meta tags on Shipped projects after the configured delay."
    )

    @Flag(name: .long, help: "Show what would be tagged (and countdowns) without writing Finder tags.")
    var dryRun = false

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        guard let completedTag = KanbanArchivePolicy.completedTag(in: config.board) else {
            throw ValidationError(
                "No Completed meta tag in board.meta_tags. Add e.g. \"Completed ✔️\" to enable delayed completion tagging."
            )
        }

        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()
        let shipped = projects.filter { $0.column == "Shipped" }
        let payload = try ShippedArchiveStore.read(forgeDir: forgeDir)
        let now = Date()

        if dryRun {
            print("Dry run — delay \(config.board.resolvedArchiveAfterShippedDays) day(s); tag \(completedTag)")
            let legacy = try KanbanArchivePolicy.migrateLegacyArchivedTags(
                projects: projects,
                config: config,
                dryRun: true
            )
            if !legacy.isEmpty {
                print("Would migrate legacy Archived → \(completedTag): \(legacy.joined(separator: ", "))")
            }
            if shipped.isEmpty {
                print("No Shipped projects.")
                return
            }
            for project in shipped.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                let shippedAt = payload.shippedAt[project.name]
                let status = KanbanArchivePolicy.status(
                    project: project,
                    config: config,
                    shippedAt: shippedAt,
                    now: now
                )
                let label: String
                switch status {
                case .completed:
                    label = "already completed"
                case .readyToComplete:
                    label = "would tag"
                case .countdown(let days):
                    label = "complete in \(days)d"
                case .notApplicable:
                    label = "n/a"
                }
                print("  \(project.name): \(label)")
            }
            return
        }

        let result = try KanbanArchivePolicy.applyDueArchives(
            projects: projects,
            config: config,
            forgeDir: forgeDir,
            now: now
        )

        if !result.migratedFromLegacyArchived.isEmpty {
            print("Migrated legacy Archived → \(completedTag): \(result.migratedFromLegacyArchived.joined(separator: ", "))")
        }
        if result.completedFolders.isEmpty {
            print("No projects due for \(completedTag).")
        } else {
            print("Completed (\(completedTag)): \(result.completedFolders.joined(separator: ", "))")
        }
        if !result.recordedShipDates.isEmpty {
            print("Recorded ship dates for: \(result.recordedShipDates.joined(separator: ", "))")
        }
        for error in result.errors {
            print("Error: \(error)")
        }
        if !result.errors.isEmpty {
            throw ExitCode(1)
        }
    }
}
