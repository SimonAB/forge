import ArgumentParser
import Foundation
import ForgeCore

struct LintCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Lint and optionally fix task markdown files for best practices."
    )

    @Flag(name: .long, help: "Apply fixes (add missing IDs, normalise checkbox casing, trailing newline).")
    var fix: Bool = false

    @Option(name: .long, help: "Report only this severity or higher: error, warning.")
    var severity: String?

    @Argument(help: "Optional paths to lint (file or directory). If omitted, all task files from config are used.")
    var pathArguments: [String] = []

    mutating func run() async throws {
        let config = try ConfigLoader.load()
        let forgeDir = ConfigLoader.forgeDirectory(for: config)

        var allPaths: [String] = []

        if pathArguments.isEmpty {
            for (path, _) in ConfigLoader.allTaskFilesInTaskRoot(forgeDir: forgeDir) {
                // Skip generated summaries such as due.md.
                if (path as NSString).lastPathComponent == "due.md" { continue }
                allPaths.append(path)
            }
            let scanner = WorkspaceScanner(config: config)
            let projects = try await scanner.scanProjects()
            let fm = FileManager.default
            for project in projects {
                let tasksPath = (project.path as NSString).appendingPathComponent("TASKS.md")
                if fm.fileExists(atPath: tasksPath) {
                    allPaths.append(tasksPath)
                }
            }
        } else {
            let fm = FileManager.default
            for inputPath in pathArguments {
                var resolved = (inputPath as NSString).expandingTildeInPath
                if resolved.hasSuffix("/") { resolved = String(resolved.dropLast()) }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: resolved, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    for tf in TaskFileFinder.findAll(under: resolved) {
                        allPaths.append(tf.path)
                    }
                } else if resolved.hasSuffix(".md") {
                    allPaths.append(resolved)
                }
            }
        }

        let paths = Array(Set(allPaths)).sorted()

        let linter = TaskFileLinter()
        var totalErrors = 0
        var totalWarnings = 0
        var fixedCount = 0

        let minSeverity: TaskFileLinter.Issue.Severity? = severity.flatMap { s in
            switch s.lowercased() {
            case "error": return .error
            case "warning": return .warning
            default: return nil
            }
        }

        for path in paths {
            let issues = linter.lint(path: path)
            let filtered = issues.filter { issue in
                guard let min = minSeverity else { return true }
                switch (min, issue.severity) {
                case (.error, .error): return true
                case (.error, .warning): return false
                case (.warning, _): return true
                }
            }
            if filtered.isEmpty { continue }

            let relPath = path.hasPrefix(FileManager.default.currentDirectoryPath)
                ? String(path.dropFirst(FileManager.default.currentDirectoryPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                : path
            print("\(relPath)")
            for issue in filtered {
                switch issue.severity {
                case .error: totalErrors += 1
                case .warning: totalWarnings += 1
                }
                let sev = issue.severity == .error ? "error" : "warning"
                let fixHint = issue.fixable ? " (fixable)" : ""
                print("  \(issue.line):\(sev): \(issue.ruleID): \(issue.message)\(fixHint)")
            }
            print("")

            if fix {
                let hasFixable = filtered.contains(where: \.fixable)
                if hasFixable {
                    do {
                        if try linter.fix(path: path) {
                            fixedCount += 1
                            print("  Fixed.")
                        }
                    } catch {
                        print("  Fix failed: \(error)")
                    }
                }
            }
        }

        if totalErrors > 0 || totalWarnings > 0 {
            print("---")
            print("\(totalErrors) error(s), \(totalWarnings) warning(s)", terminator: "")
            if fix, fixedCount > 0 {
                print(", \(fixedCount) file(s) updated")
            } else {
                print("")
            }
        } else if paths.isEmpty {
            print("No task files found.")
        } else {
            print("No issues found.")
        }
    }
}
