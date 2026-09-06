import ArgumentParser
import Foundation
import ForgeCore

struct ProjectTagCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project-tag",
        abstract: "Add, remove, or list meta and assignee Finder tags on a project folder.",
        subcommands: [ProjectTagAddCommand.self, ProjectTagRemoveCommand.self, ProjectTagListCommand.self]
    )
}

// MARK: - add

struct ProjectTagAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a meta tag or #Person assignee tag to a project directory."
    )

    @Argument(help: "Project directory name (or a unique substring).")
    var project: String

    @Argument(help: "Finder tag string (must be a configured meta tag or #Name assignee, unless --force).")
    var tag: String

    @Flag(name: .long, help: "Allow tags not in board.meta_tags and not #Person (e.g. legacy labels). Kanban column tags are always rejected; use `forge move`.")
    var force = false

    @Flag(name: .long, help: "Emit JSON result.")
    var json = false

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try ForgeJSONError.throwDomainFailure(
                "Tag must not be empty.", command: "project-tag add", json: json
            )
        }

        if config.column(forTag: trimmed) != nil {
            try ForgeJSONError.throwDomainFailure(
                "Workflow column tags are set with `forge move <project> <ColumnName>`, not `forge project-tag`.",
                command: "project-tag add",
                json: json
            )
        }

        if !force {
            switch ProjectFolderTagPolicy.validationResult(tag: trimmed, config: config) {
            case .workflowColumn:
                try ForgeJSONError.throwDomainFailure(
                    "That tag is a kanban column (workflow) tag. Use `forge move <project> <ColumnName>` to change columns.",
                    command: "project-tag add",
                    json: json
                )
            case .unrecognized:
                try ForgeJSONError.throwDomainFailure(
                    "Tag must be listed under `board.meta_tags` in config.yaml, or be a #Person assignee tag (e.g. #Alice). Use --force to add other non-column tags.",
                    command: "project-tag add",
                    json: json
                )
            case .allowed:
                break
            }
        }

        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()
        let matched = try resolveProject(
            named: project, in: projects, command: "project-tag add", json: json
        )

        let tagStore = PlatformTagStore.makeDefault()
        try tagStore.addTag(trimmed, at: matched.path)
        try? KanbanNexus.syncSidecarFromTags(
            path: matched.path,
            config: config,
            tagStore: tagStore,
            source: KanbanNexus.Source.projectTag
        )

        var meta = matched.metaTags
        if !meta.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            meta.append(trimmed)
        }
        let updated = Project(
            name: matched.name,
            path: matched.path,
            tags: matched.tags + [trimmed],
            workflowTag: matched.workflowTag,
            column: matched.column,
            metaTags: meta,
            assignees: matched.assignees
        )

        if json {
            emitTagChangeJSON(action: "added", tag: trimmed, project: matched.name, path: matched.path)
        } else {
            print("Added tag \(trimmed) on \(matched.name)")
        }

        await syncRemindersUrgentPriority(config: config, project: updated, quiet: json)
    }
}

// MARK: - remove

struct ProjectTagRemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a meta tag or #Person assignee tag from a project directory."
    )

    @Argument(help: "Project directory name (or a unique substring).")
    var project: String

    @Argument(help: "Finder tag string to remove (must pass the exact tag as shown in Finder).")
    var tag: String

    @Flag(name: .long, help: "Remove a tag that is not in meta_tags / not #Person. Kanban column tags cannot be removed here; use `forge move`.")
    var force = false

    @Flag(name: .long, help: "Emit JSON result.")
    var json = false

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try ForgeJSONError.throwDomainFailure(
                "Tag must not be empty.", command: "project-tag remove", json: json
            )
        }

        if config.column(forTag: trimmed) != nil {
            try ForgeJSONError.throwDomainFailure(
                "Workflow column tags are changed with `forge move`, not `forge project-tag remove`.",
                command: "project-tag remove",
                json: json
            )
        }

        if !force {
            switch ProjectFolderTagPolicy.validationResult(tag: trimmed, config: config) {
            case .workflowColumn:
                try ForgeJSONError.throwDomainFailure(
                    "That tag is a kanban column (workflow) tag. Use `forge move` to change columns instead of removing the workflow tag here.",
                    command: "project-tag remove",
                    json: json
                )
            case .unrecognized:
                try ForgeJSONError.throwDomainFailure(
                    "Tag must be a configured meta tag or a #Person assignee tag. Use --force to remove other non-column tags.",
                    command: "project-tag remove",
                    json: json
                )
            case .allowed:
                break
            }
        }

        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()
        let matched = try resolveProject(
            named: project, in: projects, command: "project-tag remove", json: json
        )

        let tagStore = PlatformTagStore.makeDefault()
        try tagStore.removeTag(trimmed, at: matched.path)
        try? KanbanNexus.syncSidecarFromTags(
            path: matched.path,
            config: config,
            tagStore: tagStore,
            source: KanbanNexus.Source.projectTag
        )

        let meta = matched.metaTags.filter {
            $0.caseInsensitiveCompare(trimmed) != .orderedSame
        }
        let updated = Project(
            name: matched.name,
            path: matched.path,
            tags: matched.tags.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame },
            workflowTag: matched.workflowTag,
            column: matched.column,
            metaTags: meta,
            assignees: matched.assignees
        )

        if json {
            emitTagChangeJSON(action: "removed", tag: trimmed, project: matched.name, path: matched.path)
        } else {
            print("Removed tag \(trimmed) from \(matched.name)")
        }

        await syncRemindersUrgentPriority(config: config, project: updated, quiet: json)
    }
}

// MARK: - list

struct ProjectTagListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List Finder tags on a project directory (with kind: meta, assignee, column, other)."
    )

    @Argument(help: "Project directory name (or a unique substring).")
    var project: String

    @Flag(name: .long, help: "Emit JSON: `{ \"project\", \"path\", \"tags\": [{ \"name\", \"kind\" }] }`.")
    var json = false

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()
        let matched = try resolveProject(
            named: project, in: projects, command: "project-tag list", json: json
        )

        let tagStore = PlatformTagStore.makeDefault()
        let tags = syncTags(from: tagStore, at: matched.path)

        if json {
            let rows: [ProjectTagListRow] = tags.map { name in
                ProjectTagListRow(name: name, kind: tagKind(name: name, config: config))
            }
            let payload = ProjectTagListPayload(project: matched.name, path: matched.path, tags: rows)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            if let s = String(data: data, encoding: .utf8) {
                print(s)
            }
            return
        }

        if tags.isEmpty {
            print("\(matched.name): (no Finder tags)")
            return
        }
        print("\(matched.name) — \(matched.path)\n")
        for t in tags.sorted() {
            let k = tagKind(name: t, config: config)
            print("  • \(t)  (\(k))")
        }
    }

    private func tagKind(name: String, config: ForgeConfig) -> String {
        if config.column(forTag: name) != nil { return "column" }
        if config.board.metaTags.contains(name) { return "meta" }
        if AssigneeTag.normalisedIdentifier(fromRawTag: name) != nil { return "assignee" }
        if let pt = config.projectTag, pt == name { return "project_scope" }
        return "other"
    }
}

private struct ProjectTagListPayload: Encodable {
    let project: String
    let path: String
    let tags: [ProjectTagListRow]
}

private struct ProjectTagListRow: Encodable {
    let name: String
    let kind: String
}

// MARK: - Shared helpers

private func resolveProject(
    named query: String,
    in projects: [Project],
    command: String,
    json: Bool
) throws -> Project {
    switch matchProject(named: query, in: projects) {
    case .found(let project):
        return project
    case .none:
        try ForgeJSONError.throwDomainFailure(
            "No project matching '\(query)'. Use 'forge board --list' to see all projects.",
            command: command,
            json: json
        )
    case .ambiguous(let candidates):
        if !json {
            printAmbiguousProjectMatch(query: query, candidates: candidates)
        }
        try ForgeJSONError.throwDomainFailure(
            "Ambiguous project '\(query)'. Refine the name.",
            command: command,
            json: json,
            candidates: candidates
        )
    }
}

private func syncRemindersUrgentPriority(config: ForgeConfig, project: Project, quiet: Bool) async {
    guard config.reminders.enabled else { return }
    let forgeDir = ConfigLoader.forgeDirectory(for: config)
    do {
        guard let inv = try RemindersService(config: config).loadEligibleSnapshot(forgeDir: forgeDir) else {
            if !quiet {
                print("Reminders sentinel priority skipped: no eligible snapshot (run forge reminders refresh).")
            }
            return
        }
        let outcome = await RemindersMoveSync.paintSentinelPriority(
            config: config,
            project: project,
            inventory: inv,
            writer: RemindersWriter()
        )
        guard !quiet else { return }
        switch outcome {
        case .disabled:
            break
        case .skipped(let reason):
            print("Reminders sentinel priority skipped: \(reason)")
        case .synced(let listTitle, let label):
            print("Reminders sentinel priority: \(label) on \(listTitle).")
        }
    } catch {
        if !quiet {
            print("Reminders sentinel priority skipped: \(error.localizedDescription)")
        }
    }
}

private func emitTagChangeJSON(action: String, tag: String, project: String, path: String) {
    let payload = ProjectTagChangePayload(action: action, tag: tag, project: project, path: path)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(payload),
       let s = String(data: data, encoding: .utf8) {
        print(s)
    }
}

private struct ProjectTagChangePayload: Encodable {
    let action: String
    let tag: String
    let project: String
    let path: String
}
