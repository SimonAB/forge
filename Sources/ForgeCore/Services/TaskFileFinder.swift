import Foundation

/// Recursively locates TASKS.md files and area markdown files across a directory tree.
///
/// Unlike `WorkspaceScanner` (which reads one level of project directories),
/// this finder walks the entire tree rooted at `~/Documents`, surfacing TASKS.md
/// files regardless of nesting depth.
public struct TaskFileFinder: Sendable {

    /// A located task file with its inferred project label.
    public struct TaskFile: Sendable {
        public let path: String
        public let label: String
    }

    /// Find all TASKS.md files recursively under the given root directory.
    ///
    /// Hidden directories (`.` prefix) and build artefacts (`.build`, `node_modules`)
    /// are skipped for performance. Does not use skipsPackageDescendants, so TASKS.md
    /// inside Swift packages (e.g. projects containing Package.swift) are still found.
    public static func findAll(under root: String) -> [TaskFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: []
        ) else { return [] }

        let skipNames: Set<String> = [
            ".build", ".git", "node_modules", ".Trash",
            "Library", ".cursor", ".cargo", ".rustup",
        ]

        var results: [TaskFile] = []

        for case let url as URL in enumerator {
            let name = url.lastPathComponent

            if name.hasPrefix(".") || skipNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            guard name == "TASKS.md" else { continue }

            let dirURL = url.deletingLastPathComponent()
            let label = dirURL.lastPathComponent
            results.append(TaskFile(path: url.path, label: label))
        }

        return results
    }

    /// Convenience: find all TASKS.md files under `~/Documents`.
    public static func findAllUnderDocuments() -> [TaskFile] {
        let home = NSHomeDirectory()
        let docs = (home as NSString).appendingPathComponent("Documents")
        return findAll(under: docs)
    }
}
