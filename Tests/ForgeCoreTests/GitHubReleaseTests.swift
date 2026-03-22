import Foundation
import Testing

@testable import ForgeCore

@Suite("GitHub release parsing and semver")
struct GitHubReleaseTests {

    @Test("parseLatestReleaseData extracts tag and app zip URL")
    func parseLatestRelease() throws {
        let json = """
        {
          "tag_name": "v0.9.0",
          "assets": [
            { "name": "other.zip", "browser_download_url": "https://example.com/other.zip" },
            { "name": "Forge-macos-arm64.app.zip", "browser_download_url": "https://example.com/Forge-macos-arm64.app.zip" }
          ]
        }
        """.data(using: .utf8)!
        let info = try GitHubReleaseService.parseLatestReleaseData(json, appAssetName: ForgeReleaseAssets.macOSAppZip)
        #expect(info.tagVersion == "0.9.0")
        #expect(info.appDownloadURL.absoluteString == "https://example.com/Forge-macos-arm64.app.zip")
    }

    @Test("parseLatestReleaseData throws when app asset missing")
    func parseMissingAsset() {
        let json = """
        { "tag_name": "v1.0.0", "assets": [] }
        """.data(using: .utf8)!
        #expect(throws: GitHubReleaseError.appAssetMissing) {
            try GitHubReleaseService.parseLatestReleaseData(json, appAssetName: ForgeReleaseAssets.macOSAppZip)
        }
    }

    @Test("SemanticVersion ordering")
    func semver() {
        #expect(SemanticVersion.compare("0.8.12", "0.8.12") == .orderedSame)
        #expect(SemanticVersion.isStrictlyNewer(remote: "0.9.0", than: "0.8.12"))
        #expect(!SemanticVersion.isStrictlyNewer(remote: "0.8.11", than: "0.8.12"))
        #expect(SemanticVersion.isStrictlyNewer(remote: "0.8.13", than: "0.8.12"))
        #expect(SemanticVersion.compare("1.0.0-beta", "1.0.0") == .orderedSame)
    }
}
