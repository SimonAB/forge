import AppKit
import ForgeCore
import Foundation

/// Checks GitHub Releases for a newer Forge.app, downloads the zip, and installs to `/Applications` with admin rights.
@MainActor
final class AppUpdateCoordinator {

    static let shared = AppUpdateCoordinator()

    private let releaseService = GitHubReleaseService()
    private var checkTask: Task<Void, Never>?

    private init() {}

    /// Starts a user-initiated check (cancels any in-flight check).
    func checkForUpdatesFromMenu() {
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            await self?.runCheckFlow()
        }
    }

    private func runCheckFlow() async {
        let localVersion = ForgeVersion.version
        do {
            let latest = try await releaseService.fetchLatestRelease()
            if Task.isCancelled { return }
            guard SemanticVersion.isStrictlyNewer(remote: latest.tagVersion, than: localVersion) else {
                presentUpToDateAlert(latestVersion: latest.tagVersion, localVersion: localVersion)
                return
            }
            let install = await presentDownloadOfferAlert(remoteVersion: latest.tagVersion)
            if !install { return }
            if Task.isCancelled { return }
            try await downloadAndInstall(from: latest, expectedTagVersion: latest.tagVersion)
        } catch is CancellationError {
            return
        } catch let error as GitHubReleaseError {
            presentErrorAlert(message: error.userFacingMessage)
        } catch {
            presentErrorAlert(message: error.localizedDescription)
        }
    }

    private func presentUpToDateAlert(latestVersion: String, localVersion: String) {
        let alert = NSAlert()
        alert.messageText = "You’re up to date"
        alert.informativeText = "Forge \(localVersion) is the same as or newer than the latest GitHub release (\(latestVersion))."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentDownloadOfferAlert(remoteVersion: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Update available"
            alert.informativeText = "Forge \(remoteVersion) is available. Download and replace /Applications/Forge.app? You will be asked for an administrator password."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Download and Install")
            alert.addButton(withTitle: "Cancel")
            continuation.resume(returning: alert.runModal() == .alertFirstButtonReturn)
        }
    }

    private func presentErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Update check failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentInstallSuccessAlert() {
        let alert = NSAlert()
        alert.messageText = "Update installed"
        alert.informativeText = "Forge was updated in /Applications. Quit and reopen Forge to run the new version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Quit Forge")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    private func downloadAndInstall(from info: GitHubReleaseInfo, expectedTagVersion: String) async throws {
        let fm = FileManager.default
        let base = try updatesBaseDirectory()
        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        let zipURL = base.appendingPathComponent(ForgeReleaseAssets.macOSAppZip, isDirectory: false)
        try? fm.removeItem(at: zipURL)

        let (tempZip, response) = try await URLSession.shared.download(from: info.appDownloadURL)
        if Task.isCancelled { return }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AppUpdateFlowError.downloadFailed(http.statusCode)
        }
        try fm.moveItem(at: tempZip, to: zipURL)

        let extractDir = base.appendingPathComponent("extract-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: extractDir) }

        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try runUnzip(zipURL: zipURL, destination: extractDir)

        let extractedApp = extractDir.appendingPathComponent("Forge.app", isDirectory: true)
        guard fm.fileExists(atPath: extractedApp.path) else {
            throw AppUpdateFlowError.missingAppInArchive
        }

        guard let bundleVersion = bundleShortVersion(at: extractedApp) else {
            throw AppUpdateFlowError.invalidBundle
        }
        guard SemanticVersion.isStrictlyNewer(remote: bundleVersion, than: ForgeVersion.version) else {
            throw AppUpdateFlowError.bundleNotNewer
        }
        guard bundleVersion == expectedTagVersion else {
            throw AppUpdateFlowError.versionMismatch
        }

        try AppPrivilegedInstaller.installForgeApp(from: extractedApp)

        if Task.isCancelled { return }
        presentInstallSuccessAlert()
    }

    private func updatesBaseDirectory() throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppUpdateFlowError.noApplicationSupport
        }
        return support.appendingPathComponent("Forge/updates", isDirectory: true)
    }

    private func bundleShortVersion(at appURL: URL) -> String? {
        guard let bundle = Bundle(url: appURL) else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private func runUnzip(zipURL: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zipURL.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppUpdateFlowError.unzipFailed
        }
    }
}

// MARK: - Errors

private enum AppUpdateFlowError: LocalizedError {
    case noApplicationSupport
    case downloadFailed(Int)
    case unzipFailed
    case missingAppInArchive
    case invalidBundle
    case bundleNotNewer
    case versionMismatch

    var errorDescription: String? {
        switch self {
        case .noApplicationSupport:
            return "Could not locate Application Support."
        case .downloadFailed(let code):
            return "Download failed (HTTP \(code))."
        case .unzipFailed:
            return "Could not unpack the downloaded archive."
        case .missingAppInArchive:
            return "The archive did not contain Forge.app."
        case .invalidBundle:
            return "The downloaded Forge.app is missing version metadata."
        case .bundleNotNewer:
            return "The downloaded app is not newer than the running version."
        case .versionMismatch:
            return "The downloaded app version does not match the release tag."
        }
    }
}

extension GitHubReleaseError {
    fileprivate var userFacingMessage: String {
        switch self {
        case .unexpectedHTTPStatus(let code):
            return "GitHub returned HTTP \(code)."
        case .appAssetMissing:
            return "This release does not include \(ForgeReleaseAssets.macOSAppZip). Try again after a newer release."
        case .decodingFailed:
            return "Could not read the GitHub API response."
        }
    }
}
