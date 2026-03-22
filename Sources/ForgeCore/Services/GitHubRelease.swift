import Foundation

// MARK: - Distribution constants

/// Asset names attached to Forge GitHub Releases (CI must match).
public enum ForgeReleaseAssets: Sendable {
    /// Zip containing `Forge.app` for Apple Silicon.
    public static let macOSAppZip = "Forge-macos-arm64.app.zip"
}

// MARK: - Semantic version comparison

/// Compares dotted numeric version strings such as `0.8.12`.
public enum SemanticVersion: Sendable {

    /// Lexicographic comparison of numeric components; missing components treated as `0`.
    /// Suffixes after the first `-` are ignored for the left-hand numeric core (e.g. `1.0.0-beta`).
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lc = numericComponents(lhs)
        let rc = numericComponents(rhs)
        let count = max(lc.count, rc.count)
        for i in 0..<count {
            let a = i < lc.count ? lc[i] : 0
            let b = i < rc.count ? rc[i] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    /// True when `remote` sorts strictly after `local`.
    public static func isStrictlyNewer(remote: String, than local: String) -> Bool {
        compare(remote, local) == .orderedDescending
    }

    static func numericComponents(_ s: String) -> [Int] {
        let core = s.split(separator: "-", maxSplits: 1).first.map(String.init) ?? s
        return core.split(separator: ".").map { segment in
            var value = 0
            for ch in segment {
                guard let d = ch.wholeNumberValue else { break }
                value = value * 10 + d
            }
            return value
        }
    }
}

// MARK: - Latest release DTO

/// Summary of the latest GitHub release needed for in-app updates.
public struct GitHubReleaseInfo: Sendable, Equatable {
    public let tagVersion: String
    public let appDownloadURL: URL

    public init(tagVersion: String, appDownloadURL: URL) {
        self.tagVersion = tagVersion
        self.appDownloadURL = appDownloadURL
    }
}

public enum GitHubReleaseError: Error, Sendable, Equatable {
    case unexpectedHTTPStatus(Int)
    case appAssetMissing
    case decodingFailed
}

/// Fetches `releases/latest` from the GitHub REST API.
public struct GitHubReleaseService: Sendable {
    public let owner: String
    public let repo: String
    public let urlSession: URLSession

    public init(owner: String = "SimonAB", repo: String = "forge", urlSession: URLSession = .shared) {
        self.owner = owner
        self.repo = repo
        self.urlSession = urlSession
    }

    /// Fetches the latest release and locates the menubar app zip asset.
    public func fetchLatestRelease(appAssetName: String = ForgeReleaseAssets.macOSAppZip) async throws -> GitHubReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw GitHubReleaseError.decodingFailed
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubReleaseError.unexpectedHTTPStatus(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubReleaseError.unexpectedHTTPStatus(http.statusCode)
        }
        return try Self.parseLatestReleaseData(data, appAssetName: appAssetName)
    }

    /// Parses JSON from `GET /repos/{owner}/{repo}/releases/latest`.
    public static func parseLatestReleaseData(_ data: Data, appAssetName: String) throws -> GitHubReleaseInfo {
        let decoder = JSONDecoder()
        let dto: GitHubLatestReleaseDTO
        do {
            dto = try decoder.decode(GitHubLatestReleaseDTO.self, from: data)
        } catch {
            throw GitHubReleaseError.decodingFailed
        }
        let tag = dto.tagName.hasPrefix("v") ? String(dto.tagName.dropFirst()) : dto.tagName
        guard let asset = dto.assets.first(where: { $0.name == appAssetName }),
              let downloadURL = URL(string: asset.browserDownloadURL) else {
            throw GitHubReleaseError.appAssetMissing
        }
        return GitHubReleaseInfo(tagVersion: tag, appDownloadURL: downloadURL)
    }
}

private struct GitHubLatestReleaseDTO: Decodable {
    let tagName: String
    let assets: [GitHubAssetDTO]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubAssetDTO: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
