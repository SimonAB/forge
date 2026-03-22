import AppKit
import Foundation

/// Replaces `/Applications/Forge.app` using AppleScript `do shell script … with administrator privileges`.
enum AppPrivilegedInstaller {

    /// Runs `ditto` then clears quarantine on the installed app.
    static func installForgeApp(from sourceAppURL: URL) throws {
        let src = sourceAppURL.path
        let dst = "/Applications/Forge.app"
        let script = appleScriptDittoAndQuarantine(srcPOSIX: src, dstPOSIX: dst)
        var errorDict: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw PrivilegedInstallError.scriptCreationFailed
        }
        _ = appleScript.executeAndReturnError(&errorDict)
        if let errorDict,
           let number = errorDict["NSAppleScriptErrorNumber"] as? Int,
           number != 0 {
            let message = errorDict["NSAppleScriptErrorMessage"] as? String ?? "Installation was cancelled or failed."
            throw PrivilegedInstallError.appleScriptFailed(message)
        }
    }

    /// AppleScript string contents for `src` / `dst` paths embedded in `set … to "…"`.
    private static func appleScriptDittoAndQuarantine(srcPOSIX: String, dstPOSIX: String) -> String {
        let srcLit = escapeForAppleScriptStringLiteral(srcPOSIX)
        let dstLit = escapeForAppleScriptStringLiteral(dstPOSIX)
        return """
        set srcPosix to "\(srcLit)"
        set dstPosix to "\(dstLit)"
        do shell script "/usr/bin/ditto -rsrc " & quoted form of srcPosix & " " & quoted form of dstPosix & " && /usr/bin/xattr -cr " & quoted form of dstPosix with administrator privileges
        """
    }

    private static func escapeForAppleScriptStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum PrivilegedInstallError: LocalizedError {
    case scriptCreationFailed
    case appleScriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptCreationFailed:
            return "Could not prepare the installation script."
        case .appleScriptFailed(let message):
            return message
        }
    }
}
