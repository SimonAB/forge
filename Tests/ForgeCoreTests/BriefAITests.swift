import Foundation
import Testing

@testable import ForgeCore

@Suite("Brief AI")
struct BriefAITests {
    @Test("Prompt includes required JSON keys and context")
    func promptHasContract() throws {
        let cfg = ForgeConfig.defaultConfig(projectRoots: ["/tmp/forge-test"])
        let board = BoardSnapshot(
            columns: cfg.board.columns.map { ColumnSnapshot(name: $0.name, tag: $0.tag) },
            metaTags: cfg.board.metaTags,
            tagAliases: cfg.board.tagAliases,
            projects: []
        )
        let ctx = BriefContext(generatedAt: Date(timeIntervalSince1970: 0), board: board, calendar: nil)
        let prompt = try BriefPromptBuilder.buildUserPrompt(context: ctx)
        #expect(prompt.contains("brief_markdown"))
        #expect(prompt.contains("proposals"))
        #expect(prompt.contains("\"generatedAt\""))
    }

    @Test("Result parser decodes brief JSON")
    func parseResult() throws {
        let json = """
        {
          "brief_markdown": "## Brief\\n- Hello",
          "proposals": [
            {
              "kind": "move",
              "projectPath": "/tmp/x",
              "columnName": "Active",
              "tag": null,
              "why": "Test"
            }
          ]
        }
        """
        let result = try BriefPromptBuilder.parseResult(json: json)
        #expect(result.briefMarkdown.contains("## Brief"))
        #expect(result.proposals.count == 1)
        #expect(result.proposals.first?.kind == .move)
    }

    @Test("Proposal validation rejects unknown tags")
    func validateRejectsUnrecognisedTag() throws {
        let cfg = ForgeConfig.defaultConfig(projectRoots: ["/tmp/forge-test"])
        let applier = BriefProposalApplier(config: cfg)
        let p = BriefProposal(kind: .tagAdd, projectPath: "/tmp/forge-test/Proj", columnName: nil, tag: "Grey", why: "No")
        #expect(throws: (any Error).self) {
            try applier.validate(p)
        }
    }

    @Test("Applier can move and tag a real folder")
    func applyChanges() throws {
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("forge-ai-tests-\(UUID().uuidString)")
        let project = root.appendingPathComponent("ExampleProject")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let cfg = ForgeConfig.defaultConfig(projectRoots: [root.path])
        let applier = BriefProposalApplier(config: cfg)

        let move = BriefProposal(kind: .move, projectPath: project.path, columnName: "Watch", tag: nil, why: "Test")
        let addUrgent = BriefProposal(kind: .tagAdd, projectPath: project.path, columnName: nil, tag: "URGENT ⚠️", why: "Test")
        _ = try applier.apply([move, addUrgent])

        let tagStore = FinderTagStore()
        let tags = try tagStore.readTags(at: project.path)
        #expect(tags.contains("Watch 👁️"))
        #expect(tags.contains("URGENT ⚠️"))
    }
}
