import CryptoKit
import Foundation

/// Pure helpers used by the menubar CLI installer (escaping, file identity).
///
/// Kept in ForgeCore so unit tests do not need to link the Sparkle-dependent
/// `forge-menubar` executable.
public enum ForgeCliInstallerInternals {
    /// Returns true when `destination` is a symlink that resolves to `embedded`.
    public static func pointsToEmbeddedCli(destination dest: URL, embedded: URL) -> Bool {
        let fm = FileManager.default
        guard let resolved = try? fm.destinationOfSymbolicLink(atPath: dest.path) else { return false }
        // `destinationOfSymbolicLink` may be relative.
        let absolute: String
        if resolved.hasPrefix("/") {
            absolute = (resolved as NSString).standardizingPath
        } else {
            let base = dest.deletingLastPathComponent().path
            absolute = ((base as NSString).appendingPathComponent(resolved) as NSString).standardizingPath
        }
        return absolute == (embedded.path as NSString).standardizingPath
    }

    /// Returns true when both URLs are regular files of equal size and identical SHA-256 content.
    public static func isIdenticalFile(destination dest: URL, embedded: URL) -> Bool {
        let fm = FileManager.default
        guard let a = try? fm.attributesOfItem(atPath: dest.path),
              let b = try? fm.attributesOfItem(atPath: embedded.path),
              let atype = a[.type] as? FileAttributeType,
              let btype = b[.type] as? FileAttributeType,
              atype == .typeRegular,
              btype == .typeRegular,
              let asz = a[.size] as? NSNumber,
              let bsz = b[.size] as? NSNumber,
              asz.intValue == bsz.intValue else { return false }

        guard let ah = sha256(url: dest),
              let bh = sha256(url: embedded) else { return false }
        return ah == bh
    }

    /// SHA-256 digest of file contents, or `nil` if the file cannot be read.
    public static func sha256(url: URL) -> Data? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        var hasher = SHA256()
        while true {
            let chunk: Data? = (try? fh.read(upToCount: 1024 * 1024)) ?? nil
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return Data(digest)
    }

    /// Conservative single-quote shell escaping.
    public static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// AppleScript double-quoted string literal with escapes for `\` and `"`.
    public static func appleScriptStringLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
