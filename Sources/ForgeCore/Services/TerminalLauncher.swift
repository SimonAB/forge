import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Launches commands in the user's preferred terminal application.
public struct TerminalLauncher: Sendable {

    /// Terminal apps in order of preference for auto-detection.
    private static let searchOrder = [
        "Ghostty", "kitty", "iTerm", "Warp", "cmux", "Terminal"
    ]

    private let terminalApp: String
    private let openURL: (@Sendable (URL) -> Void)?

    public init(config: ForgeConfig, terminalOverride: String? = nil, openURL: (@Sendable (URL) -> Void)? = nil) {
        self.openURL = openURL
        let preferred: String?
        if let overrideName = terminalOverride, !overrideName.isEmpty, overrideName.lowercased() != "auto" {
            preferred = Self.normaliseTerminalName(overrideName)
        } else if let fromConfig = config.terminal, fromConfig.lowercased() != "auto" {
            preferred = Self.normaliseTerminalName(fromConfig)
        } else {
            preferred = nil
        }
        if let p = preferred {
            self.terminalApp = p
        } else {
            self.terminalApp = Self.detectTerminal()
        }
    }

    /// Normalises terminal name for matching (e.g. "Ghosttly" → "Ghostty").
    private static func normaliseTerminalName(_ name: String) -> String {
        switch name.lowercased() {
        case "ghosttly":
            return "Ghostty"
        case "cmux.app":
            return "cmux"
        default:
            return name
        }
    }

    /// The resolved terminal application name.
    public var resolvedTerminal: String { terminalApp }

    /// Open the terminal editor on `filePath` (typically `vim` on `PATH`, often aliased to Neovim).
    ///
    /// Uses each terminal’s native “run this command” hooks (Ghostty surface `command` + environment,
    /// kitty remote `launch`, etc.) so the session matches `cd dir && vim relative-file`.
    public func openNeovim(filePath: String, workingDirectory: String) {
        switch terminalApp.lowercased() {
        case "ghostty":
            launchGhosttyOpenNeovim(filePath: filePath, workingDirectory: workingDirectory)
        case "kitty":
            launchKittyOpenNeovim(filePath: filePath, workingDirectory: workingDirectory)
        case "iterm", "iterm2":
            launchITermOpenNeovim(filePath: filePath, workingDirectory: workingDirectory)
        case "warp":
            launchWarpOpenNeovim(filePath: filePath, workingDirectory: workingDirectory)
        case "cmux", "cmux.app":
            launchCmuxOpenNeovim(filePath: filePath, workingDirectory: workingDirectory)
        default:
            launchTerminalOpenNeovim(filePath: filePath, workingDirectory: workingDirectory)
        }
    }

    /// Run a command in a new terminal window.
    /// Writes the command to a script file and launches the terminal with that script so the command always runs correctly.
    /// After the command runs, starts an interactive shell so you can keep using the window.
    public func run(_ command: String, workingDirectory: String? = nil) {
        let pathLine = "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\""
        let cdLine: String
        if let wd = workingDirectory, !wd.isEmpty {
            let escapedWd = wd.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            cdLine = "cd \"\(escapedWd)\""
        } else {
            cdLine = "true"
        }
        let fullCommand = """
        \(pathLine)
        \(cdLine)
        \(command)
        exec /opt/homebrew/bin/zsh -i

        """
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
        case "cmux", "cmux.app":
            launchCmux(scriptURL: scriptURL)
        default:
            launchTerminal(scriptURL: scriptURL)
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

    // MARK: - Terminal Launch

    /// Activate terminal, open a new tab (Cmd+T), and execute the script command.
    private func launchInNewTab(appName: String, scriptURL: URL) {
        let escapedPath = scriptURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let shellCommand = "/opt/homebrew/bin/zsh '\(escapedPath)'"
        let escapedShellCommand = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedAppName = appName.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "\(escapedAppName)" to activate
        delay 0.25
        tell application "System Events"
            keystroke "t" using command down
            delay 0.15
            keystroke "\(escapedShellCommand)"
            key code 36
        end tell
        """
        runAppleScript(script)
        Self.scheduleScriptDeletion(scriptURL, delay: 60)
    }

    /// Use Ghostty surface configuration so the command runs directly (no `input text` into the shell).
    private func launchGhostty(scriptURL: URL) {
        let escapedPath = scriptURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let zshRun = "/opt/homebrew/bin/zsh \"\(escapedPath)\""
        let escapedCommand = Self.escapeForAppleScriptDoubleQuoted(zshRun)
        let script = """
        tell application "Ghostty"
            activate
            if (count of windows) = 0 then
                set win to new window
            else
                set win to front window
            end if
            set cfg to new surface configuration
            set command of cfg to "\(escapedCommand)"
            set newTab to new tab in win with configuration cfg
        end tell
        """
        runAppleScript(script)
        Self.scheduleScriptDeletion(scriptURL, delay: 60)
    }

    /// Use kitty remote control to launch a new tab when available.
    /// Falls back to keystroke automation if remote control is unavailable.
    private func launchKitty(scriptURL: URL) {
        _ = runProcess("/usr/bin/open", arguments: ["-a", "kitty.app"])
        Thread.sleep(forTimeInterval: 0.2)

        let escapedPath = scriptURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let command = "/opt/homebrew/bin/zsh '\(escapedPath)'"
        let launched = runProcess(
            "/Applications/kitty.app/Contents/MacOS/kitty",
            arguments: ["@", "launch", "--type=tab", command]
        )
        if launched {
            Self.scheduleScriptDeletion(scriptURL, delay: 60)
            return
        }

        launchInNewTab(appName: "kitty", scriptURL: scriptURL)
    }

    /// Use iTerm AppleScript automation to open a tab and run the command.
    private func launchITerm(scriptURL: URL) {
        let path = scriptURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let command = "/opt/homebrew/bin/zsh '\(path)'"
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application id "com.googlecode.iterm2"
            activate
            if (count of windows) = 0 then
                create window with default profile command "\(escapedCommand)"
            else
                tell current window
                    create tab with default profile command "\(escapedCommand)"
                end tell
            end if
        end tell
        """
        runAppleScript(script)
        Self.scheduleScriptDeletion(scriptURL, delay: 60)
    }

    /// Use Terminal AppleScript to run command in a new tab in the front window.
    private func launchTerminal(scriptURL: URL) {
        let path = scriptURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let command = "/opt/homebrew/bin/zsh '\(path)'"
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            if (count of windows) = 0 then
                do script "\(escapedCommand)"
            else
                tell application "System Events"
                    keystroke "t" using command down
                end tell
                delay 0.15
                do script "\(escapedCommand)" in selected tab of front window
            end if
        end tell
        """
        runAppleScript(script)
        Self.scheduleScriptDeletion(scriptURL, delay: 60)
    }

    // MARK: - Warp launch configurations

    /// Escapes a string for YAML double-quoted scalars under `~/.warp/launch_configurations/`.
    private static func escapeForWarpYamlDoubleQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// URL to open a named Warp launch configuration (`warp://launch/…`).
    private static func warpLaunchURL(forConfigurationName configurationName: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let encoded = configurationName.addingPercentEncoding(withAllowedCharacters: allowed) ?? configurationName
        return URL(string: "warp://launch/\(encoded)")
    }

    /// Use Warp launch configurations to run commands in a new session.
    private func launchWarp(scriptURL: URL) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let launchDir = (home as NSString).appendingPathComponent(".warp/launch_configurations")
        guard (try? FileManager.default.createDirectory(atPath: launchDir, withIntermediateDirectories: true)) != nil else {
            launchInNewTab(appName: "Warp", scriptURL: scriptURL)
            return
        }

        let configName = "forge-\(UUID().uuidString.prefix(8))"
        let yamlURL = URL(fileURLWithPath: (launchDir as NSString).appendingPathComponent("\(configName).yaml"))
        let scriptPath = Self.escapeForWarpYamlDoubleQuoted(scriptURL.path)
        let homePath = Self.escapeForWarpYamlDoubleQuoted(home)
        let yaml = """
        ---
        name: \(configName)
        windows:
          - tabs:
              - layout:
                  cwd: "\(homePath)"
                  commands:
                    - exec: "/opt/homebrew/bin/zsh \\"\(scriptPath)\\""
        """
        guard (try? yaml.write(to: yamlURL, atomically: true, encoding: .utf8)) != nil else {
            launchInNewTab(appName: "Warp", scriptURL: scriptURL)
            return
        }

        if let url = Self.warpLaunchURL(forConfigurationName: configName) {
            openURL?(url)
        } else {
            launchInNewTab(appName: "Warp", scriptURL: scriptURL)
        }
        Self.scheduleScriptDeletion(scriptURL, delay: 60)
        Self.scheduleScriptDeletion(yamlURL, delay: 60)
    }

    // MARK: - Terminal editor (vim / Neovim)

    /// Single-quote a string for POSIX shell words (`'a'\''b'` for embedded quotes).
    private static func shellSingleQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escape content for use inside an AppleScript double-quoted string.
    private static func escapeForAppleScriptDoubleQuoted(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Escape for a double-quoted argument to `zsh -c` (used by iTerm / Terminal / Warp YAML).
    private static func escapeForDoubleQuotedZshC(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    private static func resolvedNeovimExecutablePath() -> String {
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/nvim") { return "/opt/homebrew/bin/nvim" }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/nvim") { return "/usr/local/bin/nvim" }
        return "/opt/homebrew/bin/nvim"
    }

    /// Shell command for `cd … && <cmd> file`. Use `vim` so it matches common `vim`→`nvim` aliases; Homebrew is first on `PATH` in Neovim env.
    private static let neovimShellCommandName = "vim"

    /// Path to pass to the editor: relative to `workingDirectory` when the file lies under it, otherwise absolute.
    private static func neovimFilePathForInvocation(filePath: String, workingDirectory: String) -> String {
        let file = (filePath as NSString).standardizingPath
        let dir = (workingDirectory as NSString).standardizingPath
        if file == dir {
            return "."
        }
        let dirPrefix = dir.hasSuffix("/") ? dir : dir + "/"
        if file.hasPrefix(dirPrefix) {
            let relative = String(file.dropFirst(dirPrefix.count))
            return relative.isEmpty ? file : relative
        }
        return file
    }

    /// Real login home from the user database (not the app sandbox container).
    ///
    /// Finder-launched or sandboxed GUI apps often report a **container** path from
    /// `FileManager.homeDirectoryForCurrentUser`. Neovim/lazy.nvim then use a separate
    /// `~/.local/share/nvim` tree and appear to reinstall plugins every launch.
    private static func passwdHomeDirectoryPath() -> String? {
#if canImport(Darwin)
        guard let pw = getpwuid(getuid()) else { return nil }
        let dir = String(cString: pw.pointee.pw_dir)
        if dir.isEmpty { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }
        return dir
#else
        return nil
#endif
    }

    /// Login name from the user record when `ProcessInfo` omits `USER` (common for GUI apps).
    private static func passwdUserName() -> String? {
#if canImport(Darwin)
        guard let pw = getpwuid(getuid()) else { return nil }
        let name = String(cString: pw.pointee.pw_name)
        return name.isEmpty ? nil : name
#else
        return nil
#endif
    }

    /// Preferred shell from the user record when the environment does not set `SHELL`.
    private static func passwdShellPath() -> String? {
#if canImport(Darwin)
        guard let pw = getpwuid(getuid()) else { return nil }
        let shell = String(cString: pw.pointee.pw_shell)
        return shell.isEmpty ? nil : shell
#else
        return nil
#endif
    }

    /// `PATH` for Neovim subprocesses: ensure Homebrew prefixes exist but keep the caller’s entries (nvm, cargo, …).
    private static func neovimPathValue(processEnvironment env: [String: String]) -> String {
        let prefix = "/opt/homebrew/bin:/usr/local/bin"
        let fallback = "\(prefix):/usr/bin:/bin:/usr/sbin:/sbin"
        guard let existing = env["PATH"], !existing.isEmpty else { return fallback }
        if existing.contains("/opt/homebrew/bin") || existing.contains("/usr/local/bin") {
            return existing
        }
        return "\(prefix):\(existing)"
    }

    /// Stable `HOME` / `XDG_*` / `PATH` for Neovim so plugin managers match a normal terminal session.
    private static func neovimEnvironmentPairs() -> [(String, String)] {
        let env = ProcessInfo.processInfo.environment
        let fallbackHome = FileManager.default.homeDirectoryForCurrentUser.path
        let home: String = {
            if let passwd = passwdHomeDirectoryPath() { return passwd }
            if let h = env["HOME"], !h.isEmpty { return h }
            return fallbackHome
        }()
        func resolve(_ key: String, _ defaultRelative: String) -> String {
            if let v = env[key], !v.isEmpty { return v }
            return (home as NSString).appendingPathComponent(defaultRelative)
        }
        var pairs: [(String, String)] = [
            ("HOME", home),
            ("PATH", neovimPathValue(processEnvironment: env)),
            ("XDG_CONFIG_HOME", resolve("XDG_CONFIG_HOME", ".config")),
            ("XDG_DATA_HOME", resolve("XDG_DATA_HOME", ".local/share")),
            ("XDG_STATE_HOME", resolve("XDG_STATE_HOME", ".local/state")),
            ("XDG_CACHE_HOME", resolve("XDG_CACHE_HOME", ".cache")),
        ]
        if let u = env["USER"], !u.isEmpty {
            pairs.append(("USER", u))
        } else if let u = passwdUserName() {
            pairs.append(("USER", u))
        }
        if let l = env["LOGNAME"], !l.isEmpty {
            pairs.append(("LOGNAME", l))
        } else if let u = passwdUserName() {
            pairs.append(("LOGNAME", u))
        }
        if let s = env["SHELL"], !s.isEmpty {
            pairs.append(("SHELL", s))
        } else if let s = passwdShellPath() {
            pairs.append(("SHELL", s))
        }
        if let n = env["NVIM_APPNAME"], !n.isEmpty { pairs.append(("NVIM_APPNAME", n)) }
        if let l = env["LANG"], !l.isEmpty { pairs.append(("LANG", l)) }
        if let t = env["TERM"], !t.isEmpty { pairs.append(("TERM", t)) }
        return pairs
    }

    /// AppleScript list: `{"HOME=…", "PATH=…", …}` for Ghostty `environment variables`.
    private static func neovimEnvironmentListForAppleScript() -> String {
        neovimEnvironmentPairs().map { k, v in
            let pair = "\(k)=\(v)"
            return "\"\(escapeForAppleScriptDoubleQuoted(pair))\""
        }.joined(separator: ", ")
    }

    private static func mergedEnvironmentForNeovimSubprocess() -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        for (k, v) in neovimEnvironmentPairs() { e[k] = v }
        return e
    }

    /// Short shell line: `cd 'wd' && vim 'relative-or-absolute-file'` (for terminals without structured env).
    private static func neovimShellInvocation(filePath: String, workingDirectory: String) -> String {
        let target = neovimFilePathForInvocation(filePath: filePath, workingDirectory: workingDirectory)
        return "cd \(shellSingleQuoted(workingDirectory)) && \(neovimShellCommandName) \(shellSingleQuoted(target))"
    }

    private func launchGhosttyOpenNeovim(filePath: String, workingDirectory: String) {
        let target = Self.neovimFilePathForInvocation(filePath: filePath, workingDirectory: workingDirectory)
        let cmd = "\(Self.neovimShellCommandName) \(Self.shellSingleQuoted(target))"
        let wdAS = Self.escapeForAppleScriptDoubleQuoted(workingDirectory)
        let cmdAS = Self.escapeForAppleScriptDoubleQuoted(cmd)
        let envList = Self.neovimEnvironmentListForAppleScript()
        let script = """
        tell application "Ghostty"
            activate
            if (count of windows) = 0 then
                set win to new window
            else
                set win to front window
            end if
            set cfg to new surface configuration
            set initial working directory of cfg to "\(wdAS)"
            set environment variables of cfg to {\(envList)}
            set command of cfg to "\(cmdAS)"
            set newTab to new tab in win with configuration cfg
        end tell
        """
        runAppleScript(script)
    }

    private func launchKittyOpenNeovim(filePath: String, workingDirectory: String) {
        _ = runProcess("/usr/bin/open", arguments: ["-a", "kitty.app"])
        Thread.sleep(forTimeInterval: 0.2)
        let nvim = Self.resolvedNeovimExecutablePath()
        let target = Self.neovimFilePathForInvocation(filePath: filePath, workingDirectory: workingDirectory)
        let ok = runProcessWithEnvironment(
            executablePath: "/Applications/kitty.app/Contents/MacOS/kitty",
            arguments: ["@", "launch", "--type=tab", "--cwd", workingDirectory, nvim, target],
            environment: Self.mergedEnvironmentForNeovimSubprocess()
        )
        if !ok {
            launchNeovimFallbackKeystroke(filePath: filePath, workingDirectory: workingDirectory)
        }
    }

    private func launchITermOpenNeovim(filePath: String, workingDirectory: String) {
        let line = Self.neovimShellInvocation(filePath: filePath, workingDirectory: workingDirectory)
        let zshCmd = "/opt/homebrew/bin/zsh -c \"\(Self.escapeForDoubleQuotedZshC(line))\""
        let escapedCommand = Self.escapeForAppleScriptDoubleQuoted(zshCmd)
        let script = """
        tell application id "com.googlecode.iterm2"
            activate
            if (count of windows) = 0 then
                create window with default profile command "\(escapedCommand)"
            else
                tell current window
                    create tab with default profile command "\(escapedCommand)"
                end tell
            end if
        end tell
        """
        runAppleScript(script)
    }

    private func launchTerminalOpenNeovim(filePath: String, workingDirectory: String) {
        let line = Self.neovimShellInvocation(filePath: filePath, workingDirectory: workingDirectory)
        let zshCmd = "/opt/homebrew/bin/zsh -c \"\(Self.escapeForDoubleQuotedZshC(line))\""
        let escapedCommand = Self.escapeForAppleScriptDoubleQuoted(zshCmd)
        let script = """
        tell application "Terminal"
            activate
            if (count of windows) = 0 then
                do script "\(escapedCommand)"
            else
                tell application "System Events"
                    keystroke "t" using command down
                end tell
                delay 0.15
                do script "\(escapedCommand)" in selected tab of front window
            end if
        end tell
        """
        runAppleScript(script)
    }

    private func launchWarpOpenNeovim(filePath: String, workingDirectory: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let launchDir = (home as NSString).appendingPathComponent(".warp/launch_configurations")
        guard (try? FileManager.default.createDirectory(atPath: launchDir, withIntermediateDirectories: true)) != nil else {
            launchNeovimFallbackKeystroke(filePath: filePath, workingDirectory: workingDirectory)
            return
        }

        let target = Self.neovimFilePathForInvocation(filePath: filePath, workingDirectory: workingDirectory)
        let configName = "forge-nvim-\(UUID().uuidString.prefix(8))"
        let yamlURL = URL(fileURLWithPath: (launchDir as NSString).appendingPathComponent("\(configName).yaml"))
        let cwdYaml = Self.escapeForWarpYamlDoubleQuoted(workingDirectory)
        let editorYaml = Self.escapeForWarpYamlDoubleQuoted(Self.neovimShellCommandName)
        let fileYaml = Self.escapeForWarpYamlDoubleQuoted(target)
        let yaml = """
        ---
        name: \(configName)
        windows:
          - tabs:
              - layout:
                  cwd: "\(cwdYaml)"
                  commands:
                    - exec: "\(editorYaml) \\"\(fileYaml)\\""
        """
        guard (try? yaml.write(to: yamlURL, atomically: true, encoding: .utf8)) != nil else {
            launchNeovimFallbackKeystroke(filePath: filePath, workingDirectory: workingDirectory)
            return
        }

        if let url = Self.warpLaunchURL(forConfigurationName: configName) {
            openURL?(url)
        } else {
            launchNeovimFallbackKeystroke(filePath: filePath, workingDirectory: workingDirectory)
        }
        Self.scheduleScriptDeletion(yamlURL, delay: 60)
    }

    private func launchCmuxOpenNeovim(filePath: String, workingDirectory: String) {
        let line = Self.neovimShellInvocation(filePath: filePath, workingDirectory: workingDirectory)
        _ = runProcess("/usr/bin/open", arguments: ["-a", "cmux.app"])
        Thread.sleep(forTimeInterval: 0.25)

        guard let cmuxBinaryPath = resolveCmuxBinaryPath() else {
            launchNeovimFallbackKeystroke(filePath: filePath, workingDirectory: workingDirectory)
            return
        }

        let newPaneResult = runProcessCaptureOutputWithStatus(cmuxBinaryPath, arguments: ["new-pane"])
        if newPaneResult.status != 0 {
            let stderrText = (newPaneResult.stderr ?? "").lowercased()
            if stderrText.contains("access denied") || stderrText.contains("only processes started inside cmux") {
                showCmuxAccessDeniedWarning()
            }
            launchNeovimFallbackKeystroke(filePath: filePath, workingDirectory: workingDirectory)
            return
        }
        guard let newPaneOutput = newPaneResult.stdout,
              let surface = parseCmuxSurfaceRef(from: newPaneOutput),
              let workspace = parseCmuxWorkspaceRef(from: newPaneOutput) else {
            launchNeovimFallbackKeystroke(filePath: filePath, workingDirectory: workingDirectory)
            return
        }

        Thread.sleep(forTimeInterval: 1.5)

        let sent = runProcess(
            cmuxBinaryPath,
            arguments: ["send", "--workspace", workspace, "--surface", surface, line]
        )
        let entered = runProcess(
            cmuxBinaryPath,
            arguments: ["send-key", "--workspace", workspace, "--surface", surface, "enter"]
        )
        if !sent || !entered {
            launchNeovimFallbackKeystroke(filePath: filePath, workingDirectory: workingDirectory)
        }
    }

    /// Last-resort: short `cd … && nvim …` keystrokes (no long `export` paste).
    private func launchNeovimFallbackKeystroke(filePath: String, workingDirectory: String) {
        let line = Self.neovimShellInvocation(filePath: filePath, workingDirectory: workingDirectory)
        let escapedShellLine = Self.escapeForAppleScriptDoubleQuoted(line)
        let appName = terminalApp
        let escapedAppName = appName.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "\(escapedAppName)" to activate
        delay 0.25
        tell application "System Events"
            keystroke "t" using command down
            delay 0.15
            keystroke "\(escapedShellLine)"
            key code 36
        end tell
        """
        runAppleScript(script)
    }

    /// Launch via a minimal cmux flow: create pane, send command, press enter.
    private func launchCmux(scriptURL: URL) {
        _ = runProcess("/usr/bin/open", arguments: ["-a", "cmux.app"])
        Thread.sleep(forTimeInterval: 0.25)

        guard let cmuxBinaryPath = resolveCmuxBinaryPath() else {
            launchInNewTab(appName: "cmux", scriptURL: scriptURL)
            return
        }

        let newPaneResult = runProcessCaptureOutputWithStatus(cmuxBinaryPath, arguments: ["new-pane"])
        if newPaneResult.status != 0 {
            let stderrText = (newPaneResult.stderr ?? "").lowercased()
            if stderrText.contains("access denied") || stderrText.contains("only processes started inside cmux") {
                showCmuxAccessDeniedWarning()
            }
            launchInNewTab(appName: "cmux", scriptURL: scriptURL)
            return
        }
        guard let newPaneOutput = newPaneResult.stdout,
              let surface = parseCmuxSurfaceRef(from: newPaneOutput),
              let workspace = parseCmuxWorkspaceRef(from: newPaneOutput) else {
            launchInNewTab(appName: "cmux", scriptURL: scriptURL)
            return
        }

        // Empirically, cmux needs a longer readiness delay before pane input executes.
        Thread.sleep(forTimeInterval: 1.5)

        let escapedPath = scriptURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let command = "/opt/homebrew/bin/zsh '\(escapedPath)'"
        let sent = runProcess(
            cmuxBinaryPath,
            arguments: ["send", "--workspace", workspace, "--surface", surface, command]
        )
        let entered = runProcess(
            cmuxBinaryPath,
            arguments: ["send-key", "--workspace", workspace, "--surface", surface, "enter"]
        )
        if !sent || !entered {
            launchInNewTab(appName: "cmux", scriptURL: scriptURL)
            return
        }
        Self.scheduleScriptDeletion(scriptURL, delay: 60)
    }

    private static func scheduleScriptDeletion(_ url: URL, delay: TimeInterval = 10) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func runAppleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    /// Resolve a cmux CLI path that can be invoked outside cmux.
    private func resolveCmuxBinaryPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/cmux",
            "/usr/local/bin/cmux",
            "/Applications/cmux.app/Contents/Resources/bin/cmux",
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    /// Run a process synchronously and return true on success.
    @discardableResult
    private func runProcess(_ executablePath: String, arguments: [String]) -> Bool {
        runProcessWithEnvironment(executablePath: executablePath, arguments: arguments, environment: makeProcessEnvironment(for: executablePath))
    }

    @discardableResult
    private func runProcessWithEnvironment(executablePath: String, arguments: [String], environment: [String: String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        process.qualityOfService = .userInitiated
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Run a process and return status/stdout/stderr.
    private func runProcessCaptureOutputWithStatus(_ executablePath: String, arguments: [String]) -> (status: Int32, stdout: String?, stderr: String?) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = makeProcessEnvironment(for: executablePath)
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.qualityOfService = .userInitiated
        do {
            try process.run()
            process.waitUntilExit()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: outputData, encoding: .utf8)
            let stderr = String(data: errorData, encoding: .utf8)
            return (process.terminationStatus, stdout, stderr)
        } catch {
            return (-1, nil, error.localizedDescription)
        }
    }

    /// Parse `surface:<id>` from cmux output (e.g. `OK surface:30 pane:29 workspace:4`).
    private func parseCmuxSurfaceRef(from output: String) -> String? {
        let tokens = output
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
        return tokens.first { $0.hasPrefix("surface:") }
    }

    /// Parse `workspace:<id>` from cmux output (e.g. `OK surface:30 pane:29 workspace:4`).
    private func parseCmuxWorkspaceRef(from output: String) -> String? {
        let tokens = output
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
        return tokens.first { $0.hasPrefix("workspace:") }
    }

    /// Build environment for subprocesses; enable cmux socket access from app-launched processes.
    private func makeProcessEnvironment(for executablePath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if executablePath.hasSuffix("/cmux") || executablePath == "cmux" {
            env["CMUX_SOCKET_MODE"] = "allowAll"
        }
        return env
    }

    /// Show a minimal warning when cmux socket mode blocks Forge automation.
    private func showCmuxAccessDeniedWarning() {
#if canImport(AppKit)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "cmux blocked Forge automation"
            alert.informativeText = "Set cmux Socket Control Mode to Automation mode, Password mode, or Full open mode."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
#endif
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
