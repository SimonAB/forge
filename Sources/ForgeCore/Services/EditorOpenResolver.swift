import Foundation

/// Absolute paths for opening a file or folder in the terminal editor.
public struct EditorOpenTarget: Equatable, Sendable {
    /// Absolute file or directory path passed to the editor.
    public let filePath: String
    /// Directory used as the editor session working directory.
    public let workingDirectory: String

    public init(filePath: String, workingDirectory: String) {
        self.filePath = filePath
        self.workingDirectory = workingDirectory
    }
}

/// Resolves CLI / Finder paths into editor launch targets.
public enum EditorOpenResolver {

    /// Expand and validate paths into editor targets.
    ///
    /// Empty `paths` resolves to the current user’s home directory (useful when an
    /// Automator app is launched with no dropped files).
    ///
    /// - Parameters:
    ///   - paths: Raw path arguments (may be empty).
    ///   - homeDirectory: Fallback when `paths` is empty.
    ///   - fileManager: Existence / directory checks.
    /// - Returns: Absolute file path + working directory pairs.
    /// - Throws: `EditorOpenError.pathNotFound` when a path does not exist.
    public static func resolveTargets(
        paths: [String],
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        fileManager: FileManager = .default
    ) throws -> [EditorOpenTarget] {
        let raw = paths.isEmpty ? [homeDirectory] : paths
        var targets: [EditorOpenTarget] = []
        for path in raw {
            let expanded = (path as NSString).expandingTildeInPath
            let standardized = (expanded as NSString).standardizingPath
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardized, isDirectory: &isDirectory) else {
                throw EditorOpenError.pathNotFound(path)
            }
            if isDirectory.boolValue {
                targets.append(EditorOpenTarget(filePath: standardized, workingDirectory: standardized))
            } else {
                let parent = (standardized as NSString).deletingLastPathComponent
                targets.append(EditorOpenTarget(filePath: standardized, workingDirectory: parent))
            }
        }
        return targets
    }
}

/// Errors from resolving editor open paths.
public enum EditorOpenError: Error, Equatable, CustomStringConvertible, Sendable {
    case pathNotFound(String)

    public var description: String {
        switch self {
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        }
    }
}
