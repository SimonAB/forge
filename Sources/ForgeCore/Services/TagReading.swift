import Foundation

/// Read-only view of Finder (or substitute) tags used when scanning for projects.
///
/// Production code uses ``FinderTagStore``. Tests can inject an in-memory store so
/// CI does not depend on macOS Finder xattr behaviour.
public protocol TagReading: Sendable {
    /// Return tags for `path`, or an empty list when unavailable.
    func tags(at path: String) -> [String]

    /// Async variant for non-blocking scans.
    func tags(at path: String) async -> [String]
}

extension FinderTagStore: TagReading {
    public func tags(at path: String) -> [String] {
        readTagsIfAvailable(at: path) ?? []
    }

    public func tags(at path: String) async -> [String] {
        await readTagsIfAvailable(at: path) ?? []
    }
}

/// In-memory tag map for tests and offline tooling (single-writer / single-reader safe).
public final class InMemoryTagStore: TagReading, @unchecked Sendable {
    private var tagsByPath: [String: [String]]

    public init(tagsByPath: [String: [String]] = [:]) {
        self.tagsByPath = tagsByPath
    }

    /// Replace tags stored for `path`.
    public func setTags(_ tags: [String], at path: String) {
        tagsByPath[path] = tags
    }

    public func tags(at path: String) -> [String] {
        tagsByPath[path] ?? []
    }

    public func tags(at path: String) async -> [String] {
        tagsByPath[path] ?? []
    }
}
