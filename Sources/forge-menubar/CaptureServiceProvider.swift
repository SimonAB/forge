import AppKit
import ForgeCore
import UserNotifications

/// macOS Services entry point: selected text, Finder files, or Mail messages → inbox.
final class CaptureServiceProvider: NSObject {

    func handlePasteboard(_ pboard: NSPasteboard) -> String {
        guard let forgeDir = Self.resolveForgeDir() else {
            return "No Forge config loaded."
        }

        var files: [String] = []
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            files = urls.filter(\.isFileURL).map(\.path)
        }

        let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)

        var args = ["service", "--source", "service", "--json"]
        for path in files {
            args += ["--file", path]
        }

        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let mailFront = frontApp == "com.apple.mail"
        if files.isEmpty && (mailFront || text == nil || text?.isEmpty == true) {
            args.append("--mail")
        } else if let text, !text.isEmpty, files.isEmpty {
            args += ["--text", text]
        } else if files.isEmpty {
            args.append("--mail")
        }

        do {
            let output = try CaptureScriptRunner.run(forgeDir: forgeDir, arguments: args)
            Self.notify(output)
            return output
        } catch {
            return error.localizedDescription
        }
    }

    @objc func captureToForgeInbox(
        _ pboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let result = handlePasteboard(pboard)
        if result.lowercased().contains("nothing to capture")
            || result.lowercased().contains("failed")
            || result.lowercased().contains("not found") {
            errorPointer.pointee = result as NSString
        }
    }

    @objc func captureMailToForgeInbox(
        _ pboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let forgeDir = Self.resolveForgeDir() else {
            errorPointer.pointee = "No Forge config loaded." as NSString
            return
        }
        do {
            let output = try CaptureScriptRunner.run(
                forgeDir: forgeDir,
                arguments: ["service", "--mail", "--source", "service", "--json"]
            )
            Self.notify(output)
        } catch let failure {
            errorPointer.pointee = failure.localizedDescription as NSString
        }
    }

    private static func notify(_ output: String) {
        let count: Int
        if let data = output.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let captured = obj["captured"] as? [[String: Any]] {
            count = captured.count
        } else {
            count = output.split(separator: "\n").filter { $0.hasPrefix("Captured ") }.count
        }
        let content = UNMutableNotificationContent()
        content.title = "Forge inbox"
        content.body = count == 1 ? "Captured 1 item." : "Captured \(max(count, 1)) item(s)."
        let request = UNNotificationRequest(
            identifier: "forge.capture.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func resolveForgeDir() -> String? {
        let home = NSHomeDirectory()
        if let preferred = UserDefaults.standard.string(forKey: "forge.config.path"),
           FileManager.default.fileExists(atPath: preferred) {
            return (preferred as NSString).deletingLastPathComponent
        }
        for candidate in ForgePaths.configCandidatePaths(home: home) {
            if FileManager.default.fileExists(atPath: candidate) {
                return (candidate as NSString).deletingLastPathComponent
            }
        }
        return nil
    }
}
