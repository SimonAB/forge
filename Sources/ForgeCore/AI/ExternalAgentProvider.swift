import Foundation

/// Optional provider backed by an external agent process.
///
/// This is a stub to keep the abstraction stable while the “ACP” shape is decided.
public struct ExternalAgentProvider: LLMProvider {
    public struct Settings: Sendable {
        public let endpoint: URL

        public init(endpoint: URL) {
            self.endpoint = endpoint
        }
    }

    private let settings: Settings

    public init(settings: Settings) {
        self.settings = settings
    }

    public func generateBrief(context: BriefContext) async throws -> BriefResult {
        throw ForgeAIError.requestFailed("External agent provider is not implemented yet (\(settings.endpoint.absoluteString)).")
    }
}
