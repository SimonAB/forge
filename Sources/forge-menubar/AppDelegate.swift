import AppKit
import ApplicationServices
import ForgeCore
import UserNotifications

/// Menu bar application delegate. Manages the status item, main menu bar,
/// preferences window, background sync, quick capture, and overdue notifications.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    private var statusBar: StatusBarController!
    private var preferencesWindowController: PreferencesWindowController?
    private var captureSelectionMonitor: Any?
    private var hasShownAccessibilityAlertThisLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        statusBar = StatusBarController()
        statusBar.start()
        setupMainMenu()
        setupCaptureSelectionShortcut()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutPreferencesDidChange(_:)),
            name: ShortcutPreferences.didChangeNotification,
            object: nil
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if captureSelectionMonitor == nil {
            setupCaptureSelectionShortcut()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    @objc private func shortcutPreferencesDidChange(_ notification: Notification) {
        if let mon = captureSelectionMonitor {
            NSEvent.removeMonitor(mon)
            captureSelectionMonitor = nil
        }
        setupMainMenu()
        setupCaptureSelectionShortcut()
    }

    /// Registers the global shortcut for Capture Selection to Inbox (from ShortcutPreferences).
    /// Requires Accessibility permission; returns nil when permission is missing. Re-try on applicationDidBecomeActive.
    private func setupCaptureSelectionShortcut() {
        let spec = ShortcutPreferences.spec(for: .captureSelection)
        let modMask: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let expectedMods = spec.modifierFlags.intersection(modMask)

        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventMods = event.modifierFlags.intersection(modMask)
            guard eventMods == expectedMods else { return }
            let keyMatches: Bool
            if !spec.keyEquivalent.isEmpty {
                keyMatches = (event.characters == spec.keyEquivalent || event.charactersIgnoringModifiers == spec.keyEquivalent)
            } else {
                keyMatches = event.keyCode == spec.keyCode
            }
            guard keyMatches else { return }
            Task { @MainActor in
                self?.statusBar.captureSelectionToInbox()
            }
        }
        captureSelectionMonitor = monitor

        if monitor == nil {
            promptForAccessibilityIfNeeded()
            showAccessibilityAlertIfNeeded()
            scheduleRetryCaptureSelectionShortcut()
        }
    }

    /// Shows an in-app alert when the global monitor failed. The system dialog from
    /// AXIsProcessTrustedWithOptions is often suppressed (e.g. under Xcode, or sandbox).
    private func showAccessibilityAlertIfNeeded() {
        guard !hasShownAccessibilityAlertThisLaunch else { return }
        hasShownAccessibilityAlertThisLaunch = true

        let appName = ProcessInfo.processInfo.processName
        let alert = NSAlert()
        alert.messageText = "Capture Selection shortcut needs Accessibility"
        alert.informativeText = "The keyboard shortcut for capturing from Finder or Mail only works when \(appName) has Accessibility permission. After each new build you may need to re-enable it.\n\nClick \"Open System Settings\" and turn on \(appName) in the list."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Shows the system Accessibility dialog once when the global monitor could not be installed.
    /// After a recompile, macOS treats the new binary as a different app, so permission must be re-granted.
    private func promptForAccessibilityIfNeeded() {
        let optionPrompt = "AXTrustedCheckOptionPrompt" as CFString
        let options = [optionPrompt: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private var captureSelectionRetryWorkItem: DispatchWorkItem?

    private func scheduleRetryCaptureSelectionShortcut() {
        captureSelectionRetryWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.setupCaptureSelectionShortcut()
            }
        }
        captureSelectionRetryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    // MARK: - Main menu (macOS conventions)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Application menu (Forge)
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Forge"
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        mainMenu.addItem(appMenuItem)
        appMenuItem.submenu = appMenu

        addItem(to: appMenu, title: "About \(appName)", action: #selector(showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        addItem(to: appMenu, title: "Preferences…", action: #selector(showPreferences(_:)), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())

        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        appMenu.addItem(servicesItem)
        servicesItem.submenu = NSMenu() // System populates Services
        appMenu.addItem(NSMenuItem.separator())

        addItem(to: appMenu, title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h", target: .application)
        addItem(to: appMenu, title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h", modifiers: [.command, .option], target: .application)
        addItem(to: appMenu, title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "", target: .application)
        appMenu.addItem(NSMenuItem.separator())
        addItem(to: appMenu, title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q", target: .application)

        // File
        let fileMenu = NSMenu(title: "File")
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        mainMenu.addItem(fileMenuItem)
        fileMenuItem.submenu = fileMenu
        let quickCaptureSpec = ShortcutPreferences.spec(for: .quickCapture)
        let captureSelectionSpec = ShortcutPreferences.spec(for: .captureSelection)
        addItem(to: fileMenu, title: "New Quick Capture…", action: #selector(showQuickCapture(_:)), keyEquivalent: quickCaptureSpec.keyEquivalent, modifiers: quickCaptureSpec.modifierFlags)
        addItem(to: fileMenu, title: "Capture Selection to Inbox", action: #selector(captureSelectionToInbox(_:)), keyEquivalent: captureSelectionSpec.keyEquivalent, modifiers: captureSelectionSpec.modifierFlags)
        addItem(to: fileMenu, title: "Edit task files…", action: #selector(editTaskFiles(_:)), keyEquivalent: "e", modifiers: [.command, .shift])

        // Edit
        let editMenu = NSMenu(title: "Edit")
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)
        editMenuItem.submenu = editMenu
        addItem(to: editMenu, title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x", target: .firstResponder)
        addItem(to: editMenu, title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c", target: .firstResponder)
        addItem(to: editMenu, title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v", target: .firstResponder)
        addItem(to: editMenu, title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a", target: .firstResponder)
        editMenu.addItem(NSMenuItem.separator())
        addItem(to: editMenu, title: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu()
        editMenu.items.last?.submenu = findMenu
        addItem(to: findMenu, title: "Find…", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "f", target: .firstResponder)
        addItem(to: findMenu, title: "Find Next", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "g", target: .firstResponder)
        addItem(to: findMenu, title: "Find Previous", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "g", modifiers: [.command, .shift], target: .firstResponder)

        // Window
        let windowMenu = NSMenu(title: "Window")
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        mainMenu.addItem(windowMenuItem)
        windowMenuItem.submenu = windowMenu
        addItem(to: windowMenu, title: "Minimise", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m", target: .firstResponder)
        addItem(to: windowMenu, title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "", target: .firstResponder)
        windowMenu.addItem(NSMenuItem.separator())
        addItem(to: windowMenu, title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "", target: .application)

        // Help
        let helpMenu = NSMenu(title: "Help")
        let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        mainMenu.addItem(helpMenuItem)
        helpMenuItem.submenu = helpMenu
        addItem(to: helpMenu, title: "\(appName) Help", action: #selector(showHelp(_:)), keyEquivalent: "?")

        NSApp.mainMenu = mainMenu
    }

    /// Target for menu item actions: app delegate (self), first responder (nil), or NSApplication.
    private enum MenuTarget {
        case delegate
        case firstResponder
        case application
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector?, keyEquivalent: String, modifiers: NSEvent.ModifierFlags = .command, target: MenuTarget = .delegate) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        switch target {
        case .delegate: item.target = self
        case .firstResponder: item.target = nil
        case .application: item.target = NSApp
        }
        menu.addItem(item)
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(string: "GTD-style task management with markdown and native tags."),
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© Forge",
        ])
    }

    @objc private func showPreferences(_ sender: Any?) {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow()
    }

    @objc private func showQuickCapture(_ sender: Any?) {
        statusBar.showQuickCapture()
    }

    @objc private func captureSelectionToInbox(_ sender: Any?) {
        statusBar.captureSelectionToInbox()
    }

    @objc private func editTaskFiles(_ sender: Any?) {
        statusBar.openTaskFilesFolder()
    }

    @objc private func showHelp(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/forge-app/forge") else { return }
        NSWorkspace.shared.open(url)
    }
}
