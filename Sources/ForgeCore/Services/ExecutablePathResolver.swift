import Foundation

/// Resolves command-line tools for GUI apps whose process `PATH` is often minimal.
///
/// Finder/Dock-launched apps typically inherit `/usr/bin:/bin:/usr/sbin:/sbin` and miss
/// Homebrew and user install prefixes (`~/bin`, `~/.local/bin`). This type builds a
/// search path that matches common interactive-shell layouts without spawning a login shell.
public enum ExecutablePathResolver: Sendable {
    /// Directories commonly present on an interactive macOS shell `PATH` but absent from GUI apps.
    public static func standardExtraDirectories(home: String = NSHomeDirectory()) -> [String] {
        let homeNS = home as NSString
        return [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            homeNS.appendingPathComponent("bin"),
            homeNS.appendingPathComponent(".local/bin"),
            homeNS.appendingPathComponent(".cargo/bin"),
        ]
    }

    /// Merge `extraDirectories` ahead of `basePATH`, preserving first-occurrence order.
    public static func augmentedPATH(
        basePATH: String? = ProcessInfo.processInfo.environment["PATH"],
        extraDirectories: [String] = standardExtraDirectories()
    ) -> String {
        let existing = (basePATH ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        var ordered: [String] = []
        for dir in extraDirectories + existing {
            if seen.insert(dir).inserted {
                ordered.append(dir)
            }
        }
        return ordered.joined(separator: ":")
    }

    /// Locate an executable by name on an augmented `PATH`.
    ///
    /// - Parameters:
    ///   - name: Command name (for example `hermes` or `forge`).
    ///   - basePATH: Process `PATH` to extend; defaults to the current process environment.
    ///   - extraDirectories: Prefix directories; defaults to ``standardExtraDirectories()``.
    ///   - additionalCandidates: Absolute paths tried after the search path (for example an embedded CLI).
    /// - Returns: The first executable path found, or `nil`.
    public static func find(
        named name: String,
        basePATH: String? = ProcessInfo.processInfo.environment["PATH"],
        extraDirectories: [String] = standardExtraDirectories(),
        additionalCandidates: [String] = [],
        fileManager: FileManager = .default
    ) -> String? {
        let path = augmentedPATH(basePATH: basePATH, extraDirectories: extraDirectories)
        for dir in path.split(separator: ":").map(String.init) {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        for candidate in additionalCandidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
    }

    /// Absolute path of the `forge` CLI bundled inside Forge.app, when present.
    public static func embeddedForgeCLIPath(
        fileManager: FileManager = .default
    ) -> String? {
        let path = "/Applications/Forge.app/Contents/Resources/bin/forge"
        return fileManager.isExecutableFile(atPath: path) ? path : nil
    }
}
