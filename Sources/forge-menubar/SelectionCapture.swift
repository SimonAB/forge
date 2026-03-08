import AppKit
import Foundation

/// Captures the currently selected item from the frontmost application (e.g. Mail message or Finder file)
/// and returns a task description with a cross‑platform link suitable for the inbox.
enum SelectionCapture {

    /// Result of a capture: human‑readable label and a link (message: or file: URL).
    struct CapturedItem {
        let label: String
        let link: String
    }

    /// Attempts to capture the current selection from the frontmost app.
    /// Returns a `CapturedItem` with label and link, or nil if the frontmost app is not supported or no selection.
    static func captureFromFrontmostApplication() -> CapturedItem? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleId = frontmost.bundleIdentifier ?? ""

        if bundleId == "com.apple.mail" {
            return captureMailSelection()
        }
        if bundleId == "com.apple.finder" {
            return captureFinderSelection()
        }
        return nil
    }

    /// Uses AppleScript to get the first selected message in Mail and builds a message: URL.
    private static func captureMailSelection() -> CapturedItem? {
        let script = """
        tell application "Mail" to tell front message viewer
            set msgs to selected messages
            if (count of msgs) < 1 then return ""
            set m to item 1 of msgs
            set mid to message id of m
            set subj to subject of m
            return mid & "\\n" & subj
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error),
              result.stringValue?.isEmpty == false else {
            return nil
        }
        let parts = result.stringValue!.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let messageId = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let subject = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : "Email"

        guard !messageId.isEmpty else { return nil }

        // message: URLs require angle brackets around the message-id (RFC 5322). Mail's AppleScript
        // may return the id with or without brackets; ensure we always emit message://%3C...%3E.
        let rawId = messageId.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        let link = "message://%3C\(rawId)%3E"
        let label = subject.isEmpty ? "Email" : subject
        return CapturedItem(label: label, link: link)
    }

    /// Returns the task text as a markdown link so it is clickable in markdown viewers.
    static func taskText(for item: CapturedItem) -> String {
        let safeLabel = item.label.replacingOccurrences(of: "]", with: "\\]")
        return "[\(safeLabel)](\(item.link))"
    }

    /// Uses AppleScript to get the first selected file or folder in Finder and builds a file: URL.
    private static func captureFinderSelection() -> CapturedItem? {
        let script = """
        tell application "Finder"
            set sel to selection
            if (count of sel) < 1 then return ""
            set f to item 1 of sel
            set cls to class of f
            if cls is not document file and cls is not alias file and cls is not file and cls is not folder then return ""
            set p to POSIX path of (f as alias)
            set n to name of f
            return p & "\\n" & n
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error),
              result.stringValue?.isEmpty == false else {
            return nil
        }
        let parts = result.stringValue!.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let posixPath = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let name = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : (posixPath as NSString).lastPathComponent

        guard !posixPath.isEmpty, FileManager.default.fileExists(atPath: posixPath) else { return nil }

        let fileURL = URL(fileURLWithPath: posixPath)
        let link = fileURL.absoluteString
        let label = name.isEmpty ? fileURL.lastPathComponent : name
        return CapturedItem(label: label, link: link)
    }
}
