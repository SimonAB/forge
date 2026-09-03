import Foundation

/// Runs `scripts/forge-capture.py` for inbox capture and processing.
public enum CaptureScriptRunner: Sendable {

    public struct CaptureResult: Sendable {
        public let taskID: String
        public let title: String
        public let rawJSON: String
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
                return "Capture script not found at \(path)."
            case .failed(let message):
                return message
            }
        }
    }

    /// Capture a title (and optional link/file) into the Forge inbox.
    public static func capture(
        forgeDir: String,
        title: String,
        link: String? = nil,
        kind: String? = nil,
        note: String? = nil,
        file: String? = nil,
        stash: Bool = false,
        source: String = "cli",
        clipboardLink: String? = nil
    ) throws -> CaptureResult {
        var args = ["capture", title, "--source", source, "--json"]
        if let link, !link.isEmpty { args += ["--link", link] }
        if let kind, !kind.isEmpty { args += ["--kind", kind] }
        if let note, !note.isEmpty { args += ["--note", note] }
        if let file, !file.isEmpty { args += ["--file", file] }
        if stash { args.append("--stash") }
        if let clipboardLink, !clipboardLink.isEmpty {
            args += ["--clipboard-link", clipboardLink]
        }
        let text = try run(forgeDir: forgeDir, arguments: args)
        guard let data = text.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let taskID = obj["id"] as? String,
              let capturedTitle = obj["title"] as? String else {
            throw RunnerError.failed("Capture returned unexpected JSON.")
        }
        return CaptureResult(taskID: taskID, title: capturedTitle, rawJSON: text)
    }

    /// List inbox items as JSON text.
    public static func inboxJSON(forgeDir: String) throws -> String {
        try run(forgeDir: forgeDir, arguments: ["inbox", "--json"])
    }

    /// Execute forge-capture.py and return stdout.
    public static func run(forgeDir: String, arguments: [String]) throws -> String {
        guard let python = ExecutablePathResolver.find(named: "python3") else {
            throw RunnerError.pythonNotFound
        }
        let script = (forgeDir as NSString).appendingPathComponent("scripts/forge-capture.py")
        guard FileManager.default.isReadableFile(atPath: script) else {
            throw RunnerError.scriptMissing(script)
        }

        let args = [script, "--forge-home", forgeDir] + arguments
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
            throw RunnerError.failed(detail.isEmpty ? "forge capture failed." : detail)
        }
        return outText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
