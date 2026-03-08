import AppKit
import ForgeCore

/// Menu bar application delegate. Manages the status item, main menu bar,
/// preferences window, background sync, quick capture, and overdue notifications.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBar: StatusBarController!
    private var preferencesWindowController: PreferencesWindowController?
    private var captureSelectionMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        statusBar.start()
        setupMainMenu()
        setupCaptureSelectionShortcut()
    }

    /// Registers the global shortcut ⌃⌥⌘. to capture the current selection (Mail/Finder) to the inbox.
    /// Requires Accessibility permission for the shortcut to work when another app is frontmost.
    private func setupCaptureSelectionShortcut() {
        captureSelectionMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains([.control, .option, .command]),
                  event.characters == "." else { return }
            Task { @MainActor in
                self?.statusBar.captureSelectionToInbox()
            }
        }
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
        addItem(to: fileMenu, title: "New Quick Capture…", action: #selector(showQuickCapture(_:)), keyEquivalent: "n", modifiers: [.command, .shift])
        addItem(to: fileMenu, title: "Capture Selection to Inbox", action: #selector(captureSelectionToInbox(_:)), keyEquivalent: ".", modifiers: [.control, .option, .command])

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

    @objc private func showHelp(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/forge-app/forge") else { return }
        NSWorkspace.shared.open(url)
    }
}
