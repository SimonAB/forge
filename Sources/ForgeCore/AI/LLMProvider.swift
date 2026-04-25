import Foundation

/// An AI provider capable of generating a brief from a `BriefContext`.
public protocol LLMProvider: Sendable {
    /// Generate a brief (and optional proposals) from the given context.
    func generateBrief(context: BriefContext) async throws -> BriefResult
}

/// Errors returned by the AI integration.
public enum ForgeAIError: Error, CustomStringConvertible, Sendable {
    case invalidEndpoint(String)
    case requestFailed(String)
    case invalidResponse(String)
    case decodeFailed(String)

    public var description: String {
        switch self {
        case .invalidEndpoint(let msg): return msg
        case .requestFailed(let msg): return msg
        case .invalidResponse(let msg): return msg
        case .decodeFailed(let msg): return msg
        }
    }
}
