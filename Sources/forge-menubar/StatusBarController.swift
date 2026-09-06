import AppKit
import ForgeCore
import ForgeUI
import UserNotifications

/// Manages the menu bar status item and menu actions.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var config: ForgeConfig?
    private var forgeDir: String?
    private var boardWindowController: BoardWindowController?
    private var omnifocusAlignWindowController: OmniFocusAlignWindowController?
    private var dashboardPopoverController: DashboardPopoverController?
    private var capturePopoverController: CapturePopoverController?
    private var remindersRefreshTimer: Timer?
    private var globalShortcutMonitor: Any?
    private var localShortcutMonitor: Any?

    /// We keep a single menu instance and mutate it in-place. Replacing `statusItem.menu`
    /// while the menu is open does not update the visible dropdown (macOS continues showing
    /// the previously-tracked `NSMenu` instance).
    private let statusMenu = NSMenu()

    private var urgentProjectCount = 0

    /// Favourite assignees for quick delegation-related menu entries. These should match
    /// the canonical person identifiers derived from #Person Finder tags (without the #).
    private let favouriteAssignees: [String] = []

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private let isRunningFromAppBundle = Bundle.main.bundleURL.pathExtension == "app"

    func start() {
        loadConfig()
        setupStatusItem()
        requestNotificationPermissionIfNeeded()
        if config != nil {
            openBoardWindow()
        }
        scheduleRemindersSnapshotRefresh()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutPreferencesDidChange),
            name: ShortcutPreferences.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configDidChange),
            name: .forgeConfigDidChange,
            object: nil
        )
    }

    @objc private func configDidChange(_ note: Notification) {
        loadConfig()
        rebuildMenu()
        scheduleRemindersSnapshotRefresh()
        guard let config else {
            boardWindowController?.closeWindow()
            boardWindowController = nil
            return
        }
        if let board = boardWindowController, board.isWindowVisible {
            board.reload(config: config, forgeDir: forgeDir)
        } else {
            boardWindowController = nil
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        guard isRunningFromAppBundle else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    @objc private func shortcutPreferencesDidChange() {
        rebuildMenu()
        installGlobalShortcutMonitor()
    }

    private func installGlobalShortcutMonitor() {
        if let globalShortcutMonitor {
            NSEvent.removeMonitor(globalShortcutMonitor)
            self.globalShortcutMonitor = nil
        }
        if let localShortcutMonitor {
            NSEvent.removeMonitor(localShortcutMonitor)
            self.localShortcutMonitor = nil
        }
        let captureSpec = ShortcutPreferences.spec(for: .capture)
        globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard ShortcutPreferences.eventMatches(event, spec: captureSpec) else { return }
            Task { @MainActor in
                self?.openCapture()
            }
        }
        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard ShortcutPreferences.eventMatches(event, spec: captureSpec) else { return event }
            Task { @MainActor in
                self?.openCapture()
            }
            return nil
        }
    }

    // MARK: - Configuration

    private func loadConfig() {
        let home = NSHomeDirectory()
        let preferredKey = "forge.config.path"
        if let preferred = UserDefaults.standard.string(forKey: preferredKey) {
            if FileManager.default.fileExists(atPath: preferred),
               let cfg = try? ForgeConfig.load(from: preferred) {
                config = cfg
                forgeDir = (preferred as NSString).deletingLastPathComponent
                dashboardPopoverController?.updateForgeDir(forgeDir)
                capturePopoverController?.updateForgeDir(forgeDir)
                return
            }
            // Stale path (e.g. legacy ~/Documents/Forge) — clear so search finds Software/Forge.
            UserDefaults.standard.removeObject(forKey: preferredKey)
        }
        let candidates = ForgePaths.configCandidatePaths(home: home)
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                config = try? ForgeConfig.load(from: candidate)
                forgeDir = (candidate as NSString).deletingLastPathComponent
                UserDefaults.standard.set(candidate, forKey: preferredKey)
                dashboardPopoverController?.updateForgeDir(forgeDir)
                capturePopoverController?.updateForgeDir(forgeDir)
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
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let dashboard = DashboardPopoverController()
        dashboard.onOpenBoard = { [weak self] in self?.openBoardWindow() }
        dashboard.updateForgeDir(forgeDir)
        dashboardPopoverController = dashboard

        let capture = CapturePopoverController()
        capture.updateForgeDir(forgeDir)
        capturePopoverController = capture

        statusMenu.delegate = self
        rebuildMenu()
        installGlobalShortcutMonitor()
    }

    private func updateBadge() {
        guard let button = statusItem.button else { return }

        // Never set contentTintColor — it overrides the template image's
        // automatic light/dark adaptation. Use attributed strings instead.
        button.contentTintColor = nil

        if urgentProjectCount > 0 {
            button.attributedTitle = NSAttributedString(
                string: " \(urgentProjectCount)",
                attributes: [.foregroundColor: NSColor.systemRed]
            )
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    private func rebuildMenu() {
        let menu = statusMenu
        menu.removeAllItems()

        if config == nil {
            let item = NSMenuItem(title: "No config loaded — create config.yaml in ~/Documents/Software/Forge", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(NSMenuItem.separator())
        }

        if config != nil {
            let item = NSMenuItem(
                title: urgentProjectCount > 0 ? "⚠ \(urgentProjectCount) URGENT project(s)" : "No URGENT projects",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(NSMenuItem.separator())
        }

        if config != nil {
            let captureSpec = ShortcutPreferences.spec(for: .capture)
            let captureItem = NSMenuItem(
                title: "Capture…",
                action: #selector(openCapture),
                keyEquivalent: captureSpec.keyEquivalent
            )
            captureItem.keyEquivalentModifierMask = captureSpec.modifierFlags
            captureItem.target = self
            menu.addItem(captureItem)

            let dashboardItem = NSMenuItem(
                title: "Dashboard…",
                action: #selector(openDashboard),
                keyEquivalent: "d"
            )
            dashboardItem.keyEquivalentModifierMask = [.command, .shift]
            dashboardItem.target = self
            menu.addItem(dashboardItem)

            let boardSpec = ShortcutPreferences.spec(for: .openBoard)
            let boardItem = NSMenuItem(
                title: "Board",
                action: #selector(openBoardWindow),
                keyEquivalent: boardSpec.keyEquivalent
            )
            boardItem.keyEquivalentModifierMask = boardSpec.modifierFlags
            boardItem.target = self
            menu.addItem(boardItem)

            if config?.omnifocus.enabled == true {
                let alignItem = NSMenuItem(
                    title: "OmniFocus Align…",
                    action: #selector(openOmniFocusAlign),
                    keyEquivalent: ""
                )
                alignItem.target = self
                menu.addItem(alignItem)
            }

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

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Forge",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshUrgentCount()
    }

    // MARK: - Reminders snapshot

    private func scheduleRemindersSnapshotRefresh() {
        remindersRefreshTimer?.invalidate()
        remindersRefreshTimer = nil
        guard let config, config.reminders.enabled else { return }
        refreshRemindersSnapshotInBackground()
        let interval = max(60, config.reminders.snapshotMaxAgeSeconds)
        remindersRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRemindersSnapshotInBackground()
            }
        }
    }

    private func refreshRemindersSnapshotInBackground() {
        guard let config, let forgeDir, config.reminders.enabled else { return }
        Task.detached(priority: .utility) {
            do {
                let scanner = WorkspaceScanner(config: config)
                let names = (try? await scanner.scanProjects().map(\.name)) ?? []
                _ = try await RemindersService(config: config).refreshSnapshot(
                    forgeDir: forgeDir,
                    projectNames: names,
                    writer: "Forge.app"
                )
            } catch {
                // Snapshot refresh must not disturb the menu bar UI.
            }
        }
    }

    // MARK: - Actions

    private func refreshUrgentCount() {
        guard let config else {
            urgentProjectCount = 0
            updateBadge()
            rebuildMenu()
            return
        }
        let scanner = WorkspaceScanner(config: config)
        let projects = (try? scanner.scanProjects()) ?? []
        urgentProjectCount = projects.filter { KanbanRadar.isUrgent(metaTags: $0.metaTags) }.count
        updateBadge()
        rebuildMenu()
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            refreshUrgentCount()
            statusMenu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.height + 4),
                in: sender
            )
            return
        }
        dashboardPopoverController?.toggle(relativeTo: sender)
    }

    @objc private func openDashboard() {
        guard let button = statusItem.button else { return }
        dashboardPopoverController?.toggle(relativeTo: button)
    }

    @objc func openCapture() {
        guard let button = statusItem.button else { return }
        capturePopoverController?.toggle(relativeTo: button)
    }

    @objc private func openOmniFocusAlign() {
        guard let config, let forgeDir, config.omnifocus.enabled else { return }
        Task {
            do {
                let plan = try await OmniFocusAlignWindowController.loadPlan(
                    config: config,
                    forgeDir: forgeDir
                )
                await MainActor.run {
                    let controller = OmniFocusAlignWindowController(
                        config: config,
                        forgeDir: forgeDir,
                        plan: plan
                    )
                    self.omnifocusAlignWindowController = controller
                    controller.showWindow(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "OmniFocus Align"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    func showBoardWindow() {
        openBoardWindow()
    }

    @objc private func openBoardWindow() {
        guard let config = config else { return }
        if boardWindowController == nil {
            boardWindowController = BoardWindowController(config: config, forgeDir: forgeDir)
        }
        boardWindowController?.showWindow()
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

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Notifications

    /// Requests notification permission if not yet determined, then delivers the notification when permitted.
    /// Falls back to AppleScript when permission is denied (e.g. running from Xcode without notification entitlement).
    private func sendNotification(title: String, body: String) {
        guard isRunningFromAppBundle else {
            Self.deliverNotificationViaAppleScript(title: title, body: body)
            return
        }
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
