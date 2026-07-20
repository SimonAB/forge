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
        if let board = boardWindowController {
            board.closeWindow()
            boardWindowController = nil
        }
        rebuildMenu()
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
    }

    // MARK: - Configuration

    private func loadConfig() {
        let home = NSHomeDirectory()
        if let preferred = UserDefaults.standard.string(forKey: "forge.config.path"),
           FileManager.default.fileExists(atPath: preferred),
           let cfg = try? ForgeConfig.load(from: preferred) {
            config = cfg
            forgeDir = (preferred as NSString).deletingLastPathComponent
            return
        }
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

        statusMenu.delegate = self
        statusItem.menu = statusMenu
        rebuildMenu()
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
            let item = NSMenuItem(title: "No config loaded — create config.yaml in ~/Documents/Forge", action: nil, keyEquivalent: "")
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
