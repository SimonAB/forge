import Foundation

/// Launches commands in the user's preferred terminal application.
public struct TerminalLauncher: Sendable {

    /// Terminal apps in order of preference for auto-detection.
    private static let searchOrder = [
        "Ghostty", "kitty", "iTerm", "Warp", "Terminal"
    ]

    private let terminalApp: String

    public init(config: ForgeConfig) {
        if let preferred = config.terminal, preferred.lowercased() != "auto" {
            self.terminalApp = Self.normaliseTerminalName(preferred)
        } else {
            self.terminalApp = Self.detectTerminal()
        }
    }

    /// Normalises terminal name for matching (e.g. "Ghosttly" → "Ghostty").
    private static func normaliseTerminalName(_ name: String) -> String {
        switch name.lowercased() {
        case "ghosttly":
            return "Ghostty"
        default:
            return name
        }
    }

    /// The resolved terminal application name.
    public var resolvedTerminal: String { terminalApp }

    /// Run a command in a new terminal window.
    /// Writes the command to a script file and launches the terminal with that script so the command always runs correctly.
    /// After the command runs, starts an interactive shell so you can keep using the window.
    public func run(_ command: String, workingDirectory: String? = nil) {
        let pathExport = "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\" && "
        let cd = workingDirectory.map { "cd \"\($0.replacingOccurrences(of: "\"", with: "\\\""))\" && " } ?? ""
        let fullCommand = "\(pathExport)\(cd)\(command)\n\nexec /opt/homebrew/bin/zsh -i\n"
        guard let scriptURL = Self.writeCommandScript(fullCommand) else { return }

        switch terminalApp.lowercased() {
        case "ghostty":
            launchGhostty(scriptURL: scriptURL)
        case "kitty":
            launchKitty(scriptURL: scriptURL)
        case "iterm", "iterm2":
            launchITerm(scriptURL: scriptURL)
        case "warp":
            launchWarp(scriptURL: scriptURL)
        default:
            launchTerminalApp(scriptURL: scriptURL)
        }
    }

    /// Writes the shell command to a temporary script and returns its URL. Caller can delete later.
    private static func writeCommandScript(_ command: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("forge-run-\(UUID().uuidString).sh")
        let script = "#!/opt/homebrew/bin/zsh\n\(command)"
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
            return scriptURL
        } catch {
            return nil
        }
    }

    // MARK: - Terminal-Specific Launchers

    /// Launch Ghostty: pass only the script path so Ghostty runs it directly (script has shebang).
    /// Ghostty wraps -e in "login -flp user <command>" so a single path works; "zsh path" was failing.
    private func launchGhostty(scriptURL: URL) {
        let scriptPath = scriptURL.path
        let scriptPathQuoted = scriptPath.replacingOccurrences(of: "'", with: "'\\''")
        let openScript = "#!/bin/zsh\nopen -na Ghostty.app --args -e '\(scriptPathQuoted)'\n"
        let openScriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("forge-open-ghostty-\(UUID().uuidString).sh")
        try? openScript.write(to: openScriptURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: openScriptURL.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [openScriptURL.path]
        process.qualityOfService = .userInitiated
        try? process.run()
        Self.scheduleScriptDeletion(openScriptURL, delay: 5)
        Self.scheduleScriptDeletion(scriptURL, delay: 60)
    }

    private static func scheduleScriptDeletion(_ url: URL, delay: TimeInterval = 10) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func launchKitty(scriptURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Applications/kitty.app/Contents/MacOS/kitty")
        process.arguments = ["/opt/homebrew/bin/zsh", scriptURL.path]
        process.qualityOfService = .userInitiated
        try? process.run()
        Self.scheduleScriptDeletion(scriptURL)
    }

    private func launchITerm(scriptURL: URL) {
        let path = scriptURL.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm"
            activate
            create window with default profile command "/opt/homebrew/bin/zsh \\"\(path)\\""
        end tell
        """
        runAppleScript(script)
        Self.scheduleScriptDeletion(scriptURL)
    }

    private func launchWarp(scriptURL: URL) {
        let path = scriptURL.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Warp"
            activate
            do script "/opt/homebrew/bin/zsh \\"\(path)\\""
        end tell
        """
        runAppleScript(script)
        Self.scheduleScriptDeletion(scriptURL)
    }

    private func launchTerminalApp(scriptURL: URL) {
        let path = scriptURL.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "/opt/homebrew/bin/zsh \\"\(path)\\""
        end tell
        """
        runAppleScript(script)
        Self.scheduleScriptDeletion(scriptURL)
    }

    private func runAppleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    // MARK: - Detection

    private static func detectTerminal() -> String {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let appDirs = ["/Applications", (home as NSString).appendingPathComponent("Applications")]
        for appDir in appDirs {
            for appName in searchOrder {
                let path = (appDir as NSString).appendingPathComponent("\(appName).app")
                if fm.fileExists(atPath: path) {
                    return appName
                }
            }
        }
        return "Terminal"
    }
}
