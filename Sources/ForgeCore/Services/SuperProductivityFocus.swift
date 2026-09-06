import Foundation

/// Focus a mapped Super Productivity project in the SP UI.
///
/// SP has no stable ``superproductivity://`` deep link for an existing project.
/// This helper runs ``scripts/forge-sp-focus-project.py``, which uses Chrome
/// DevTools Protocol to set ``#/project/<id>/tasks`` (relaunches SP with
/// ``--remote-debugging-port=9222`` when CDP is not already available).
public enum SuperProductivityFocus {
    /// Best-effort focus; returns a short note for logging, or nil on success with no message.
    @discardableResult
    public static func focusProject(
        projectId: String,
        forgeDir: String?
    ) -> String? {
        let trimmed = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "SP focus skipped: empty project id"
        }
        guard let forgeDir, !forgeDir.isEmpty else {
            return "SP focus skipped: Forge directory unknown"
        }
        let script = (forgeDir as NSString).appendingPathComponent("scripts/forge-sp-focus-project.py")
        guard FileManager.default.fileExists(atPath: script) else {
            return "SP focus skipped: forge-sp-focus-project.py not found"
        }

        let python = preferredPython(forgeDir: forgeDir)
        let process = Process()
        if python == "/usr/bin/env" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", script, trimmed]
        } else {
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [script, trimmed]
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 0 {
                return nil
            }
            return text.isEmpty
                ? "SP focus failed (exit \(process.terminationStatus))"
                : "SP focus failed: \(text)"
        } catch {
            return "SP focus failed: \(error.localizedDescription)"
        }
    }

    /// Prefer Forge's durable environment, installed from scripts/requirements.txt.
    static func preferredPython(forgeDir: String) -> String {
        ExecutablePathResolver.forgePython(in: forgeDir) ?? "/usr/bin/env"
    }
}
