import AppKit
import ForgeCore
import SwiftUI

/// Hosts the GTD dashboard popover anchored to the menu bar status item.
@MainActor
final class DashboardPopoverController: NSObject {

    private let popover = NSPopover()
    private weak var anchorButton: NSButton?

    private var snapshot: DashboardSnapshotJSON?
    private var errorMessage: String?
    private var isLoading = false
    private var forgeDir: String?
    private var config: ForgeConfig?
    private var assignProjects: [DashboardAssignProject] = []

    var onOpenBoard: (() -> Void)?

    override init() {
        super.init()
        popover.behavior = .semitransient
        popover.animates = true
    }

    func updateForgeDir(_ forgeDir: String?) {
        self.forgeDir = forgeDir
        if let forgeDir {
            let path = (forgeDir as NSString).appendingPathComponent("config.yaml")
            config = try? ForgeConfig.load(from: path)
        } else {
            config = nil
        }
        refreshAssignProjects()
    }

    func toggle(relativeTo button: NSButton) {
        anchorButton = button
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let forgeDir else {
            presentError("No Forge config loaded.", relativeTo: button)
            return
        }
        showLoading(relativeTo: button)
        Task {
            await reload(forgeDir: forgeDir)
            if let button = anchorButton {
                showPopover(relativeTo: button)
            }
        }
    }

    func reload(forgeDir: String) async {
        isLoading = true
        errorMessage = nil
        snapshot = nil
        refreshHostedView()
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try DashboardScriptRunner.loadSnapshot(forgeDir: forgeDir)
            }.value
            snapshot = loaded
            errorMessage = nil
            refreshAssignProjects()
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
        refreshHostedView()
    }

    private func refreshAssignProjects() {
        guard let config else {
            assignProjects = []
            return
        }
        let scanner = WorkspaceScanner(config: config)
        let projects = (try? scanner.scanProjects()) ?? []
        assignProjects = projects
            .filter { $0.column != "Shipped" }
            .map {
                DashboardAssignProject(
                    name: $0.name,
                    column: $0.column ?? "(none)"
                )
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private func showLoading(relativeTo button: NSButton) {
        isLoading = true
        errorMessage = nil
        refreshHostedView()
        showPopover(relativeTo: button)
    }

    private func presentError(_ message: String, relativeTo button: NSButton) {
        errorMessage = message
        isLoading = false
        refreshHostedView()
        showPopover(relativeTo: button)
    }

    private func showPopover(relativeTo button: NSButton) {
        refreshHostedView()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func refreshHostedView() {
        let dir = forgeDir
        let view = DashboardPopoverView(
            snapshot: snapshot,
            errorMessage: errorMessage,
            isLoading: isLoading,
            assignProjects: assignProjects,
            onRefresh: { [weak self] in
                guard let self, let dir else { return }
                Task { await self.reload(forgeDir: dir) }
            },
            onOpenBoard: { [weak self] in
                self?.popover.performClose(nil)
                self?.onOpenBoard?()
            },
            onOpenProjectTasks: { [weak self] name in
                self?.openProjectTasks(named: name)
            },
            onRevealProject: { [weak self] name in
                self?.revealProject(named: name)
            },
            onOpenInboxItem: { [weak self] taskID in
                self?.openInboxItem(taskID: taskID)
            },
            onCompleteInboxItem: { [weak self] taskID in
                self?.completeInboxItem(taskID: taskID)
            },
            onAssignInboxItem: { [weak self] taskID, project in
                self?.assignInboxItem(taskID: taskID, project: project)
            }
        )
        popover.contentViewController = NSHostingController(rootView: view)
    }

    private func openProjectTasks(named name: String) {
        guard let config else { return }
        popover.performClose(nil)
        // Leave Forge in the background so Super Productivity (or Finder) can take focus.
        _ = ProjectOpenActions.openTasksOrRevealFolder(
            projectName: name,
            config: config,
            forgeDir: forgeDir
        )
    }

    private func revealProject(named name: String) {
        guard let config else { return }
        popover.performClose(nil)
        _ = ProjectOpenActions.revealInFinder(projectName: name, config: config)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openInboxItem(taskID: String) {
        guard let forgeDir else { return }
        do {
            try CaptureScriptRunner.openTask(forgeDir: forgeDir, taskID: taskID)
            popover.performClose(nil)
        } catch {
            // Keep the popover open when there is no link or open fails.
            NSSound.beep()
        }
    }

    private func completeInboxItem(taskID: String) {
        guard let forgeDir else { return }
        do {
            try CaptureScriptRunner.completeTask(forgeDir: forgeDir, taskID: taskID)
            Task { await self.reload(forgeDir: forgeDir) }
        } catch {
            NSSound.beep()
        }
    }

    private func assignInboxItem(taskID: String, project: String) {
        guard let forgeDir else { return }
        do {
            try CaptureScriptRunner.assignTask(
                forgeDir: forgeDir,
                taskID: taskID,
                project: project
            )
            Task { await self.reload(forgeDir: forgeDir) }
        } catch {
            NSSound.beep()
        }
    }
}
