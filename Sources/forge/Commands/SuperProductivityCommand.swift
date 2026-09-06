import ArgumentParser
import Foundation
import ForgeCore

/// Local Super Productivity task bridge. The Python adapter owns the REST and
/// Keychain details so the Swift CLI remains a thin, auditable launcher.
struct SuperProductivityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "superproductivity",
        abstract: "Synchronise explicitly mapped projects with Super Productivity.",
        subcommands: [
            Status.self,
            List.self,
            Show.self,
            Doctor.self,
            Align.self,
            Refresh.self,
            Sync.self,
            Focus.self,
            Start.self,
            Stop.self,
            SetupToken.self,
            MirrorMenuTree.self,
        ],
        defaultSubcommand: Status.self
    )

    fileprivate static func runPython(_ arguments: [String]) throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        guard let python = ExecutablePathResolver.forgePython(in: forgeDir) else {
            throw ValidationError("python3 not found on PATH.")
        }
        let script = (forgeDir as NSString).appendingPathComponent("scripts/forge-superproductivity.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script, "--forge-home", forgeDir] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: forgeDir)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ExecutablePathResolver.augmentedPATH()
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ExitCode(process.terminationStatus)
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "status", abstract: "Show connection and mapping status.")
        @Flag(name: .long) var json = false
        mutating func run() async throws {
            try SuperProductivityCommand.runPython(json ? ["--json", "status"] : ["status"])
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List Super Productivity projects.")
        @Flag(name: .long) var json = false
        mutating func run() async throws {
            try SuperProductivityCommand.runPython(json ? ["--json", "list"] : ["list"])
        }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Show remote tasks for one mapped project.")
        @Flag(name: .long) var json = false
        @Argument var project: String
        mutating func run() async throws {
            var args = json ? ["--json", "show"] : ["show"]
            args.append(project)
            try SuperProductivityCommand.runPython(args)
        }
    }

    struct Doctor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "doctor", abstract: "Check mappings and local folders.")
        @Flag(name: .long) var json = false
        mutating func run() async throws {
            try SuperProductivityCommand.runPython(json ? ["--json", "doctor"] : ["doctor"])
        }
    }

    struct Align: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "align", abstract: "Preview project bindings by title.")
        @Flag(name: .long) var apply = false
        @Flag(name: .long) var json = false
        mutating func run() async throws {
            var args = json ? ["--json", "align"] : ["align"]
            if apply { args.append("--apply") }
            try SuperProductivityCommand.runPython(args)
        }
    }

    struct Refresh: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "refresh",
            abstract: "Preview or apply a one-way Super Productivity import."
        )
        @Flag(name: .long) var apply = false
        @Flag(name: .long) var json = false
        @Argument var projects: [String] = []
        mutating func run() async throws {
            var args = json ? ["--json", "refresh"] : ["refresh"]
            if apply { args.append("--apply") }
            args.append(contentsOf: projects)
            try SuperProductivityCommand.runPython(args)
        }
    }

    struct Sync: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "sync",
            abstract: "Preview or apply a three-way task synchronisation."
        )
        @Flag(name: .long) var apply = false
        @Flag(name: .long) var json = false
        @Argument var projects: [String] = []
        mutating func run() async throws {
            var args = json ? ["--json", "sync"] : ["sync"]
            if apply { args.append("--apply") }
            args.append(contentsOf: projects)
            try SuperProductivityCommand.runPython(args)
        }
    }

    struct Focus: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "focus", abstract: "Read Super Productivity focus state.")
        @Flag(name: .long) var json = false
        mutating func run() async throws {
            try SuperProductivityCommand.runPython(json ? ["--json", "focus"] : ["focus"])
        }
    }

    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "start", abstract: "Start a Super Productivity task.")
        @Argument var taskId: String
        @Flag(name: .long) var json = false
        mutating func run() async throws {
            var args = json ? ["--json", "start"] : ["start"]
            args.append(taskId)
            try SuperProductivityCommand.runPython(args)
        }
    }

    struct Stop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "stop", abstract: "Stop the current Super Productivity task.")
        @Flag(name: .long) var json = false
        mutating func run() async throws {
            try SuperProductivityCommand.runPython(json ? ["--json", "stop"] : ["stop"])
        }
    }

    struct SetupToken: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "setup-token",
            abstract: "Store the API token in macOS Keychain."
        )
        mutating func run() async throws {
            try SuperProductivityCommand.runPython(["setup-token"])
        }
    }

    struct MirrorMenuTree: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "mirror-menu-tree",
            abstract: "Mirror Finder folder paths into Super Productivity project folders."
        )
        @Flag(name: .long, help: "Print the planned tree only.")
        var dryRun = false
        @Flag(name: .long) var json = false
        @Option(name: .long, help: "Path root used to derive nesting (default: ~/Documents).")
        var docsRoot: String?
        mutating func run() async throws {
            var args = ["mirror-menu-tree"]
            if dryRun { args.append("--dry-run") }
            if json { args.insert("--json", at: 0) }
            if let docsRoot {
                args.append(contentsOf: ["--docs-root", docsRoot])
            }
            try SuperProductivityCommand.runPython(args)
        }
    }
}
