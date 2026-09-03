import ArgumentParser
import Foundation
import ForgeCore

struct CaptureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "Capture into the Forge inbox (zero-friction GTD).",
        discussion: """
        Writes to `.forge/tasks.db`. Link-only by default; use --stash to copy a file \
        into `.forge/inbox/<id>/`. Assistants: forge capture "…" --source assistant
        """
    )

    @Argument(help: "Inbox item title.")
    var title: String

    @Option(name: .long, help: "URI (message://, file://, https://, …).")
    var link: String?

    @Option(name: .long, help: "Link kind: mail, file, url, note, obsidian, bookends, other.")
    var kind: String?

    @Option(name: .long, help: "Optional note body.")
    var note: String?

    @Option(name: .long, help: "Local file path (link-only unless --stash).")
    var file: String?

    @Flag(name: .long, help: "Copy --file into .forge/inbox/<id>/.")
    var stash: Bool = false

    @Option(name: .long, help: "Source label (cli, menubar, assistant).")
    var source: String = "cli"

    @Flag(name: .long, help: "Emit JSON.")
    var json: Bool = false

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)
        guard let python = ExecutablePathResolver.find(named: "python3") else {
            throw ValidationError("python3 not found on PATH.")
        }
        let script = (forgeDir as NSString).appendingPathComponent("scripts/forge-capture.py")
        var args = [script, "--forge-home", forgeDir, "capture", title, "--source", source]
        if let link, !link.isEmpty { args += ["--link", link] }
        if let kind, !kind.isEmpty { args += ["--kind", kind] }
        if let note, !note.isEmpty { args += ["--note", note] }
        if let file, !file.isEmpty { args += ["--file", file] }
        if stash { args.append("--stash") }
        if json { args.append("--json") }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = args
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
