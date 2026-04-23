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

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError("Tag must not be empty.")
        }

        if config.column(forTag: trimmed) != nil {
            throw ValidationError(
                "Workflow column tags are set with `forge move <project> <ColumnName>`, not `forge project-tag`."
            )
        }

        if !force {
            switch ProjectFolderTagPolicy.validationResult(tag: trimmed, config: config) {
            case .workflowColumn:
                throw ValidationError(
                    "That tag is a kanban column (workflow) tag. Use `forge move <project> <ColumnName>` to change columns."
                )
            case .unrecognized:
                throw ValidationError(
                    "Tag must be listed under `board.meta_tags` in config.yaml, or be a #Person assignee tag (e.g. #Alice). Use --force to add other non-column tags."
                )
            case .allowed:
                break
            }
        }

        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()
        guard let matched = findProject(named: project, in: projects) else {
            throw ValidationError(
                "No project matching '\(project)'. Use 'forge board --list' to see all projects."
            )
        }

        let tagStore = FinderTagStore()
        try tagStore.addTag(trimmed, at: matched.path)
        print("Added tag \(trimmed) on \(matched.name)")
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

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError("Tag must not be empty.")
        }

        if config.column(forTag: trimmed) != nil {
            throw ValidationError(
                "Workflow column tags are changed with `forge move`, not `forge project-tag remove`."
            )
        }

        if !force {
            switch ProjectFolderTagPolicy.validationResult(tag: trimmed, config: config) {
            case .workflowColumn:
                throw ValidationError(
                    "That tag is a kanban column (workflow) tag. Use `forge move` to change columns instead of removing the workflow tag here."
                )
            case .unrecognized:
                throw ValidationError(
                    "Tag must be a configured meta tag or a #Person assignee tag. Use --force to remove other non-column tags."
                )
            case .allowed:
                break
            }
        }

        let scanner = WorkspaceScanner(config: config)
        let projects = try await scanner.scanProjects()
        guard let matched = findProject(named: project, in: projects) else {
            throw ValidationError(
                "No project matching '\(project)'. Use 'forge board --list' to see all projects."
            )
        }

        let tagStore = FinderTagStore()
        try tagStore.removeTag(trimmed, at: matched.path)
        print("Removed tag \(trimmed) from \(matched.name)")
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
        guard let matched = findProject(named: project, in: projects) else {
            throw ValidationError(
                "No project matching '\(project)'. Use 'forge board --list' to see all projects."
            )
        }

        let tagStore = FinderTagStore()
        let tags = try tagStore.readTags(at: matched.path)

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

// MARK: - Shared lookup (same behaviour as MoveCommand)

private func findProject(named query: String, in projects: [Project]) -> Project? {
    let lower = query.lowercased()
    if let exact = projects.first(where: { $0.name.lowercased() == lower }) {
        return exact
    }
    let matches = projects.filter { $0.name.lowercased().contains(lower) }
    if matches.count == 1 {
        return matches.first
    }
    if matches.count > 1 {
        print("Ambiguous match for '\(query)':")
        for m in matches { print("  • \(m.name)") }
    }
    return nil
}
