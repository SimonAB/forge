import Foundation

/// Errors from the OmniFocus JXA / OmniJS bridge.
public enum OmniJSBridgeError: Error, CustomStringConvertible, Sendable {
    case omnifocusNotAvailable(String)
    case evaluationFailed(String)
    case invalidJSON(String)
    case disabled

    public var description: String {
        switch self {
        case .omnifocusNotAvailable(let detail):
            return "OmniFocus is not available: \(detail)"
        case .evaluationFailed(let detail):
            return "OmniFocus script failed: \(detail)"
        case .invalidJSON(let detail):
            return "OmniFocus returned invalid JSON: \(detail)"
        case .disabled:
            return "OmniFocus integration is disabled. Set omnifocus.enabled: true in config.yaml."
        }
    }
}

/// Runs OmniJS inside OmniFocus via JXA `evaluateJavascript`, returning JSON.
///
/// Uses a temporary script file so argument injection stays robust (same approach as
/// community OmniFocus JXA bridges).
public struct OmniJSBridge: Sendable {
    public var timeoutSeconds: TimeInterval

    public init(timeoutSeconds: TimeInterval = 120) {
        self.timeoutSeconds = timeoutSeconds
    }

    /// Evaluate an OmniJS function that accepts one JSON argument and returns a JSON string.
    public func evaluateJSON<T: Decodable, Arg: Encodable>(
        omniJSSource: String,
        argument: Arg,
        as type: T.Type = T.self
    ) throws -> T {
        let argJSON = try JSONEncoder().encode(argument)
        guard let argLiteral = String(data: argJSON, encoding: .utf8) else {
            throw OmniJSBridgeError.invalidJSON("Could not encode argument.")
        }
        let raw = try evaluateRaw(omniJSSource: omniJSSource, argumentLiteral: argLiteral)
        guard let data = raw.data(using: .utf8) else {
            throw OmniJSBridgeError.invalidJSON(raw)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw OmniJSBridgeError.invalidJSON("\(error.localizedDescription); payload prefix: \(raw.prefix(240))")
        }
    }

    /// Evaluate with an empty object argument.
    public func evaluateJSON<T: Decodable>(omniJSSource: String, as type: T.Type = T.self) throws -> T {
        try evaluateJSON(omniJSSource: omniJSSource, argument: [String: String](), as: type)
    }

    /// Returns the raw string from OmniFocus `evaluateJavascript`.
    public func evaluateRaw(omniJSSource: String, argumentLiteral: String) throws -> String {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("forge-omnijs-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let fnURL = dir.appendingPathComponent("omni.js")
        let argURL = dir.appendingPathComponent("arg.json")
        let jxaURL = dir.appendingPathComponent("runner.jxa")

        try omniJSSource.write(to: fnURL, atomically: true, encoding: .utf8)
        try argumentLiteral.write(to: argURL, atomically: true, encoding: .utf8)

        let jxa = """
        (() => {
          "use strict";
          ObjC.import("Foundation");
          const read = (path) => {
            const str = $.NSString.stringWithContentsOfFileEncodingError(
              path,
              $.NSUTF8StringEncoding,
              null
            );
            return ObjC.unwrap(str);
          };
          const fnSource = read(\(jsonString(fnURL.path)));
          const argJSON = JSON.parse(read(\(jsonString(argURL.path))));
          const OmniFocus = Application("OmniFocus");
          const code = "(" + fnSource + ")(" + JSON.stringify(argJSON) + ")";
          return OmniFocus.evaluateJavascript(code);
        })();
        """
        try jxa.write(to: jxaURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", jxaURL.path]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw OmniJSBridgeError.omnifocusNotAvailable(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw OmniJSBridgeError.evaluationFailed("Timed out after \(Int(timeoutSeconds))s.")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = err.isEmpty ? out : err
            if detail.localizedCaseInsensitiveContains("not authorized")
                || detail.localizedCaseInsensitiveContains("not allowed") {
                throw OmniJSBridgeError.omnifocusNotAvailable(
                    "Automation permission denied. Allow your terminal (or Forge.app) to control OmniFocus in System Settings → Privacy & Security → Automation. \(detail)"
                )
            }
            throw OmniJSBridgeError.evaluationFailed(detail.isEmpty ? "exit \(process.terminationStatus)" : detail)
        }

        if out.isEmpty {
            throw OmniJSBridgeError.evaluationFailed(err.isEmpty ? "Empty result from OmniFocus." : err)
        }
        return out
    }

    private func jsonString(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s),
              let lit = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return lit
    }
}
