import AppKit
import ForgeCore
import ForgeUI
import UserNotifications

/// Manages the menu bar status item, background sync timer, and menu actions.
@MainActor
final class StatusBarController: NSObject {

    private var statusItem: NSStatusItem!
    private var syncTimer: Timer?
    private var config: ForgeConfig?
    private var forgeDir: String?
    private var capturePanel: CapturePanel?
    private var boardWindowController: BoardWindowController?

    private var syncProgressWindow: NSWindow?
    private var hasShownInitialSyncWindow = false

    private var overdueCount = 0
    private var dueTodayCount = 0
    private var inboxCount = 0
    private var lastSyncDate: Date?

    /// Cache of (mtime, overdue, dueToday) per task file path to avoid re-parsing unchanged files.
    private var countsCache: [String: (mtime: Date, overdue: Int, dueToday: Int)] = [:]

    /// Sync interval in seconds (default: 5 minutes).
    private let syncInterval: TimeInterval = 300

    /// Favourite assignees for quick delegation-related menu entries. These should match
    /// the canonical person identifiers derived from #Person Finder tags (without the #).
    private let favouriteAssignees: [String] = []

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    func start() {
        loadConfig()
        setupStatusItem()
        refreshCounts()
        startSyncTimer()
        requestNotificationPermissionIfNeeded()
        if config != nil {
            openBoardWindow()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutPreferencesDidChange),
            name: ShortcutPreferences.didChangeNotification,
            object: nil
        )
    }

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    @objc private func shortcutPreferencesDidChange() {
        rebuildMenu()
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
            keyEquivalent: ShortcutPreferences.spec(for: .quickCapture).keyEquivalent
        )
        captureItem.keyEquivalentModifierMask = ShortcutPreferences.spec(for: .quickCapture).modifierFlags
        captureItem.target = self
        menu.addItem(captureItem)

        let captureSelectionSpec = ShortcutPreferences.spec(for: .captureSelection)
        let captureSelectionItem = NSMenuItem(
            title: "Capture Selection to Inbox",
            action: #selector(captureSelectionToInboxFromMenu),
            keyEquivalent: captureSelectionSpec.keyEquivalent
        )
        captureSelectionItem.keyEquivalentModifierMask = captureSelectionSpec.modifierFlags
        captureSelectionItem.target = self
        menu.addItem(captureSelectionItem)

        menu.addItem(NSMenuItem.separator())

        let syncSpec = ShortcutPreferences.spec(for: .syncNow)
        let syncItem = NSMenuItem(
            title: "Sync Now",
            action: #selector(syncNow),
            keyEquivalent: syncSpec.keyEquivalent
        )
        syncItem.keyEquivalentModifierMask = syncSpec.modifierFlags
        syncItem.target = self
        menu.addItem(syncItem)

        if let lastSync = lastSyncDate {
            let relative = Self.relativeDateFormatter.localizedString(for: lastSync, relativeTo: Date())
            let syncInfo = NSMenuItem(title: "Last sync: \(relative)", action: nil, keyEquivalent: "")
            syncInfo.isEnabled = false
            menu.addItem(syncInfo)
        }

        menu.addItem(NSMenuItem.separator())

        if config != nil {
            let boardSpec = ShortcutPreferences.spec(for: .openBoard)
            let boardItem = NSMenuItem(
                title: "Board",
                action: #selector(openBoardWindow),
                keyEquivalent: boardSpec.keyEquivalent
            )
            boardItem.keyEquivalentModifierMask = boardSpec.modifierFlags
            boardItem.target = self
            menu.addItem(boardItem)

            let delegationMenu = NSMenu()
            for name in favouriteAssignees {
                let boardForAssignee = NSMenuItem(
                    title: "Board for #\(name)",
                    action: #selector(openBoardForAssignee(_:)),
                    keyEquivalent: ""
                )
                boardForAssignee.representedObject = name
                boardForAssignee.target = self
                delegationMenu.addItem(boardForAssignee)

                let nextForAssignee = NSMenuItem(
                    title: "Next actions for #\(name)",
                    action: #selector(openNextForAssignee(_:)),
                    keyEquivalent: ""
                )
                nextForAssignee.representedObject = name
                nextForAssignee.target = self
                delegationMenu.addItem(nextForAssignee)

                let waitingForAssignee = NSMenuItem(
                    title: "Waiting for #\(name)",
                    action: #selector(openWaitingForAssignee(_:)),
                    keyEquivalent: ""
                )
                waitingForAssignee.representedObject = name
                waitingForAssignee.target = self
                delegationMenu.addItem(waitingForAssignee)

                delegationMenu.addItem(NSMenuItem.separator())
            }
            if !favouriteAssignees.isEmpty {
                let delegationItem = NSMenuItem(title: "Delegation", action: nil, keyEquivalent: "")
                delegationItem.submenu = delegationMenu
                menu.addItem(delegationItem)
            }
        }

        let boardTerminalItem = NSMenuItem(
            title: "Open Board in Terminal",
            action: #selector(openBoardInTerminal),
            keyEquivalent: ""
        )
        boardTerminalItem.target = self
        menu.addItem(boardTerminalItem)

        let editTasksItem = NSMenuItem(
            title: "Edit task files…",
            action: #selector(openTaskFilesFolder),
            keyEquivalent: ""
        )
        editTasksItem.target = self
        editTasksItem.toolTip = "Open inbox, area files, and someday list in your default editor"
        menu.addItem(editTasksItem)

        let reviewSpec = ShortcutPreferences.spec(for: .weeklyReview)
        let reviewItem = NSMenuItem(
            title: "Weekly Review in Terminal",
            action: #selector(openReview),
            keyEquivalent: reviewSpec.keyEquivalent
        )
        reviewItem.keyEquivalentModifierMask = reviewSpec.modifierFlags
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

        // On first sync after launch, show a small non-blocking window so it is clear that
        // Forge is performing an initial background sync with Reminders and Calendar.
        if lastSyncDate == nil {
            showInitialSyncWindowIfNeeded()
        }

        Task { @MainActor in
            do {
                guard let forgeDir = self.forgeDir else { return }
                let paths = ForgePaths(forgeDir: forgeDir)
                let db = try TaskFileDatabase(forgeDir: forgeDir)
                let index = DatabaseTaskIndex(database: db)
                let engine = SyncEngine(
                    config: config,
                    forgeDir: forgeDir,
                    taskFilesRoot: paths.taskFilesRoot,
                    options: .background,
                    taskIndex: index
                )
                let report = try await engine.sync()
                lastSyncDate = Date()
                hideSyncProgressWindow()
                refreshCounts()

                if report.inboxItemsAdded > 0 {
                    sendNotification(
                        title: "Forge",
                        body: "\(report.inboxItemsAdded) new item(s) captured from Reminders"
                    )
                }
            } catch {
                hideSyncProgressWindow()
                rebuildMenu()
            }
        }
    }

    private func showInitialSyncWindowIfNeeded() {
        guard !hasShownInitialSyncWindow else { return }
        hasShownInitialSyncWindow = true

        let contentRect = NSRect(x: 0, y: 0, width: 220, height: 220)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Forge"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear

        let label = NSTextField(labelWithString: "Initial sync in progress…")
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)

        let contentView = NSView(frame: contentRect)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 16
        contentView.layer?.masksToBounds = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.97).cgColor
        contentView.addSubview(iconView)
        contentView.addSubview(label)
        contentView.addSubview(spinner)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            iconView.widthAnchor.constraint(equalToConstant: 96),
            iconView.heightAnchor.constraint(equalToConstant: 96),
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8)
        ])

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - contentRect.width / 2
            let y = frame.midY - contentRect.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        syncProgressWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func hideSyncProgressWindow() {
        syncProgressWindow?.orderOut(nil)
        syncProgressWindow = nil
    }

    // MARK: - Refresh Counts

    private func refreshCounts() {
        let config = self.config
        let forgeDir = self.forgeDir
        var cache = self.countsCache
        Task {
            let (overdue, dueToday, inbox) = Self.computeCounts(config: config, forgeDir: forgeDir, cache: &cache)
            await MainActor.run {
                self.countsCache = cache
                self.overdueCount = overdue
                self.dueTodayCount = dueToday
                self.inboxCount = inbox
                self.updateBadge()
                self.rebuildMenu()
            }
        }
    }

    /// Runs off the main actor to avoid blocking the menu. When config is present, scopes to workspace only.
    /// Uses cache to skip re-parsing task files whose mtime hasn't changed.
    private static func computeCounts(
        config: ForgeConfig?,
        forgeDir: String?,
        cache: inout [String: (mtime: Date, overdue: Int, dueToday: Int)]
    ) -> (Int, Int, Int) {
        let markdownIO = MarkdownIO()
        let fm = FileManager.default

        let taskFiles: [(path: String, label: String)]
        if let config = config {
            if let forgeDir = forgeDir,
               let db = try? TaskFileDatabase(forgeDir: forgeDir) {
                let index = DatabaseTaskIndex(database: db)
                try? index.refreshIfNeeded(config: config, forgeDir: forgeDir)
                taskFiles = index.projectTaskFiles(for: config).map { info in
                    (path: info.path, label: info.projectName)
                }
            } else {
                taskFiles = []
            }
        } else {
            taskFiles = TaskFileFinder.findAllUnderDocuments().map { file in
                (path: file.path, label: file.label)
            }
        }

        var overdue = 0
        var dueToday = 0

        for file in taskFiles {
            let mtime: Date
            do {
                let attrs = try fm.attributesOfItem(atPath: file.path)
                mtime = (attrs[.modificationDate] as? Date) ?? .distantPast
            } catch {
                mtime = .distantPast
            }
            if let cached = cache[file.path], cached.mtime == mtime {
                overdue += cached.overdue
                dueToday += cached.dueToday
                continue
            }
            var fileOverdue = 0
            var fileDueToday = 0
            let tasks = (try? markdownIO.parseTasks(at: file.path)) ?? []
            for task in tasks where !task.isCompleted {
                if task.isOverdue { fileOverdue += 1 }
                if task.isDueToday { fileDueToday += 1 }
            }
            cache[file.path] = (mtime, fileOverdue, fileDueToday)
            overdue += fileOverdue
            dueToday += fileDueToday
        }

        // Include area files (markdown in task files root), same as `forge due`.
        if let _ = config, let forgeDir = forgeDir {
            let taskRoot = ForgePaths(forgeDir: forgeDir).taskFilesRoot
            let excludedAreaFiles: Set<String> = ["config.yaml", "someday-maybe.md", "inbox.md"]
            if let entries = try? fm.contentsOfDirectory(atPath: taskRoot) {
                for entry in entries where entry.hasSuffix(".md") && !excludedAreaFiles.contains(entry) {
                    let path = (taskRoot as NSString).appendingPathComponent(entry)
                    let mtime: Date
                    do {
                        let attrs = try fm.attributesOfItem(atPath: path)
                        mtime = (attrs[.modificationDate] as? Date) ?? .distantPast
                    } catch {
                        mtime = .distantPast
                    }
                    if let cached = cache[path], cached.mtime == mtime {
                        overdue += cached.overdue
                        dueToday += cached.dueToday
                        continue
                    }
                    var fileOverdue = 0
                    var fileDueToday = 0
                    let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                    let tasks = markdownIO.parseTasks(from: content)
                    for task in tasks where !task.isCompleted {
                        if task.isOverdue { fileOverdue += 1 }
                        if task.isDueToday { fileDueToday += 1 }
                    }
                    cache[path] = (mtime, fileOverdue, fileDueToday)
                    overdue += fileOverdue
                    dueToday += fileDueToday
                }
            }
        }

        var inboxCount = 0
        if let _ = config, let forgeDir = forgeDir {
            let inboxPath = ForgePaths(forgeDir: forgeDir).inboxPath
            if fm.fileExists(atPath: inboxPath) {
                let inboxTasks = markdownIO.parseTasks(
                    from: (try? String(contentsOfFile: inboxPath, encoding: .utf8)) ?? ""
                )
                inboxCount = inboxTasks.filter { !$0.isCompleted }.count
            }
        }

        return (overdue, dueToday, inboxCount)
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

    /// Exposed for main menu "New Quick Capture" (⇧⌘N).
    @objc func showQuickCapture() {
        openCapture()
    }

    /// Captures the current selection from Mail (selected message) or Finder (selected file/folder)
    /// and adds it as an inbox task with a clickable link. Invoked by ⌃⌥⌘. or the File menu.
    @objc func captureSelectionToInbox() {
        guard config != nil else { return }
        guard let item = SelectionCapture.captureFromFrontmostApplication() else {
            sendNotification(title: "Forge", body: "No selection. Select an email in Mail or a file in Finder, then try again.")
            return
        }
        let taskText = SelectionCapture.taskText(for: item)
        captureToInbox(text: taskText)
    }

    @objc private func captureSelectionToInboxFromMenu() {
        captureSelectionToInbox()
    }

    private func captureToInbox(text: String) {
        guard let _ = config, let forgeDir = forgeDir else { return }
        try? ForgePaths(forgeDir: forgeDir).ensureTaskFilesDirectoryExists()
        let inboxPath = ForgePaths(forgeDir: forgeDir).inboxPath
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
        let launcher = TerminalLauncher(config: config, openURL: { NSWorkspace.shared.open($0) })
        launcher.run("forge due", workingDirectory: config.resolvedWorkspacePath)
    }

    @objc private func openBoardWindow() {
        guard let config = config else { return }
        if boardWindowController == nil {
            boardWindowController = BoardWindowController(config: config, forgeDir: forgeDir)
        }
        boardWindowController?.showWindow()
    }

    @objc func openTaskFilesFolder() {
        guard let config = config, let forgeDir = forgeDir else { return }
        let paths = ForgePaths(forgeDir: forgeDir)
        try? paths.ensureTaskFilesDirectoryExists()
        let taskFilesRoot = (paths.taskFilesRoot as NSString).standardizingPath
        let folderURL = URL(fileURLWithPath: taskFilesRoot).standardizedFileURL
        let editor = EditorPreferences.loadPreferredEditor()
        if editor == nil || editor == "default" || editor?.isEmpty == true {
            NSWorkspace.shared.open(folderURL)
            return
        }
        switch editor! {
        case "Vim (in default terminal)":
            let launcher = TerminalLauncher(config: config, terminalOverride: nil, openURL: { NSWorkspace.shared.open($0) })
            let escaped = taskFilesRoot.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            launcher.run("zsh -i -c 'vim \"\(escaped)\"'", workingDirectory: taskFilesRoot)
        case "Cursor", "Visual Studio Code", "TextEdit", "Sublime Text":
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", editor!, taskFilesRoot]
            process.qualityOfService = .userInitiated
            try? process.run()
        default:
            NSWorkspace.shared.open(folderURL)
        }
    }

    @objc private func openBoardInTerminal() {
        guard let config = config else { return }
        NSApp.activate(ignoringOtherApps: true)
        let launcher = TerminalLauncher(config: config, openURL: { NSWorkspace.shared.open($0) })
        launcher.run("forge board", workingDirectory: config.resolvedWorkspacePath)
    }

    @objc private func openBoardForAssignee(_ sender: NSMenuItem) {
        guard let config = config,
              let name = sender.representedObject as? String else { return }
        NSApp.activate(ignoringOtherApps: true)
        let launcher = TerminalLauncher(config: config, openURL: { NSWorkspace.shared.open($0) })
        launcher.run("forge board --assignee \(name)", workingDirectory: config.resolvedWorkspacePath)
    }

    @objc private func openNextForAssignee(_ sender: NSMenuItem) {
        guard let config = config,
              let name = sender.representedObject as? String else { return }
        NSApp.activate(ignoringOtherApps: true)
        let launcher = TerminalLauncher(config: config, openURL: { NSWorkspace.shared.open($0) })
        launcher.run("forge next --assignee \(name)", workingDirectory: config.resolvedWorkspacePath)
    }

    @objc private func openWaitingForAssignee(_ sender: NSMenuItem) {
        guard let config = config,
              let name = sender.representedObject as? String else { return }
        NSApp.activate(ignoringOtherApps: true)
        let launcher = TerminalLauncher(config: config, openURL: { NSWorkspace.shared.open($0) })
        launcher.run("forge waiting --assignee \(name)", workingDirectory: config.resolvedWorkspacePath)
    }

    @objc private func openProcess() {
        guard let config = config else { return }
        NSApp.activate(ignoringOtherApps: true)
        let launcher = TerminalLauncher(config: config, openURL: { NSWorkspace.shared.open($0) })
        launcher.run("forge process", workingDirectory: config.resolvedWorkspacePath)
    }

    @objc private func openReview() {
        guard let config = config else { return }
        NSApp.activate(ignoringOtherApps: true)
        let launcher = TerminalLauncher(config: config, openURL: { NSWorkspace.shared.open($0) })
        launcher.run("forge review", workingDirectory: config.resolvedWorkspacePath)
    }

    @objc private func quit() {
        syncTimer?.invalidate()
        NSApp.terminate(nil)
    }

    // MARK: - Notifications

    /// Requests notification permission if not yet determined, then delivers the notification when permitted.
    /// Falls back to AppleScript when permission is denied (e.g. running from Xcode without notification entitlement).
    private func sendNotification(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                Self.deliverNotification(title: title, body: body)
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        Self.deliverNotification(title: title, body: body)
                    } else {
                        Self.deliverNotificationViaAppleScript(title: title, body: body)
                    }
                }
            case .denied, .ephemeral:
                Self.deliverNotificationViaAppleScript(title: title, body: body)
            @unknown default:
                Self.deliverNotificationViaAppleScript(title: title, body: body)
            }
        }
    }

    private static nonisolated func deliverNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private static nonisolated func deliverNotificationViaAppleScript(title: String, body: String) {
        let escapedBody = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedBody)\" with title \"\(title)\""
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }
}
