import Foundation

/// Read/write tag store used by the kanban nexus (Finder on macOS, xattr on Linux, memory in tests).
public protocol TagWriting: TagReading {
    /// Replace all tags at `path`.
    func writeTags(_ tags: [String], at path: String) throws
    /// Add a tag if missing.
    func addTag(_ tag: String, at path: String) throws
    /// Remove a tag if present.
    func removeTag(_ tag: String, at path: String) throws
}

extension FinderTagStore: TagWriting {}

extension InMemoryTagStore: TagWriting {
    public func writeTags(_ tags: [String], at path: String) throws {
        setTags(tags, at: path)
    }

    public func addTag(_ tag: String, at path: String) throws {
        var existing = tags(at: path)
        guard !existing.contains(tag) else { return }
        existing.append(tag)
        setTags(existing, at: path)
    }

    public func removeTag(_ tag: String, at path: String) throws {
        var existing = tags(at: path)
        guard let index = existing.firstIndex(of: tag) else { return }
        existing.remove(at: index)
        setTags(existing, at: path)
    }
}

/// Selects the platform-appropriate tag store.
public enum PlatformTagStore {
    /// Finder tags on Apple platforms; `user.xdg.tags` on Linux.
    public static func makeDefault() -> any TagWriting {
        #if os(Linux)
        return XattrTagStore()
        #else
        return FinderTagStore()
        #endif
    }
}
