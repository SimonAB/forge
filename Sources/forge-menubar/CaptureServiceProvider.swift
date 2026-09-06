import AppKit
import ForgeCore
import UserNotifications

/// macOS Services entry: context capture (files / Mail / browser / text) → inbox.
final class CaptureServiceProvider: NSObject {

    /// Build ``forge-capture.py service`` arguments from the Service pasteboard.
    func serviceArguments(from pboard: NSPasteboard, prefer: String = "auto") -> [String] {
        var files: [String] = []
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            files = urls.filter(\.isFileURL).map(\.path)
        }

        let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)

        var args = ["service", "--source", "service", "--json", "--prefer", prefer]
        for path in files {
            args += ["--file", path]
        }
        if let text, !text.isEmpty {
            args += ["--text", text]
        }
        return args
    }

    func runService(prefer: String = "auto", pboard: NSPasteboard) -> String {
        guard let forgeDir = Self.resolveForgeDir() else {
            return "No Forge config loaded."
        }
        let args = serviceArguments(from: pboard, prefer: prefer)
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
        let result = runService(prefer: "auto", pboard: pboard)
        if result.lowercased().contains("nothing to capture")
            || result.lowercased().contains("failed")
            || result.lowercased().contains("not found") {
            errorPointer.pointee = result as NSString
        }
    }

    /// Alias for the same context engine with Mail preference (existing shortcuts).
    @objc func captureMailToForgeInbox(
        _ pboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let result = runService(prefer: "mail", pboard: pboard)
        if result.lowercased().contains("nothing to capture")
            || result.lowercased().contains("failed")
            || result.lowercased().contains("not found") {
            errorPointer.pointee = result as NSString
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
        let candidates = [
            "\(home)/Documents/Software/Forge",
            "\(home)/Documents/Forge",
            "\(home)/Documents/Work/Projects/Forge",
        ]
        return candidates.first {
            FileManager.default.fileExists(atPath: "\($0)/config.yaml")
                || FileManager.default.fileExists(atPath: "\($0)/config.sample.yaml")
        }
    }
}
