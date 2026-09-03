import AppKit
import ForgeCore
import SwiftUI

/// Menubar popover for zero-friction inbox capture (same path as `forge capture`).
@MainActor
final class CapturePopoverController: NSObject, NSTextFieldDelegate {

    private let popover = NSPopover()
    private weak var anchorButton: NSButton?

    private var titleText = ""
    private var detectedLink: String?
    private var detectedKind: String?
    private var statusMessage: String?
    private var isSubmitting = false
    private var forgeDir: String?

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
        prepareClipboard()
        titleText = ""
        statusMessage = nil
        isSubmitting = false
        show(relativeTo: button)
    }

    func show(relativeTo button: NSButton? = nil) {
        if let button {
            anchorButton = button
        }
        guard let anchor = anchorButton else { return }
        prepareClipboard()
        refreshHostedView()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        // Focus the text field after the popover appears.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func prepareClipboard() {
        detectedLink = nil
        detectedKind = nil
        guard let paste = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !paste.isEmpty else { return }

        if paste.lowercased().hasPrefix("message:") {
            detectedKind = "mail"
            detectedLink = paste
            return
        }
        if paste.lowercased().hasPrefix("http://") || paste.lowercased().hasPrefix("https://") {
            detectedKind = "url"
            detectedLink = paste
            return
        }
        if paste.lowercased().hasPrefix("file:") {
            detectedKind = "file"
            detectedLink = paste
            return
        }
        if paste.lowercased().hasPrefix("obsidian:") {
            detectedKind = "obsidian"
            detectedLink = paste
            return
        }
        if paste.hasPrefix("/") {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: paste, isDirectory: &isDir), !isDir.boolValue {
                detectedKind = "file"
                detectedLink = URL(fileURLWithPath: paste).absoluteString
            }
        }
    }

    private func refreshHostedView() {
        let view = CapturePopoverView(
            title: Binding(
                get: { self.titleText },
                set: { self.titleText = $0 }
            ),
            detectedLink: detectedLink,
            detectedKind: detectedKind,
            statusMessage: statusMessage,
            isSubmitting: isSubmitting,
            onCapture: { [weak self] in self?.submit() },
            onCancel: { [weak self] in self?.popover.performClose(nil) }
        )
        popover.contentViewController = NSHostingController(rootView: view)
    }

    private func submit() {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let forgeDir else {
            statusMessage = "No Forge config loaded."
            refreshHostedView()
            return
        }
        isSubmitting = true
        statusMessage = nil
        refreshHostedView()

        let link = detectedLink
        let kind = detectedKind
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try CaptureScriptRunner.capture(
                        forgeDir: forgeDir,
                        title: trimmed,
                        link: link,
                        kind: kind,
                        source: "menubar"
                    )
                }.value
                self.statusMessage = "Captured \(result.taskID)"
                self.isSubmitting = false
                self.titleText = ""
                self.refreshHostedView()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.popover.performClose(nil)
                }
            } catch {
                self.statusMessage = error.localizedDescription
                self.isSubmitting = false
                self.refreshHostedView()
            }
        }
    }
}
