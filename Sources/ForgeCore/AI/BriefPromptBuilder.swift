import Foundation

/// Builds a constrained prompt for brief generation and parses the provider's JSON response.
public enum BriefPromptBuilder {
    /// Create the user-facing prompt containing the full context as JSON.
    public static func buildUserPrompt(context: BriefContext) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(context)
        let json = String(decoding: data, as: UTF8.self)

        return """
        You are Forge’s local assistant. Produce a concise brief for the user based on the provided context.

        Requirements:
        - Output must be a single JSON object with keys: brief_markdown (string) and proposals (array).
        - brief_markdown should be compact, scannable Markdown with headings and bullets.
        - proposals may be empty. If non-empty, each entry must include:
          - kind: \"move\" | \"tag_add\" | \"tag_remove\"
          - projectPath: absolute path string from the input
          - columnName (for move) OR tag (for tag_add/tag_remove)
          - why: short rationale
        - Do not invent projects, tags, or columns. Use only values present in the input.
        - When uncertain, prefer no proposals and explain in the brief.

        Context JSON:
        \(json)
        """
    }

    public static func parseResult(json: String) throws -> BriefResult {
        struct Wire: Codable {
            let briefMarkdown: String
            let proposals: [BriefProposal]

            enum CodingKeys: String, CodingKey {
                case briefMarkdown = "brief_markdown"
                case proposals
            }
        }

        guard let data = json.data(using: .utf8) else {
            throw ForgeAIError.decodeFailed("Could not decode provider response as UTF-8.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let wire = try decoder.decode(Wire.self, from: data)
            return BriefResult(briefMarkdown: wire.briefMarkdown, proposals: wire.proposals)
        } catch {
            throw ForgeAIError.decodeFailed("Could not decode brief JSON: \(error.localizedDescription)")
        }
    }
}
