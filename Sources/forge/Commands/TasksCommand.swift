import ArgumentParser
import Foundation
import ForgeCore

struct TasksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tasks",
        abstract: "Inbox and task processing (list, assign, complete, open).",
        subcommands: [
            TasksInboxCommand.self,
            TasksAssignCommand.self,
            TasksCompleteCommand.self,
            TasksOpenCommand.self,
        ]
    )
}

struct TasksInboxCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "List Forge inbox items."
    )

    @Flag(name: .long, help: "Emit JSON.")
    var json: Bool = false

    mutating func run() async throws {
        try Self.runCapture(subcommand: ["inbox"] + (json ? ["--json"] : []))
    }

    static func runCapture(subcommand: [String]) throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        guard let python = ExecutablePathResolver.forgePython(in: forgeDir) else {
            throw ValidationError("python3 not found on PATH.")
        }
        let script = (forgeDir as NSString).appendingPathComponent("scripts/forge-capture.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script, "--forge-home", forgeDir] + subcommand
        process.currentDirectoryURL = URL(fileURLWithPath: forgeDir)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ExecutablePathResolver.augmentedPATH()
        process.environment = env
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ExitCode(process.terminationStatus)
        }
    }
}

struct TasksAssignCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assign",
        abstract: "Assign an inbox item to a Forge project."
    )

    @Argument(help: "Task id.")
    var taskID: String

    @Argument(help: "Project name substring.")
    var project: String

    @Option(name: .long, help: "Section: next, waiting, or someday.")
    var section: String = "next"

    mutating func run() async throws {
        try TasksInboxCommand.runCapture(
            subcommand: ["assign", taskID, project, "--section", section]
        )
    }
}

struct TasksCompleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "complete",
        abstract: "Mark a task done."
    )

    @Argument(help: "Task id.")
    var taskID: String

    mutating func run() async throws {
        try TasksInboxCommand.runCapture(subcommand: ["complete", taskID])
    }
}

struct TasksOpenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open the first link on a task (Mail, file, URL)."
    )

    @Argument(help: "Task id.")
    var taskID: String

    @Flag(name: .long, help: "Print URI instead of opening.")
    var printOnly: Bool = false

    mutating func run() async throws {
        var args = ["open", taskID]
        if printOnly { args.append("--print-only") }
        try TasksInboxCommand.runCapture(subcommand: args)
    }
}
