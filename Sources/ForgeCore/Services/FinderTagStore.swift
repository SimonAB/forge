import Foundation

/// Reads and writes macOS Finder tags using Foundation for reading and the
/// com.apple.metadata:_kMDItemUserTags xattr for writing (portable across macOS versions).
public struct FinderTagStore: Sendable {

    private static let tagXattrName = "com.apple.metadata:_kMDItemUserTags"

    /// Default timeout when reading tags for paths that may be undownloaded (e.g. iCloud placeholders).
    public static let defaultAvailabilityTimeout: TimeInterval = 2.0

    public init() {}

    /// Read all Finder tag names from a file or directory at the given path.
    public func readTags(at path: String) throws -> [String] {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.tagNamesKey])
        return values.tagNames ?? []
    }

    /// Read tags only if the path responds within the timeout; returns nil on timeout or error.
    /// Use when scanning paths that may be undownloaded (e.g. iCloud placeholders) to avoid stalling.
    public func readTagsIfAvailable(at path: String, timeout: TimeInterval = defaultAvailabilityTimeout) -> [String]? {
        final class ResultBox: @unchecked Sendable {
            var tags: [String]?
        }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        let url = URL(fileURLWithPath: path)
        DispatchQueue.global(qos: .utility).async {
            let values = try? url.resourceValues(forKeys: [.tagNamesKey])
            box.tags = values?.tagNames ?? []
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return nil
        }
        return box.tags ?? []
    }

    /// Write Finder tags to a file or directory, replacing all existing tags.
    /// Uses the binary plist xattr directly for cross-version compatibility.
    public func writeTags(_ tags: [String], at path: String) throws {
        let plistArray = tags as NSArray
        let data = try PropertyListSerialization.data(
            fromPropertyList: plistArray, format: .binary, options: 0
        )
        let result = data.withUnsafeBytes { buffer in
            setxattr(path, Self.tagXattrName, buffer.baseAddress, buffer.count, 0, 0)
        }
        guard result == 0 else {
            throw TagError.writeFailed(path: path, errno: errno)
        }
    }

    /// Add a single tag, preserving existing tags. No-op if already present.
    public func addTag(_ tag: String, at path: String) throws {
        var existing = try readTags(at: path)
        guard !existing.contains(tag) else { return }
        existing.append(tag)
        try writeTags(existing, at: path)
    }

    /// Remove a single tag. No-op if not present.
    public func removeTag(_ tag: String, at path: String) throws {
        var existing = try readTags(at: path)
        guard let index = existing.firstIndex(of: tag) else { return }
        existing.remove(at: index)
        try writeTags(existing, at: path)
    }

    /// Replace one tag with another. Preserves tag order and other tags.
    public func replaceTag(_ oldTag: String, with newTag: String, at path: String) throws {
        var existing = try readTags(at: path)
        if let index = existing.firstIndex(of: oldTag) {
            existing[index] = newTag
        } else {
            existing.append(newTag)
        }
        try writeTags(existing, at: path)
    }

    /// Apply tag aliases: replace any aliased tags with their canonical form.
    /// Returns the list of replacements made as (old, new) pairs.
    /// When `timeout` is set, uses a non-blocking read; returns empty on timeout (e.g. undownloaded cloud path).
    @discardableResult
    public func applyAliases(
        _ aliases: [String: String], at path: String, timeout: TimeInterval? = nil
    ) throws -> [(old: String, new: String)] {
        var tags: [String]
        if let t = timeout {
            guard let available = readTagsIfAvailable(at: path, timeout: t) else { return [] }
            tags = available
        } else {
            tags = try readTags(at: path)
        }
        var replacements: [(old: String, new: String)] = []

        for (index, tag) in tags.enumerated() {
            if let canonical = aliases[tag], canonical != tag {
                tags[index] = canonical
                replacements.append((old: tag, new: canonical))
            }
        }

        if !replacements.isEmpty {
            try writeTags(tags, at: path)
        }
        return replacements
    }

    enum TagError: Error, CustomStringConvertible {
        case writeFailed(path: String, errno: Int32)

        var description: String {
            switch self {
            case .writeFailed(let path, let code):
                return "Failed to write tags to '\(path)': \(String(cString: strerror(code)))"
            }
        }
    }
}
