import Foundation

/// Local, OpenAI-compatible provider targeting Ollama’s loopback API by default.
public struct LocalOllamaProvider: LLMProvider {
    public struct Settings: Sendable {
        public let baseURL: URL
        public let model: String
        public let apiKey: String
        public let temperature: Double
        public let maxTokens: Int
        public let timeoutSeconds: TimeInterval

        /// Create settings for a local Ollama instance.
        ///
        /// - Parameters:
        ///   - baseURL: OpenAI-compatible base URL, typically `http://127.0.0.1:11434/v1`.
        public init(
            baseURL: URL = URL(string: "http://127.0.0.1:11434/v1")!,
            model: String = "qwen3-coder",
            apiKey: String = "ollama",
            temperature: Double = 0.2,
            maxTokens: Int = 800,
            timeoutSeconds: TimeInterval = 60
        ) {
            self.baseURL = baseURL
            self.model = model
            self.apiKey = apiKey
            self.temperature = temperature
            self.maxTokens = maxTokens
            self.timeoutSeconds = timeoutSeconds
        }
    }

    private let settings: Settings
    private let urlSession: URLSession

    public init(settings: Settings = Settings(), urlSession: URLSession? = nil) {
        self.settings = settings
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = settings.timeoutSeconds
            config.timeoutIntervalForResource = settings.timeoutSeconds
            self.urlSession = URLSession(configuration: config)
        }
    }

    public func generateBrief(context: BriefContext) async throws -> BriefResult {
        let prompt = try BriefPromptBuilder.buildUserPrompt(context: context)
        let raw = try await chatCompletion(system: nil, user: prompt)
        return try BriefPromptBuilder.parseResult(json: raw)
    }

    private func chatCompletion(system: String?, user: String) async throws -> String {
        guard let url = URL(string: "chat/completions", relativeTo: settings.baseURL) else {
            throw ForgeAIError.invalidEndpoint("Invalid Ollama base URL: \(settings.baseURL.absoluteString)")
        }

        struct Message: Codable {
            let role: String
            let content: String
        }
        struct Body: Codable {
            let model: String
            let messages: [Message]
            let temperature: Double
            let maxTokens: Int

            enum CodingKeys: String, CodingKey {
                case model, messages, temperature
                case maxTokens = "max_tokens"
            }
        }
        struct Response: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        var messages: [Message] = []
        if let system, !system.isEmpty {
            messages.append(Message(role: "system", content: system))
        }
        messages.append(Message(role: "user", content: user))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")

        let body = Body(model: settings.model, messages: messages, temperature: settings.temperature, maxTokens: settings.maxTokens)
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw ForgeAIError.requestFailed("Could not encode request JSON.")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ForgeAIError.invalidResponse("No HTTP response from provider.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(decoding: data, as: UTF8.self)
            throw ForgeAIError.requestFailed("Provider returned HTTP \(http.statusCode): \(text)")
        }

        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            let text = String(decoding: data, as: UTF8.self)
            throw ForgeAIError.invalidResponse("Could not decode provider response: \(text)")
        }
        guard let content = decoded.choices.first?.message.content else {
            throw ForgeAIError.invalidResponse("Provider response had no message content.")
        }
        return extractJSONObject(from: content) ?? content
    }

    /// Extract a top-level JSON object from model output that may include surrounding text.
    private func extractJSONObject(from s: String) -> String? {
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") else { return nil }
        guard start < end else { return nil }
        return String(s[start...end])
    }
}
