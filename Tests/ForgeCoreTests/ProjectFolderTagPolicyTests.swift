import Testing

import ForgeCore

@Suite("Project folder tag policy")
struct ProjectFolderTagPolicyTests {

    private var config: ForgeConfig {
        ForgeConfig.defaultConfig(projectRoots: ["/tmp"])
    }

    @Test("Meta tag from config is allowed")
    func metaAllowed() {
        #expect(ProjectFolderTagPolicy.validationResult(tag: "URGENT ⚠️", config: config) == .allowed)
    }

    @Test("Assignee tag is allowed")
    func assigneeAllowed() {
        #expect(ProjectFolderTagPolicy.validationResult(tag: "#Alice", config: config) == .allowed)
    }

    @Test("Workflow column tag is workflowColumn")
    func columnNotManaged() {
        #expect(ProjectFolderTagPolicy.validationResult(tag: "Active 🚧", config: config) == .workflowColumn)
    }

    @Test("Random tag is unrecognized")
    func randomUnrecognized() {
        #expect(ProjectFolderTagPolicy.validationResult(tag: "Grey", config: config) == .unrecognized)
    }
}
