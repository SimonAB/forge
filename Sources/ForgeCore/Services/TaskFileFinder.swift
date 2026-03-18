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
    /// The root path is normalised (standardised, no trailing slash) so enumeration is consistent.
    ///
    /// - Parameters:
    ///   - root: Directory path to search under.
    ///   - maxFiles: If set, stop after collecting this many files (default: nil = no limit).
    ///   - maxDepth: If set, do not descend beyond this depth relative to root; 0 = root only (default: nil = no limit).
    public static func findAll(
        under root: String,
        maxFiles: Int? = nil,
        maxDepth: Int? = nil
    ) -> [TaskFile] {
        let fm = FileManager.default
        var normalisedRoot = (root as NSString).standardizingPath
        if normalisedRoot.hasSuffix("/") {
            normalisedRoot = String(normalisedRoot.dropLast())
        }

        let skipNames: Set<String> = [
            ".build", ".git", "node_modules", ".Trash",
            "Library", ".cursor", ".cargo", ".rustup",
        ]

        let rootURL = URL(fileURLWithPath: normalisedRoot, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootComponents = rootURL.pathComponents
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [TaskFile] = []

        for case let url as URL in enumerator {
            if let cap = maxFiles, results.count >= cap { break }

            let standardURL = url.standardizedFileURL.resolvingSymlinksInPath()
            let resourceValues = try? standardURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory == true

            let components = standardURL.pathComponents
            if components.count < rootComponents.count || Array(components.prefix(rootComponents.count)) != rootComponents {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }

            // Relative path components (depth relative to rootURL).
            let relativeComponents = Array(components.dropFirst(rootComponents.count))
            let depth = relativeComponents.count
            let relativeParts = relativeComponents.filter { $0 != "/" }

            if relativeParts.contains(where: { part in
                part.hasPrefix(".") || skipNames.contains(part)
            }) {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            if let maxD = maxDepth, depth > maxD {
                if isDirectory {
                    enumerator.skipDescendants()
                }
                continue
            }

            let name = standardURL.lastPathComponent
            guard name == "TASKS.md" else { continue }

            let fullPath = standardURL.path
            let dirPath = (fullPath as NSString).deletingLastPathComponent
            let label = (dirPath as NSString).lastPathComponent
            results.append(TaskFile(path: fullPath, label: label))
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
