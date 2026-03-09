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
        if bundleId == "com.sonnysoftware.Bookends" {
            return captureBookendsSelection()
        }
        if bundleId == "md.obsidian" {
            return captureObsidianSelection()
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

    /// Uses AppleScript to get the first selected publication in Bookends and builds a bookends:// URL.
    /// Falls back to using the bare URL as label if the title cannot be read.
    private static func captureBookendsSelection() -> CapturedItem? {
        let script = """
        tell application "Bookends"
            if not (exists front library window) then return ""
            tell front library window
                if (count of selected publication items) < 1 then return ""
                set aPub to item 1 of selected publication items
                set theTitle to title of aPub
                set theID to id of aPub
            end tell
        end tell
        if theID is missing value then return ""
        set theLink to "bookends://sonnysoftware.com/" & theID
        return theLink & "\\n" & theTitle
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error),
              result.stringValue?.isEmpty == false else {
            return nil
        }
        let parts = result.stringValue!.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let link = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return nil }
        let label = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : link
        return CapturedItem(label: label.isEmpty ? link : label, link: link)
    }

    /// Uses AppleScript and window title parsing to build an obsidian://open URL for the current note.
    /// Assumes window title in the form "Note – Vault – Obsidian …".
    private static func captureObsidianSelection() -> CapturedItem? {
        let script = """
        tell application "System Events"
            if not (exists process "Obsidian") then return ""
            tell process "Obsidian"
                if not (exists front window) then return ""
                set t to name of front window
            end tell
        end tell
        if t is "" then return ""
        set AppleScript's text item delimiters to " - "
        set parts to text items of t
        if (count of parts) < 2 then return ""
        set noteTitle to item 1 of parts
        set vaultName to item 2 of parts
        set AppleScript's text item delimiters to ""
        return vaultName & "\\n" & noteTitle
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error),
              result.stringValue?.isEmpty == false else {
            return nil
        }
        let parts = result.stringValue!.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let vault = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let note = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vault.isEmpty, !note.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vault),
            URLQueryItem(name: "file", value: note),
        ]
        guard let url = components.url?.absoluteString else { return nil }
        return CapturedItem(label: note, link: url)
    }
}
