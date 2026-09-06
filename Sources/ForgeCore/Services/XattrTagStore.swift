import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Tag store using `user.xdg.tags` (comma-separated), for Linux painters and tests.
///
/// Tag strings match Forge `board.columns[].tag` / `meta_tags` so the same sidecar
/// paints correctly on both OSes.
public struct XattrTagStore: TagWriting, Sendable {
    public static let xattrName = "user.xdg.tags"

    public init() {}

    public func tags(at path: String) -> [String] {
        (try? readTags(at: path)) ?? []
    }

    public func tags(at path: String) async -> [String] {
        (try? readTags(at: path)) ?? []
    }

    /// Read `user.xdg.tags` as a CSV of tag names.
    public func readTags(at path: String) throws -> [String] {
        let size = xattrGetSize(path: path, name: Self.xattrName)
        if size < 0 {
            if isMissingXattrError(errno) { return [] }
            throw TagStoreError.writeFailed(path: path, errno: errno)
        }
        if size == 0 { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = buffer.withUnsafeMutableBytes { raw in
            xattrGet(path: path, name: Self.xattrName, buffer: raw.baseAddress, size: size)
        }
        guard read >= 0 else {
            if isMissingXattrError(errno) { return [] }
            throw TagStoreError.writeFailed(path: path, errno: errno)
        }
        let data = Data(buffer.prefix(read))
        guard let string = String(data: data, encoding: .utf8) else { return [] }
        return string
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func writeTags(_ tags: [String], at path: String) throws {
        if tags.isEmpty {
            let result = xattrRemove(path: path, name: Self.xattrName)
            if result != 0, !isMissingXattrError(errno) {
                throw TagStoreError.writeFailed(path: path, errno: errno)
            }
            return
        }
        let joined = tags.joined(separator: ",")
        guard let data = joined.data(using: .utf8) else {
            throw TagStoreError.writeFailed(path: path, errno: EINVAL)
        }
        let result = data.withUnsafeBytes { buffer in
            xattrSet(path: path, name: Self.xattrName, buffer: buffer.baseAddress, size: buffer.count)
        }
        guard result == 0 else {
            throw TagStoreError.writeFailed(path: path, errno: errno)
        }
    }

    public func addTag(_ tag: String, at path: String) throws {
        var existing = try readTags(at: path)
        guard !existing.contains(tag) else { return }
        existing.append(tag)
        try writeTags(existing, at: path)
    }

    public func removeTag(_ tag: String, at path: String) throws {
        var existing = try readTags(at: path)
        guard let index = existing.firstIndex(of: tag) else { return }
        existing.remove(at: index)
        try writeTags(existing, at: path)
    }
}

// MARK: - Platform xattr wrappers

private func isMissingXattrError(_ code: Int32) -> Bool {
    #if os(Linux)
    return code == ENODATA
    #else
    return code == ENOATTR
    #endif
}

private func xattrGetSize(path: String, name: String) -> Int {
    #if os(Linux)
    return getxattr(path, name, nil, 0)
    #else
    return getxattr(path, name, nil, 0, 0, 0)
    #endif
}

private func xattrGet(path: String, name: String, buffer: UnsafeMutableRawPointer?, size: Int) -> Int {
    #if os(Linux)
    return getxattr(path, name, buffer, size)
    #else
    return getxattr(path, name, buffer, size, 0, 0)
    #endif
}

private func xattrSet(path: String, name: String, buffer: UnsafeRawPointer?, size: Int) -> Int32 {
    #if os(Linux)
    return setxattr(path, name, buffer, size, 0)
    #else
    return setxattr(path, name, buffer, size, 0, 0)
    #endif
}

private func xattrRemove(path: String, name: String) -> Int32 {
    #if os(Linux)
    return removexattr(path, name)
    #else
    return removexattr(path, name, 0)
    #endif
}
