import Foundation

/// Paths used when wiring Forge into Hermes.
public enum HermesPaths: Sendable {
    /// Default Forge home when not otherwise configured.
    public static let defaultForgeHome: String = {
        (NSHomeDirectory() as NSString).appendingPathComponent("Documents/Forge")
    }()

    /// Hermes user config file.
    public static let hermesConfigPath: String = {
        (NSHomeDirectory() as NSString).appendingPathComponent(".hermes/config.yaml")
    }()

    /// Relative skills directory inside a Forge home.
    public static let skillsRelativePath = ".hermes/skills"

    /// Absolute skills directory for a Forge home.
    public static func skillsDirectory(forgeHome: String) -> String {
        (forgeHome as NSString).appendingPathComponent(skillsRelativePath)
    }
}

/// Result of a single Hermes integration check.
public struct HermesSetupCheck: Sendable, Equatable {
    public let label: String
    public let passed: Bool
    public let detail: String

    public init(label: String, passed: Bool, detail: String) {
        self.label = label
        self.passed = passed
        self.detail = detail
    }
}

/// Aggregated Hermes + Forge setup status for Preferences and diagnostics.
public struct HermesSetupStatus: Sendable, Equatable {
    public let checks: [HermesSetupCheck]

    public init(checks: [HermesSetupCheck]) {
        self.checks = checks
    }

    /// True when every check passed.
    public var isReady: Bool {
        checks.allSatisfy(\.passed)
    }
}

/// Reads Hermes config and probes local prerequisites (Ollama, Hermes CLI, forge, skill wiring).
public struct HermesSetupProbe: Sendable {
    public struct Options: Sendable {
        public let forgeHome: String
        public let hermesConfigPath: String
        public let ollamaTagsURL: URL
        public let probeSkillVisibility: Bool
        public let urlSession: URLSession

        public init(
            forgeHome: String = HermesPaths.defaultForgeHome,
            hermesConfigPath: String = HermesPaths.hermesConfigPath,
            ollamaTagsURL: URL = URL(string: "http://127.0.0.1:11434/api/tags")!,
            probeSkillVisibility: Bool = true,
            urlSession: URLSession? = nil
        ) {
            self.forgeHome = forgeHome
            self.hermesConfigPath = hermesConfigPath
            self.ollamaTagsURL = ollamaTagsURL
            self.probeSkillVisibility = probeSkillVisibility
            if let urlSession {
                self.urlSession = urlSession
            } else {
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 3
                config.timeoutIntervalForResource = 3
                self.urlSession = URLSession(configuration: config)
            }
        }
    }

    private let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    /// Run all setup checks.
    public func probe() async -> HermesSetupStatus {
        let skillsDir = HermesPaths.skillsDirectory(forgeHome: options.forgeHome)
        let configText = (try? String(contentsOfFile: options.hermesConfigPath, encoding: .utf8)) ?? ""
        let configured = HermesConfigParser.externalDirsContainForgeSkills(
            configText: configText,
            expectedSkillsDirectory: skillsDir
        )

        var checks: [HermesSetupCheck] = []
        let ollamaOK = await ollamaReachable()
        checks.append(HermesSetupCheck(
            label: "Ollama reachable (loopback)",
            passed: ollamaOK,
            detail: options.ollamaTagsURL.absoluteString
        ))

        let hermesPath = Self.executablePath(named: "hermes")
        checks.append(HermesSetupCheck(
            label: "Hermes on PATH",
            passed: hermesPath != nil,
            detail: hermesPath ?? "Install Hermes and add it to PATH"
        ))

        let forgePath = Self.executablePath(named: "forge")
            ?? Self.embeddedForgeCliPath()
        checks.append(HermesSetupCheck(
            label: "forge on PATH",
            passed: Self.executablePath(named: "forge") != nil,
            detail: forgePath ?? "Forge → Preferences → Install CLI…"
        ))

        checks.append(HermesSetupCheck(
            label: "Forge skills directory",
            passed: FileManager.default.fileExists(atPath: skillsDir),
            detail: skillsDir
        ))

        checks.append(HermesSetupCheck(
            label: "Hermes skill configured",
            passed: configured,
            detail: configured ? skillsDir : "Run scripts/setup-hermes-forge.py"
        ))

        if options.probeSkillVisibility, let hermes = hermesPath {
            let visible = Self.hermesListsSkill(hermesPath: hermes, skillName: "forge-board")
            checks.append(HermesSetupCheck(
                label: "forge-board skill visible",
                passed: visible,
                detail: visible ? "forge-board" : "Restart Hermes after setup if needed"
            ))
        }

        return HermesSetupStatus(checks: checks)
    }

    private func ollamaReachable() async -> Bool {
        var request = URLRequest(url: options.ollamaTagsURL)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await options.urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private static func executablePath(named name: String) -> String? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for dir in paths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func embeddedForgeCliPath() -> String? {
        let path = "/Applications/Forge.app/Contents/Resources/bin/forge"
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private static func hermesListsSkill(hermesPath: String, skillName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: hermesPath)
        process.arguments = ["skills", "list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        guard process.terminationStatus == 0 else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(skillName)
    }
}

/// Minimal parser for `skills.external_dirs` in Hermes config YAML.
public enum HermesConfigParser: Sendable {
    /// Parse `skills.external_dirs` entries from Hermes config text.
    public static func parseExternalDirs(configText: String) -> [String] {
        let lines = configText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inSkills = false
        var inExternal = false
        var dirs: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inSkills {
                if trimmed == "skills:" {
                    inSkills = true
                }
                continue
            }
            if !inExternal {
                if trimmed == "external_dirs: []" {
                    return []
                }
                if trimmed == "external_dirs:" {
                    inExternal = true
                    continue
                }
                if trimmed.hasPrefix("external_dirs: [") {
                    let inner = trimmed
                        .replacingOccurrences(of: "external_dirs: [", with: "")
                        .replacingOccurrences(of: "]", with: "")
                    for part in inner.split(separator: ",") {
                        let cleaned = part.trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                        if !cleaned.isEmpty {
                            dirs.append(cleaned)
                        }
                    }
                    return dirs
                }
                if !trimmed.isEmpty, !line.hasPrefix(" "), !trimmed.hasPrefix("#") {
                    break
                }
                continue
            }
            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if !item.isEmpty {
                    dirs.append(item)
                }
                continue
            }
            if !trimmed.isEmpty, !line.hasPrefix(" ") {
                break
            }
        }
        return dirs
    }

    /// Return true when `expectedSkillsDirectory` is listed under skills.external_dirs.
    public static func externalDirsContainForgeSkills(
        configText: String,
        expectedSkillsDirectory: String
    ) -> Bool {
        let expected = URL(fileURLWithPath: expectedSkillsDirectory).standardizedFileURL.path
        return parseExternalDirs(configText: configText).contains { entry in
            URL(fileURLWithPath: entry).standardizedFileURL.path == expected
        }
    }
}
