import ArgumentParser
import Foundation
import ForgeCore

struct FsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fs",
        abstract: "Portable kanban sidecar ↔ local folder tags (nexus).",
        subcommands: [FsDoctorCommand.self, FsSyncCommand.self, FsMigrateCommand.self]
    )
}

// MARK: - doctor

struct FsDoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Report drift between .forge/kanban.toml and local tags."
    )

    @Flag(name: .long, help: "Emit JSON.")
    var json = false

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let tagStore = PlatformTagStore.makeDefault()
        let projects = try await WorkspaceScanner(config: config, tagStore: tagStore).scanProjects()
        let drifts = try KanbanFsSync.doctor(projects: projects, config: config, tagStore: tagStore)
        if json {
            let payload = drifts.map {
                [
                    "project": $0.project,
                    "path": $0.path,
                    "sidecar_column": $0.sidecarColumn as Any,
                    "tag_column": $0.tagColumn as Any,
                    "issue": $0.issue,
                ] as [String: Any]
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else if drifts.isEmpty {
            print("No sidecar ↔ tag drift.")
        } else {
            for d in drifts {
                print("\(d.project): \(d.issue) sidecar=\(d.sidecarColumn ?? "—") tags=\(d.tagColumn ?? "—")")
            }
        }
    }
}

// MARK: - sync

struct FsSyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Reconcile sidecar and local tags (dry-run unless --apply)."
    )

    @Option(name: .long, help: "Prefer sidecar (default) or finder/local tags when they disagree.")
    var prefer: String = "sidecar"

    @Flag(name: .long, help: "Write changes.")
    var apply = false

    @Flag(name: .long, help: "Emit JSON.")
    var json = false

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let preferMode: KanbanFsSync.Prefer
        switch prefer.lowercased() {
        case "sidecar": preferMode = .sidecar
        case "finder", "tags", "local": preferMode = .finder
        default:
            try ForgeJSONError.throwDomainFailure(
                "Unknown --prefer '\(prefer)' (use sidecar or finder).",
                command: "fs sync",
                json: json
            )
        }
        let tagStore = PlatformTagStore.makeDefault()
        let projects = try await WorkspaceScanner(config: config, tagStore: tagStore).scanProjects()
        let changes = try KanbanFsSync.sync(
            projects: projects,
            config: config,
            prefer: preferMode,
            apply: apply,
            tagStore: tagStore
        )
        emitChanges(changes, apply: apply, json: json, command: "fs sync")
    }
}

// MARK: - migrate

struct FsMigrateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Bootstrap .forge/kanban.toml from local tags (dry-run unless --apply)."
    )

    @Flag(name: .long, help: "Write sidecars.")
    var apply = false

    @Flag(name: .long, help: "Overwrite existing sidecars.")
    var overwrite = false

    @Flag(name: .long, help: "Emit JSON.")
    var json = false

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let tagStore = PlatformTagStore.makeDefault()
        let projects = try await WorkspaceScanner(config: config, tagStore: tagStore).scanProjects()
        let changes = try KanbanFsSync.migrate(
            projects: projects,
            config: config,
            apply: apply,
            tagStore: tagStore,
            overwrite: overwrite
        )
        emitChanges(changes, apply: apply, json: json, command: "fs migrate")
    }
}

private func emitChanges(
    _ changes: [KanbanFsSync.Change],
    apply: Bool,
    json: Bool,
    command: String
) {
    if json {
        let payload: [String: Any] = [
            "command": command,
            "applied": apply,
            "changes": changes.map {
                ["project": $0.project, "path": $0.path, "action": $0.action, "detail": $0.detail]
            },
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            print(s)
        }
    } else {
        let mode = apply ? "applied" : "dry-run"
        print("\(command) (\(mode)): \(changes.count) change(s)")
        for c in changes {
            print("  \(c.project): \(c.action) — \(c.detail)")
        }
    }
}
