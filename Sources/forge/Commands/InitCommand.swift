import ArgumentParser
import Foundation
import ForgeCore

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialise forge in a workspace directory."
    )

    @Option(name: .long, help: "Path to the workspace directory.")
    var workspace: String?

    mutating func run() throws {
        let workspacePath = resolveWorkspace()
        let forgeDir = (workspacePath as NSString).appendingPathComponent("Forge")
        let configPath = (forgeDir as NSString).appendingPathComponent("config.yaml")
        let fm = FileManager.default

        if fm.fileExists(atPath: configPath) {
            print("Forge already initialised at \(forgeDir)")
            print("Running tag cleanup...\n")
            let config = try ForgeConfig.load(from: configPath)
            try runCleanup(config: config)
            return
        }

        print("Initialising forge in \(workspacePath)\n")

        if !fm.fileExists(atPath: forgeDir) {
            try fm.createDirectory(atPath: forgeDir, withIntermediateDirectories: true)
        }

        let config = ForgeConfig.defaultConfig(projectRoots: [workspacePath])
        try config.save(to: configPath)
        print("✓ Created config.yaml")

        let inboxPath = (forgeDir as NSString).appendingPathComponent("inbox.md")
        if !fm.fileExists(atPath: inboxPath) {
            let inboxContent = """
            # Inbox

            Capture tasks here. Process with `forge process`.

            """
            try inboxContent.write(toFile: inboxPath, atomically: true, encoding: .utf8)
            print("✓ Created inbox.md")
        }

        let somedayPath = (forgeDir as NSString).appendingPathComponent("someday-maybe.md")
        if !fm.fileExists(atPath: somedayPath) {
            let somedayContent = """
            # Someday / Maybe

            Projects and ideas to revisit later.

            """
            try somedayContent.write(toFile: somedayPath, atomically: true, encoding: .utf8)
            print("✓ Created someday-maybe.md")
        }

        print()
        try runCleanup(config: config)

        print("\nForge is ready. Try 'forge board' to see your kanban board.")
    }

    private func resolveWorkspace() -> String {
        if let ws = workspace {
            return (ws as NSString).expandingTildeInPath
        }
        let cwd = FileManager.default.currentDirectoryPath
        let cwdForge = (cwd as NSString).appendingPathComponent("Forge")
        if FileManager.default.fileExists(atPath: cwdForge) {
            return cwd
        }
        return cwd
    }

    private func runCleanup(config: ForgeConfig) throws {
        let cleanup = TagCleanup(config: config)
        var allActions: [TagCleanup.CleanupAction] = []
        for root in config.resolvedProjectRoots {
            let actions = try cleanup.cleanupAliases(at: root)
            allActions.append(contentsOf: actions)
        }

        if allActions.isEmpty {
            print("Tags are clean — no aliases to resolve.")
        } else {
            print("Tag cleanup:")
            for action in allActions {
                print("  \(action.description)")
            }
        }

        let scanner = WorkspaceScanner(config: config)
        let projects = try scanner.scanProjects()
        let untagged = projects.filter { $0.column == nil }
        let tagged = projects.count - untagged.count

        print("\nFound \(projects.count) projects (\(tagged) tagged, \(untagged.count) untagged)")
    }
}
