import AppKit
import CryptoKit
import Foundation

/// Installs the embedded `forge` CLI from inside Forge.app onto the user's PATH.
///
/// The CLI is bundled at `Forge.app/Contents/Resources/bin/forge` by the packaging script.
@MainActor
enum ForgeCliInstaller {

    enum InstallTarget: String, CaseIterable {
        case userBin
        case usrLocalBin

        var displayTitle: String {
            switch self {
            case .userBin: return "Install to ~/bin (recommended)"
            case .usrLocalBin: return "Install to /usr/local/bin (admin)"
            }
        }
    }

    enum InstallerError: Error, CustomStringConvertible {
        case embeddedCliMissing
        case cannotCreateUserBinDirectory(String)
        case destinationExistsButIsNotForge(String)
        case operationFailed(String)

        var description: String {
            switch self {
            case .embeddedCliMissing:
                return "Embedded forge CLI not found in this app bundle."
            case .cannotCreateUserBinDirectory(let path):
                return "Could not create directory: \(path)"
            case .destinationExistsButIsNotForge(let path):
                return "Refusing to modify existing \(path) because it does not appear to be Forge’s CLI."
            case .operationFailed(let message):
                return message
            }
        }
    }

    static func embeddedCliURL() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("bin/forge")
    }

    static func embeddedCliPathString() -> String {
        embeddedCliURL()?.path ?? "Not bundled"
    }

    static func destinationURL(for target: InstallTarget) -> URL {
        switch target {
        case .userBin:
            let home = FileManager.default.homeDirectoryForCurrentUser
            return home.appendingPathComponent("bin/forge")
        case .usrLocalBin:
            return URL(fileURLWithPath: "/usr/local/bin/forge")
        }
    }

    static func install(to target: InstallTarget, allowOverwrite: Bool = false) throws {
        guard let embedded = embeddedCliURL(),
              FileManager.default.isExecutableFile(atPath: embedded.path) else {
            throw InstallerError.embeddedCliMissing
        }

        let dest = destinationURL(for: target)
        switch target {
        case .userBin:
            try installUserBin(embedded: embedded, destination: dest, allowOverwrite: allowOverwrite)
        case .usrLocalBin:
            try installUsrLocalBinViaAppleScript(embedded: embedded, destination: dest, allowOverwrite: allowOverwrite)
        }
    }

    static func uninstall(from target: InstallTarget) throws {
        guard let embedded = embeddedCliURL() else {
            throw InstallerError.embeddedCliMissing
        }
        let dest = destinationURL(for: target)
        switch target {
        case .userBin:
            try uninstallUserBin(embedded: embedded, destination: dest)
        case .usrLocalBin:
            try uninstallUsrLocalBinViaAppleScript(embedded: embedded, destination: dest)
        }
    }

    // MARK: - User install (no admin)

    private static func installUserBin(embedded: URL, destination dest: URL, allowOverwrite: Bool) throws {
        let fm = FileManager.default
        let binDir = dest.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        } catch {
            throw InstallerError.cannotCreateUserBinDirectory(binDir.path)
        }

        if fm.fileExists(atPath: dest.path) {
            guard allowOverwrite || pointsToEmbeddedCli(destination: dest, embedded: embedded) || isIdenticalFile(destination: dest, embedded: embedded) else {
                throw InstallerError.destinationExistsButIsNotForge(dest.path)
            }
            try? fm.removeItem(at: dest)
        }

        do {
            try fm.createSymbolicLink(at: dest, withDestinationURL: embedded)
        } catch {
            // Fall back to copy.
            do {
                try fm.copyItem(at: embedded, to: dest)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
            } catch {
                throw InstallerError.operationFailed("Could not install forge to \(dest.path).")
            }
        }
    }

    private static func uninstallUserBin(embedded: URL, destination dest: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dest.path) else { return }

        if pointsToEmbeddedCli(destination: dest, embedded: embedded) || isIdenticalFile(destination: dest, embedded: embedded) {
            try fm.removeItem(at: dest)
            return
        }
        throw InstallerError.destinationExistsButIsNotForge(dest.path)
    }

    // MARK: - System install (admin) via AppleScript

    private static func installUsrLocalBinViaAppleScript(embedded: URL, destination dest: URL, allowOverwrite: Bool) throws {
        // Avoid touching an unrelated binary unless explicitly overwriting.
        if FileManager.default.fileExists(atPath: dest.path), !allowOverwrite {
            if !(pointsToEmbeddedCli(destination: dest, embedded: embedded) || isIdenticalFile(destination: dest, embedded: embedded)) {
                throw InstallerError.destinationExistsButIsNotForge(dest.path)
            }
        }
        let cmd = """
        mkdir -p /usr/local/bin && ln -sf \(shellEscape(embedded.path)) \(shellEscape(dest.path))
        """
        try runPrivilegedShell(command: cmd, prompt: "Forge would like to install the 'forge' command-line tool.")
    }

    private static func uninstallUsrLocalBinViaAppleScript(embedded: URL, destination dest: URL) throws {
        // Only remove if it appears to be ours.
        if FileManager.default.fileExists(atPath: dest.path) {
            if !(pointsToEmbeddedCli(destination: dest, embedded: embedded) || isIdenticalFile(destination: dest, embedded: embedded)) {
                throw InstallerError.destinationExistsButIsNotForge(dest.path)
            }
        } else {
            return
        }
        let cmd = "rm -f \(shellEscape(dest.path))"
        try runPrivilegedShell(command: cmd, prompt: "Forge would like to remove the 'forge' command-line tool.")
    }

    private static func runPrivilegedShell(command: String, prompt: String) throws {
        let script = """
        do shell script \(appleScriptStringLiteral(command)) with administrator privileges with prompt \(appleScriptStringLiteral(prompt))
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String)
                ?? "Authorisation failed."
            if let number = error[NSAppleScript.errorNumber] as? Int {
                throw InstallerError.operationFailed("\(message) (AppleScript error \(number))")
            }
            throw InstallerError.operationFailed(message)
        }
        _ = result
    }

    // MARK: - Identification

    private static func pointsToEmbeddedCli(destination dest: URL, embedded: URL) -> Bool {
        ForgeCliInstallerInternals.pointsToEmbeddedCli(destination: dest, embedded: embedded)
    }

    private static func isIdenticalFile(destination dest: URL, embedded: URL) -> Bool {
        ForgeCliInstallerInternals.isIdenticalFile(destination: dest, embedded: embedded)
    }

    // MARK: - Escaping

    private static func shellEscape(_ s: String) -> String {
        ForgeCliInstallerInternals.shellEscape(s)
    }

    private static func appleScriptStringLiteral(_ s: String) -> String {
        ForgeCliInstallerInternals.appleScriptStringLiteral(s)
    }
}

// MARK: - Internals (SPI for tests)

@_spi(Testing)
public enum ForgeCliInstallerInternals {
    static func pointsToEmbeddedCli(destination dest: URL, embedded: URL) -> Bool {
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

    static func isIdenticalFile(destination dest: URL, embedded: URL) -> Bool {
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

    static func sha256(url: URL) -> Data? {
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

    static func shellEscape(_ s: String) -> String {
        // Conservative single-quote escaping.
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptStringLiteral(_ s: String) -> String {
        // AppleScript string uses double quotes; escape backslashes and quotes.
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
