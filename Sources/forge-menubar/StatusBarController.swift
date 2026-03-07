import AppKit
import ForgeCore

/// Manages the menu bar status item, background sync timer, and menu actions.
@MainActor
final class StatusBarController: NSObject {

    private var statusItem: NSStatusItem!
    private var syncTimer: Timer?
    private var config: ForgeConfig?
    private var forgeDir: String?
    private var capturePanel: CapturePanel?

    private var overdueCount = 0
    private var dueTodayCount = 0
    private var inboxCount = 0
    private var lastSyncDate: Date?

    /// Sync interval in seconds (default: 5 minutes).
    private let syncInterval: TimeInterval = 300

    func start() {
        loadConfig()
        setupStatusItem()
        refreshCounts()
        startSyncTimer()
    }

    // MARK: - Configuration

    private func loadConfig() {
        let home = NSHomeDirectory()
        let candidates = [
            (home as NSString).appendingPathComponent("Documents/Forge/config.yaml"),
            (home as NSString).appendingPathComponent("Documents/Work/Projects/Forge/config.yaml"),
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                config = try? ForgeConfig.load(from: candidate)
                forgeDir = (candidate as NSString).deletingLastPathComponent
                return
            }
        }
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "hammer.fill",
                accessibilityDescription: "Forge"
            )
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
        }

        rebuildMenu()
    }

    private func updateBadge() {
        guard let button = statusItem.button else { return }

        // Never set contentTintColor — it overrides the template image's
        // automatic light/dark adaptation. Use attributed strings instead.
        button.contentTintColor = nil

        if overdueCount > 0 {
            button.attributedTitle = NSAttributedString(
                string: " \(overdueCount)",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
        } else if dueTodayCount > 0 {
            button.attributedTitle = NSAttributedString(
                string: " \(dueTodayCount)",
                attributes: [.foregroundColor: NSColor.systemOrange]
            )
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if overdueCount > 0 {
            let item = NSMenuItem(
                title: "⚠ \(overdueCount) overdue",
                action: #selector(openDue),
                keyEquivalent: ""
            )
            item.target = self
            item.attributedTitle = NSAttributedString(
                string: "⚠ \(overdueCount) overdue",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
            menu.addItem(item)
        }
        if dueTodayCount > 0 {
            let item = NSMenuItem(
                title: "📅 \(dueTodayCount) due today",
                action: #selector(openDue),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }
        if inboxCount > 0 {
            let item = NSMenuItem(
                title: "📥 \(inboxCount) in inbox",
                action: #selector(openProcess),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }

        if overdueCount > 0 || dueTodayCount > 0 || inboxCount > 0 {
            menu.addItem(NSMenuItem.separator())
        }

        let captureItem = NSMenuItem(
            title: "Quick Capture…",
            action: #selector(openCapture),
            keyEquivalent: "n"
        )
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        captureItem.target = self
        menu.addItem(captureItem)

        menu.addItem(NSMenuItem.separator())

        let syncItem = NSMenuItem(
            title: "Sync Now",
            action: #selector(syncNow),
            keyEquivalent: "s"
        )
        syncItem.keyEquivalentModifierMask = [.command]
        syncItem.target = self
        menu.addItem(syncItem)

        if let lastSync = lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let relative = formatter.localizedString(for: lastSync, relativeTo: Date())
            let syncInfo = NSMenuItem(title: "Last sync: \(relative)", action: nil, keyEquivalent: "")
            syncInfo.isEnabled = false
            menu.addItem(syncInfo)
        }

        menu.addItem(NSMenuItem.separator())

        let boardItem = NSMenuItem(
            title: "Open Board in Terminal",
            action: #selector(openBoard),
            keyEquivalent: "b"
        )
        boardItem.keyEquivalentModifierMask = [.command]
        boardItem.target = self
        menu.addItem(boardItem)

        let reviewItem = NSMenuItem(
            title: "Weekly Review in Terminal",
            action: #selector(openReview),
            keyEquivalent: "r"
        )
        reviewItem.keyEquivalentModifierMask = [.command]
        reviewItem.target = self
        menu.addItem(reviewItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Forge",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Background Sync

    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(
            withTimeInterval: syncInterval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.performBackgroundSync()
            }
        }
        performBackgroundSync()
    }

    private func performBackgroundSync() {
        guard let config = config else { return }

        Task { @MainActor in
            do {
                let engine = SyncEngine(config: config, forgeDir: self.forgeDir)
                let report = try await engine.sync()
                lastSyncDate = Date()
                refreshCounts()

                if report.inboxItemsAdded > 0 {
                    sendNotification(
                        title: "Forge",
                        body: "\(report.inboxItemsAdded) new item(s) captured from Reminders"
                    )
                }
            } catch {
                rebuildMenu()
            }
        }
    }

    // MARK: - Refresh Counts

    private func refreshCounts() {
        let markdownIO = MarkdownIO()
        let fm = FileManager.default

        var overdue = 0
        var dueToday = 0

        let taskFiles = TaskFileFinder.findAllUnderDocuments()
        for file in taskFiles {
            let tasks = (try? markdownIO.parseTasks(at: file.path)) ?? []
            for task in tasks where !task.isCompleted {
                if task.isOverdue { overdue += 1 }
                if task.isDueToday { dueToday += 1 }
            }
        }

        overdueCount = overdue
        dueTodayCount = dueToday

        if let config = config {
            let resolvedForgeDir = forgeDir ?? (config.resolvedWorkspacePath as NSString).appendingPathComponent("Forge")
            let inboxPath = (resolvedForgeDir as NSString).appendingPathComponent("inbox.md")
            if fm.fileExists(atPath: inboxPath) {
                let inboxTasks = markdownIO.parseTasks(
                    from: (try? String(contentsOfFile: inboxPath, encoding: .utf8)) ?? ""
                )
                inboxCount = inboxTasks.filter { !$0.isCompleted }.count
            } else {
                inboxCount = 0
            }
        } else {
            inboxCount = 0
        }

        updateBadge()
        rebuildMenu()
    }

    // MARK: - Actions

    @objc private func openCapture() {
        if capturePanel == nil {
            capturePanel = CapturePanel { [weak self] text in
                self?.captureToInbox(text: text)
            }
        }
        capturePanel?.show()
    }

    private func captureToInbox(text: String) {
        guard let config = config else { return }
        let resolvedForgeDir = forgeDir ?? (config.resolvedWorkspacePath as NSString).appendingPathComponent("Forge")
        let inboxPath = (resolvedForgeDir as NSString).appendingPathComponent("inbox.md")
        let markdownIO = MarkdownIO()
        let task = ForgeTask(id: ForgeTask.newID(), text: text, section: .nextActions)
        try? markdownIO.appendTask(task, toFileAt: inboxPath)
        inboxCount += 1
        updateBadge()
        rebuildMenu()
        sendNotification(title: "Forge", body: "Captured: \(text)")
    }

    @objc private func syncNow() {
        performBackgroundSync()
    }

    @objc private func openDue() {
        guard let config = config else { return }
        NSApp.activate(ignoringOtherApps: true)
        let launcher = TerminalLauncher(config: config)
        launcher.run("forge due", workingDirectory: config.resolvedWorkspacePath)
    }

    @objc private func openBoard() {
        guard let config = config else { return }
        NSApp.activate(ignoringOtherApps: true)
        let launcher = TerminalLauncher(config: config)
        launcher.run("forge board", workingDirectory: config.resolvedWorkspacePath)
    }

    @objc private func openProcess() {
        guard let config = config else { return }
        NSApp.activate(ignoringOtherApps: true)
        let launcher = TerminalLauncher(config: config)
        launcher.run("forge process", workingDirectory: config.resolvedWorkspacePath)
    }

    @objc private func openReview() {
        guard let config = config else { return }
        NSApp.activate(ignoringOtherApps: true)
        let launcher = TerminalLauncher(config: config)
        launcher.run("forge review", workingDirectory: config.resolvedWorkspacePath)
    }

    @objc private func quit() {
        syncTimer?.invalidate()
        NSApp.terminate(nil)
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        let script = """
        display notification "\(body.replacingOccurrences(of: "\"", with: "\\\""))" with title "\(title)"
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }
}
