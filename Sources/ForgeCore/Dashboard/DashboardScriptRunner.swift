import Foundation

/// Runs `scripts/forge-dashboard.py` and decodes JSON for GUI surfaces.
public enum DashboardScriptRunner: Sendable {

    public struct Options: Sendable {
        public var layout: String
        public var show: Int
        public var dueDays: Int
        public var refresh: Bool
        public var jsonOnly: Bool

        public init(
            layout: String = "compact",
            show: Int = 8,
            dueDays: Int = 14,
            refresh: Bool = false,
            jsonOnly: Bool = true
        ) {
            self.layout = layout
            self.show = show
            self.dueDays = dueDays
            self.refresh = refresh
            self.jsonOnly = jsonOnly
        }
    }

    public enum RunnerError: Error, CustomStringConvertible {
        case pythonNotFound
        case scriptMissing(String)
        case failed(String)

        public var description: String {
            switch self {
            case .pythonNotFound:
                return "python3 not found on PATH."
            case .scriptMissing(let path):
                return "Dashboard script not found at \(path)."
            case .failed(let message):
                return message
            }
        }
    }

    /// Execute the dashboard script and return stdout (text or JSON).
    public static func run(forgeDir: String, options: Options = Options()) throws -> String {
        guard let python = ExecutablePathResolver.find(named: "python3") else {
            throw RunnerError.pythonNotFound
        }
        let script = (forgeDir as NSString).appendingPathComponent("scripts/forge-dashboard.py")
        guard FileManager.default.isReadableFile(atPath: script) else {
            throw RunnerError.scriptMissing(script)
        }

        var args = [
            script,
            "--forge-home", forgeDir,
            "--layout", options.layout,
            "--show", String(options.show),
            "--due-days", String(options.dueDays),
        ]
        if options.refresh {
            args.append("--refresh")
        }
        if options.jsonOnly {
            args.append("--json")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: forgeDir)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ExecutablePathResolver.augmentedPATH()
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outText = String(data: outData, encoding: .utf8) ?? ""
        let errText = String(data: errData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = errText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RunnerError.failed(detail.isEmpty ? "forge dashboard failed." : detail)
        }
        return outText
    }

    /// Load a structured dashboard snapshot for SwiftUI.
    public static func loadSnapshot(
        forgeDir: String,
        options: Options = Options()
    ) throws -> DashboardSnapshotJSON {
        let text = try run(forgeDir: forgeDir, options: options)
        guard let data = text.data(using: .utf8) else {
            throw RunnerError.failed("Dashboard returned invalid UTF-8.")
        }
        let decoder = JSONDecoder()
        return try decoder.decode(DashboardSnapshotJSON.self, from: data)
    }
}
