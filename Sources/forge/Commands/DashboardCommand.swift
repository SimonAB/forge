import ArgumentParser
import Foundation
import ForgeCore

struct DashboardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dashboard",
        abstract: "GTD dashboard — projects, calendar, and due tasks.",
        discussion: """
        Wraps scripts/forge-dashboard.py (TASKS.toml per project + .forge/world.db task index). \
        Use --json for structured output (Forge.app popover).
        """
    )

    @Option(name: .long, help: "Terminal layout: tick, compact, split, full.")
    var layout: String = "compact"

    @Option(name: .long, help: "Rows per section.")
    var show: Int = 8

    @Option(name: .long, help: "Due-task horizon in days.")
    var dueDays: Int = 14

    @Flag(name: .long, help: "Run morning-review-pull.sh before rendering.")
    var refresh: Bool = false

    @Flag(name: .long, help: "Emit structured JSON instead of terminal layout.")
    var json: Bool = false

    @Option(name: .long, help: "Clear and re-render every N seconds (terminal only).")
    var watch: Double?

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)

        if let interval = watch, !json {
            guard let python = ExecutablePathResolver.find(named: "python3") else {
                throw ValidationError("python3 not found on PATH.")
            }
            let script = (forgeDir as NSString).appendingPathComponent("scripts/forge-dashboard.py")
            var args = [
                script,
                "--forge-home", forgeDir,
                "--layout", layout,
                "--show", String(show),
                "--due-days", String(dueDays),
                "--watch", String(interval),
            ]
            if refresh { args.append("--refresh") }
            let status = try Self.runProcess(executable: python, arguments: args, cwd: forgeDir)
            if status != 0 { throw ExitCode(status) }
            return
        }

        let options = DashboardScriptRunner.Options(
            layout: layout,
            show: show,
            dueDays: dueDays,
            refresh: refresh,
            jsonOnly: json
        )
        let output = try DashboardScriptRunner.run(forgeDir: forgeDir, options: options)
        print(output, terminator: output.hasSuffix("\n") ? "" : "\n")
    }

    private static func runProcess(executable: String, arguments: [String], cwd: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ExecutablePathResolver.augmentedPATH()
        process.environment = env
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
