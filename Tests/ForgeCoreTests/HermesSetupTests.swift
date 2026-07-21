import Foundation
import Testing

@testable import ForgeCore

@Suite("Hermes setup")
struct HermesSetupTests {
    @Test("Parser reads external_dirs list entries")
    func parseExternalDirsList() {
        let yaml = """
        skills:
          external_dirs:
            - /tmp/forge/.hermes/skills
            - /other/path
        agent:
          max_turns: 10
        """
        let dirs = HermesConfigParser.parseExternalDirs(configText: yaml)
        #expect(dirs.count == 2)
        #expect(dirs[0].hasSuffix(".hermes/skills"))
    }

    @Test("Parser reads empty external_dirs")
    func parseEmptyExternalDirs() {
        let yaml = """
        skills:
          external_dirs: []
        """
        #expect(HermesConfigParser.parseExternalDirs(configText: yaml).isEmpty)
    }

    @Test("Detect configured forge skills directory")
    func detectsForgeSkillsDir() {
        let skills = "/Users/me/Documents/Forge/.hermes/skills"
        let yaml = """
        skills:
          external_dirs:
            - \(skills)
        """
        #expect(HermesConfigParser.externalDirsContainForgeSkills(
            configText: yaml,
            expectedSkillsDirectory: skills
        ))
    }

    @Test("Skills path helper resolves under forge home")
    func skillsPathUnderForgeHome() {
        let home = "/tmp/forge-home"
        #expect(HermesPaths.skillsDirectory(forgeHome: home) == "/tmp/forge-home/.hermes/skills")
    }

    @Test("Setup status ready when all checks pass")
    func statusReadyAggregation() {
        let status = HermesSetupStatus(checks: [
            HermesSetupCheck(label: "a", passed: true, detail: ""),
            HermesSetupCheck(label: "b", passed: true, detail: ""),
        ])
        #expect(status.isReady)
    }
}
