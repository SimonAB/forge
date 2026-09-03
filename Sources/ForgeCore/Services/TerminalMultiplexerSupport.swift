import Foundation

/// Multiplexer backends Forge prefers when present (before Ghostty / Terminal.app).
public enum TerminalMultiplexerKind: String, Sendable, CaseIterable {
    case herdr
    case tmux
}

/// Pure helpers for detecting and parsing herdr / tmux launch responses.
public enum TerminalMultiplexerSupport {

    /// Whether `herdr status` output indicates a compatible running server.
    public static func isHerdrServerRunning(statusOutput: String) -> Bool {
        let lines = statusOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inServer = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("server:") {
                inServer = true
                continue
            }
            if inServer {
                if trimmed.hasPrefix("status:") {
                    return trimmed.lowercased().contains("running")
                }
                // Left the server block (next top-level key).
                if !line.hasPrefix(" ") && !line.hasPrefix("\t") && trimmed.contains(":") {
                    break
                }
            }
        }
        return statusOutput.lowercased().contains("status: running")
    }

    /// Extract `root_pane.pane_id` from `herdr tab create` JSON.
    public static func parseHerdrTabCreatePaneID(from jsonText: String) -> String? {
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let rootPane = result["root_pane"] as? [String: Any],
              let paneID = rootPane["pane_id"] as? String,
              !paneID.isEmpty
        else {
            return nil
        }
        return paneID
    }

    /// Short tab / window label from a working directory path.
    public static func label(forWorkingDirectory workingDirectory: String?, fallback: String = "Forge") -> String {
        guard let workingDirectory, !workingDirectory.isEmpty else { return fallback }
        let name = (workingDirectory as NSString).lastPathComponent
        return name.isEmpty ? fallback : String(name.prefix(40))
    }

    /// Candidate absolute paths for the `herdr` CLI.
    public static func herdrBinaryCandidates(home: String = NSHomeDirectory()) -> [String] {
        [
            "/opt/homebrew/bin/herdr",
            "/usr/local/bin/herdr",
            (home as NSString).appendingPathComponent("bin/herdr"),
            (home as NSString).appendingPathComponent(".local/bin/herdr"),
        ]
    }

    /// Candidate absolute paths for the `tmux` CLI.
    public static func tmuxBinaryCandidates(home: String = NSHomeDirectory()) -> [String] {
        [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            (home as NSString).appendingPathComponent("bin/tmux"),
            (home as NSString).appendingPathComponent(".local/bin/tmux"),
        ]
    }
}
