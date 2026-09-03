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

    var onOpenBoard: (() -> Void)?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
    }

    func updateForgeDir(_ forgeDir: String?) {
        self.forgeDir = forgeDir
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
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
        }
        isLoading = false
        refreshHostedView()
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
            onRefresh: { [weak self] in
                guard let self, let dir else { return }
                Task { await self.reload(forgeDir: dir) }
            },
            onOpenBoard: { [weak self] in
                self?.popover.performClose(nil)
                self?.onOpenBoard?()
            }
        )
        popover.contentViewController = NSHostingController(rootView: view)
    }
}
