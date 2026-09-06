import AppKit
import ForgeCore

/// Preferences window with tabbed panels: General, Board, Brief, Hermes, OmniFocus, Reminders, Workspace, Shortcuts.
final class PreferencesWindowController: NSWindowController {

    static let windowTitle = "Preferences"
    private static let defaultContentSize = NSSize(width: 720, height: 560)
    private static let minimumContentSize = NSSize(width: 640, height: 480)
    private static let userDefaultsConfigPathKey = "forge.config.path"
    private static let configCandidates: [String] = ForgePaths.configCandidatePaths()

    private var configPath: String?
    private var config: ForgeConfig?

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.windowTitle
        window.minSize = Self.minimumContentSize
        window.setContentSize(Self.defaultContentSize)
        window.center()
        super.init(window: window)

        loadConfig()

        let container = NSView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = container

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: container.topAnchor),
            tabView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = "General"
        generalItem.view = PreferencesGeneralView(
            configPath: configPath,
            config: config,
            onSaveTerminal: { [weak self] terminal in
                self?.saveTerminal(terminal) ?? false
            }
        )
        tabView.addTabViewItem(generalItem)

        let boardItem = NSTabViewItem(identifier: "board")
        boardItem.label = "Board"
        boardItem.view = PreferencesBoardView(metaTags: config?.board.metaTags ?? [])
        tabView.addTabViewItem(boardItem)

        let briefItem = NSTabViewItem(identifier: "brief")
        briefItem.label = "Brief"
        briefItem.view = PreferencesBriefView(configPath: configPath, config: config)
        tabView.addTabViewItem(briefItem)

        let hermesItem = NSTabViewItem(identifier: "hermes")
        hermesItem.label = "Hermes"
        hermesItem.view = PreferencesHermesView(configPath: configPath, config: config)
        tabView.addTabViewItem(hermesItem)

        let omnifocusItem = NSTabViewItem(identifier: "omnifocus")
        omnifocusItem.label = "OmniFocus"
        omnifocusItem.view = PreferencesOmniFocusView(
            configPath: configPath,
            config: config,
            onSave: { [weak self] enabled, syncOnMove, syncFromOmnifocus in
                self?.saveOmniFocus(
                    enabled: enabled,
                    syncOnMove: syncOnMove,
                    syncFromOmnifocus: syncFromOmnifocus
                ) ?? false
            }
        )
        tabView.addTabViewItem(omnifocusItem)

        let remindersItem = NSTabViewItem(identifier: "reminders")
        remindersItem.label = "Reminders"
        remindersItem.view = PreferencesRemindersView(
            configPath: configPath,
            forgeDir: configPath.map { ($0 as NSString).deletingLastPathComponent },
            config: config,
            onSave: { [weak self] enabled, list, includeCompleted, syncOnMove, syncFromReminders in
                self?.saveReminders(
                    enabled: enabled,
                    list: list,
                    includeCompleted: includeCompleted,
                    syncOnMove: syncOnMove,
                    syncFromReminders: syncFromReminders
                ) ?? false
            },
            onRefresh: { [weak self] in
                await self?.refreshRemindersSnapshot() ?? "Could not refresh."
            }
        )
        tabView.addTabViewItem(remindersItem)

        let workspaceItem = NSTabViewItem(identifier: "workspace")
        workspaceItem.label = "Workspace"
        workspaceItem.view = PreferencesWorkspaceView(
            projectRoots: config?.projectRoots ?? [],
            configPath: configPath,
            onSave: { [weak self] newRoots in
                self?.saveProjectRoots(newRoots) ?? false
            }
        )
        tabView.addTabViewItem(workspaceItem)

        let shortcutsItem = NSTabViewItem(identifier: "shortcuts")
        shortcutsItem.label = "Shortcuts"
        shortcutsItem.view = PreferencesShortcutsView()
        tabView.addTabViewItem(shortcutsItem)
    }

    private func loadConfig() {
        if let preferred = UserDefaults.standard.string(forKey: Self.userDefaultsConfigPathKey),
           FileManager.default.fileExists(atPath: preferred),
           let cfg = try? ForgeConfig.load(from: preferred) {
            configPath = preferred
            config = cfg
            return
        }
        for path in Self.configCandidates {
            if FileManager.default.fileExists(atPath: path),
               let cfg = try? ForgeConfig.load(from: path) {
                configPath = path
                config = cfg
                return
            }
        }
        configPath = nil
        config = nil
    }

    private func saveProjectRoots(_ newRoots: [String]) -> Bool {
        guard let path = configPath, let current = config else { return false }
        let updated = current.replacing(projectRoots: newRoots)
        do {
            try updated.save(to: path)
            config = updated
            NotificationCenter.default.post(name: .forgeConfigDidChange, object: path)
            return true
        } catch {
            return false
        }
    }

    /// Save terminal preference to config.yaml and update in-memory config.
    private func saveTerminal(_ terminal: String?) -> Bool {
        guard let path = configPath, let current = config else { return false }
        let updated = current.replacing(terminal: .some(terminal))
        do {
            try updated.save(to: path)
            config = updated
            NotificationCenter.default.post(name: .forgeConfigDidChange, object: path)
            return true
        } catch {
            return false
        }
    }

    /// Persist OmniFocus integration flags to config.yaml.
    fileprivate func saveOmniFocus(enabled: Bool, syncOnMove: Bool, syncFromOmnifocus: Bool) -> Bool {
        guard let path = configPath, let current = config else { return false }
        let of = current.omnifocus.updating(
            enabled: enabled,
            syncOnMove: syncOnMove,
            syncFromOmnifocus: syncFromOmnifocus
        )
        let updated = current.replacing(omnifocus: of)
        do {
            try updated.save(to: path)
            config = updated
            NotificationCenter.default.post(name: .forgeConfigDidChange, object: path)
            return true
        } catch {
            return false
        }
    }

    /// Persist Reminders integration flags to config.yaml.
    fileprivate func saveReminders(
        enabled: Bool,
        list: String,
        includeCompleted: Bool,
        syncOnMove: Bool,
        syncFromReminders: Bool
    ) -> Bool {
        guard let path = configPath, let current = config else { return false }
        let rem = current.reminders.updating(
            enabled: enabled,
            list: list,
            includeCompleted: includeCompleted,
            syncOnMove: syncOnMove,
            syncFromReminders: syncFromReminders
        )
        let updated = current.replacing(reminders: rem)
        do {
            try updated.save(to: path)
            config = updated
            NotificationCenter.default.post(name: .forgeConfigDidChange, object: path)
            return true
        } catch {
            return false
        }
    }


    fileprivate func refreshRemindersSnapshot() async -> String {
        guard let path = configPath, let current = config else {
            return "No config.yaml loaded."
        }
        guard current.reminders.enabled else {
            return "Enable Reminders integration first."
        }
        let forgeDir = (path as NSString).deletingLastPathComponent
        do {
            let scanner = WorkspaceScanner(config: current)
            let projects = try await scanner.scanProjects()
            let cfg = current
            let remOut = try await RemindersMoveSync.refreshAndPull(
                config: cfg,
                forgeDir: forgeDir,
                projects: projects,
                writerName: "Forge.app",
                setColumn: { @Sendable project, column in
                    try OmniFocusMoveSync.setFinderWorkflowColumn(
                        path: project.path,
                        column: column,
                        config: cfg,
                        tagStore: FinderTagStore(),
                        forgeDir: forgeDir,
                        folderName: project.name,
                        previousColumn: project.column
                    )
                }
            )
            let summary = RemindersSnapshotStore.statusSummary(forgeDir: forgeDir)
            var parts = [summary]
            if !remOut.paintedColours.isEmpty {
                parts.append("Colours \(remOut.paintedColours.count).")
            }
            if !remOut.paintedPriorities.isEmpty {
                parts.append("URGENT priority \(remOut.paintedPriorities.count).")
            }
            if !remOut.updatedFolders.isEmpty {
                parts.append("Finder columns: \(remOut.updatedFolders.joined(separator: ", ")).")
            }
            if !remOut.errors.isEmpty {
                parts.append(remOut.errors.joined(separator: "; "))
            }
            if KanbanArchivePolicy.isEnabled(config: cfg) {
                let refreshed = try await scanner.scanProjects()
                let sweep = try KanbanArchivePolicy.applyDueArchives(
                    projects: refreshed,
                    config: cfg,
                    forgeDir: forgeDir
                )
                if !sweep.migratedFromLegacyArchived.isEmpty {
                    parts.append("Migrated Archived → Completed: \(sweep.migratedFromLegacyArchived.joined(separator: ", ")).")
                }
                if !sweep.completedFolders.isEmpty {
                    parts.append("Completed: \(sweep.completedFolders.joined(separator: ", ")).")
                }
                if !sweep.errors.isEmpty {
                    parts.append(sweep.errors.joined(separator: "; "))
                }
            }
            let inventory = try RemindersService(config: current).loadEligibleSnapshot(forgeDir: forgeDir)
            if let inventory {
                let forgeOnly = RemindersAlignment.doctor(
                    projects: projects,
                    inventory: inventory,
                    config: current
                ).items.filter { $0.bucket == .forgeOnly }.count
                if forgeOnly > 0 {
                    parts.append("\(forgeOnly) folder(s) have no list — forge reminders align --apply.")
                }
            }
            return parts.joined(separator: " ")
        } catch {
            return error.localizedDescription
        }
    }

    fileprivate func chooseConfigPath() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Select Forge config.yaml"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [] // Allow selecting YAML by name even without UTI.
        panel.prompt = "Select"
        panel.nameFieldStringValue = "config.yaml"
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return false }
        let path = url.path
        guard FileManager.default.fileExists(atPath: path),
              let cfg = try? ForgeConfig.load(from: path) else { return false }
        UserDefaults.standard.set(path, forKey: Self.userDefaultsConfigPathKey)
        configPath = path
        config = cfg
        return true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindow() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - General panel

private final class PreferencesGeneralView: NSView {
    private var editorPopUp: NSPopUpButton?
    private var terminalPopUp: NSPopUpButton?
    private var taskManagerPopUp: NSPopUpButton?
    private let configPath: String?
    private let config: ForgeConfig?
    private let onSaveTerminal: (String?) -> Bool
    private weak var cliStatusLabel: NSTextField?

    override var isFlipped: Bool { true }

    init(configPath: String?, config: ForgeConfig?, onSaveTerminal: @escaping (String?) -> Bool) {
        self.configPath = configPath
        self.config = config
        self.onSaveTerminal = onSaveTerminal
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: "General")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let sub = NSTextField(labelWithString: "Configuration and UI preferences.")
        sub.font = .systemFont(ofSize: 12, weight: .regular)
        sub.textColor = .secondaryLabelColor
        sub.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sub)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            sub.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            sub.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
        ])

        let openConfigButton = NSButton(title: "Open config", target: self, action: #selector(openConfigTapped(_:)))
        openConfigButton.bezelStyle = .rounded
        openConfigButton.translatesAutoresizingMaskIntoConstraints = false
        openConfigButton.isEnabled = configPath != nil
        addSubview(openConfigButton)
        NSLayoutConstraint.activate([
            openConfigButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            openConfigButton.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 16),
        ])

        let chooseConfigButton = NSButton(title: "Choose config…", target: self, action: #selector(chooseConfigTapped(_:)))
        chooseConfigButton.bezelStyle = .rounded
        chooseConfigButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chooseConfigButton)
        NSLayoutConstraint.activate([
            chooseConfigButton.leadingAnchor.constraint(equalTo: openConfigButton.trailingAnchor, constant: 12),
            chooseConfigButton.centerYAnchor.constraint(equalTo: openConfigButton.centerYAnchor),
        ])

        let editorLabel = NSTextField(labelWithString: "Default text editor (for Open config, etc.):")
        editorLabel.font = .systemFont(ofSize: 12, weight: .regular)
        editorLabel.textColor = .secondaryLabelColor
        editorLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(editorLabel)

        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.addItems(withTitles: EditorPreferences.knownEditors)
        let saved = EditorPreferences.loadPreferredEditor()
        let displayTitle = EditorPreferences.displayTitle(forIdentifier: saved)
        if let idx = EditorPreferences.knownEditors.firstIndex(of: displayTitle) {
            popUp.selectItem(at: idx)
        } else {
            popUp.selectItem(at: 0)
        }
        popUp.target = self
        popUp.action = #selector(editorPopUpChanged(_:))
        addSubview(popUp)
        editorPopUp = popUp

        NSLayoutConstraint.activate([
            editorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            editorLabel.topAnchor.constraint(equalTo: openConfigButton.bottomAnchor, constant: 20),
            popUp.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            popUp.topAnchor.constraint(equalTo: editorLabel.bottomAnchor, constant: 6),
            popUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])

        let taskManagerLabel = NSTextField(labelWithString: "Open TASKS opens:")
        taskManagerLabel.font = .systemFont(ofSize: 12, weight: .regular)
        taskManagerLabel.textColor = .secondaryLabelColor
        taskManagerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(taskManagerLabel)

        let taskManagerPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        taskManagerPopUp.translatesAutoresizingMaskIntoConstraints = false
        taskManagerPopUp.addItems(withTitles: TaskManagerPreferences.knownKinds.map(\.title))
        let taskDisplay = TaskManagerPreferences.displayTitle(
            for: TaskManagerPreferences.loadPreferredTaskManager()
        )
        if let idx = TaskManagerPreferences.knownKinds.map(\.title).firstIndex(of: taskDisplay) {
            taskManagerPopUp.selectItem(at: idx)
        } else {
            taskManagerPopUp.selectItem(at: 0)
        }
        taskManagerPopUp.target = self
        taskManagerPopUp.action = #selector(taskManagerPopUpChanged(_:))
        addSubview(taskManagerPopUp)
        self.taskManagerPopUp = taskManagerPopUp

        NSLayoutConstraint.activate([
            taskManagerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            taskManagerLabel.topAnchor.constraint(equalTo: popUp.bottomAnchor, constant: 16),
            taskManagerPopUp.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            taskManagerPopUp.topAnchor.constraint(equalTo: taskManagerLabel.bottomAnchor, constant: 6),
            taskManagerPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])

        let terminalLabel = NSTextField(labelWithString: "Default terminal for Forge CLI actions:")
        terminalLabel.font = .systemFont(ofSize: 12, weight: .regular)
        terminalLabel.textColor = .secondaryLabelColor
        terminalLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalLabel)

        let terminalPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        terminalPopUp.translatesAutoresizingMaskIntoConstraints = false
        terminalPopUp.addItems(withTitles: TerminalPreferences.knownTerminals)
        let terminalDisplayTitle = TerminalPreferences.displayTitle(forConfigValue: config?.terminal)
        if let idx = TerminalPreferences.knownTerminals.firstIndex(of: terminalDisplayTitle) {
            terminalPopUp.selectItem(at: idx)
        } else {
            terminalPopUp.selectItem(at: 0)
        }
        terminalPopUp.target = self
        terminalPopUp.action = #selector(terminalPopUpChanged(_:))
        terminalPopUp.isEnabled = configPath != nil
        addSubview(terminalPopUp)
        self.terminalPopUp = terminalPopUp

        NSLayoutConstraint.activate([
            terminalLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            terminalLabel.topAnchor.constraint(equalTo: taskManagerPopUp.bottomAnchor, constant: 16),
            terminalPopUp.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            terminalPopUp.topAnchor.constraint(equalTo: terminalLabel.bottomAnchor, constant: 6),
            terminalPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])

        // CLI tools
        let cliHeader = NSTextField(labelWithString: "Command-line tool (forge)")
        cliHeader.font = .systemFont(ofSize: 13, weight: .semibold)
        cliHeader.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cliHeader)

        let cliPathLabel = NSTextField(labelWithString: "Embedded CLI:")
        cliPathLabel.font = .systemFont(ofSize: 11, weight: .regular)
        cliPathLabel.textColor = .secondaryLabelColor
        cliPathLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cliPathLabel)

        let cliPathValue = NSTextField(labelWithString: ForgeCliInstaller.embeddedCliPathString())
        cliPathValue.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cliPathValue.textColor = .secondaryLabelColor
        cliPathValue.lineBreakMode = .byTruncatingMiddle
        cliPathValue.maximumNumberOfLines = 1
        cliPathValue.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cliPathValue)

        let installButton = NSButton(title: "Install CLI…", target: self, action: #selector(installCliTapped(_:)))
        installButton.bezelStyle = .rounded
        installButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(installButton)

        let uninstallButton = NSButton(title: "Uninstall CLI…", target: self, action: #selector(uninstallCliTapped(_:)))
        uninstallButton.bezelStyle = .rounded
        uninstallButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(uninstallButton)

        let revealButton = NSButton(title: "Reveal embedded CLI", target: self, action: #selector(revealEmbeddedCliTapped(_:)))
        revealButton.bezelStyle = .rounded
        revealButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(revealButton)

        let cliStatus = NSTextField(labelWithString: "")
        cliStatus.font = .systemFont(ofSize: 11, weight: .regular)
        cliStatus.textColor = .secondaryLabelColor
        cliStatus.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cliStatus)
        cliStatusLabel = cliStatus

        NSLayoutConstraint.activate([
            cliHeader.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            cliHeader.topAnchor.constraint(equalTo: terminalPopUp.bottomAnchor, constant: 22),

            cliPathLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            cliPathLabel.topAnchor.constraint(equalTo: cliHeader.bottomAnchor, constant: 8),
            cliPathValue.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            cliPathValue.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            cliPathValue.topAnchor.constraint(equalTo: cliPathLabel.bottomAnchor, constant: 4),

            installButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            installButton.topAnchor.constraint(equalTo: cliPathValue.bottomAnchor, constant: 10),
            uninstallButton.leadingAnchor.constraint(equalTo: installButton.trailingAnchor, constant: 12),
            uninstallButton.centerYAnchor.constraint(equalTo: installButton.centerYAnchor),
            revealButton.leadingAnchor.constraint(equalTo: uninstallButton.trailingAnchor, constant: 12),
            revealButton.centerYAnchor.constraint(equalTo: installButton.centerYAnchor),

            cliStatus.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            cliStatus.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            cliStatus.topAnchor.constraint(equalTo: installButton.bottomAnchor, constant: 8),
        ])
    }

    @objc private func openConfigTapped(_ sender: NSButton) {
        guard let path = configPath else { return }
        let url = URL(fileURLWithPath: path)
        let editor = EditorPreferences.loadPreferredEditor()
        openFile(url: url, withEditor: editor)
    }

    @objc private func chooseConfigTapped(_ sender: NSButton) {
        guard let controller = window?.windowController as? PreferencesWindowController else { return }
        if controller.chooseConfigPath() {
            // Close and reopen to rehydrate tabs with the new config.
            controller.close()
            controller.showWindow()
        }
    }

    /// Opens a file with the chosen default editor (system app, named app, or vim in terminal).
    private func openFile(url: URL, withEditor editorIdentifier: String?) {
        EditorLauncher.openFile(
            fileURL: url,
            preferredEditor: editorIdentifier,
            config: currentConfig(),
            openURL: { NSWorkspace.shared.open($0) }
        )
    }

    /// Load the latest config so editor+terminal settings stay in sync while Preferences is open.
    private func currentConfig() -> ForgeConfig? {
        guard let path = configPath else { return config }
        return (try? ForgeConfig.load(from: path)) ?? config
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            refreshEditorSelection()
        }
    }

    private func refreshEditorSelection() {
        guard let popUp = editorPopUp else { return }
        let saved = EditorPreferences.loadPreferredEditor()
        let displayTitle = EditorPreferences.displayTitle(forIdentifier: saved)
        if let idx = EditorPreferences.knownEditors.firstIndex(of: displayTitle) {
            popUp.selectItem(at: idx)
        } else {
            popUp.selectItem(at: 0)
        }
    }

    @objc private func editorPopUpChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        let id = EditorPreferences.identifier(forDisplayTitle: title)
        EditorPreferences.savePreferredEditor(id)
    }

    @objc private func taskManagerPopUpChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        let kind = TaskManagerPreferences.kind(forDisplayTitle: title)
        TaskManagerPreferences.savePreferredTaskManager(kind == .auto ? nil : kind)
    }

    /// Persist the selected terminal application into config.yaml.
    @objc private func terminalPopUpChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        let configValue = TerminalPreferences.configValue(forDisplayTitle: title)
        _ = onSaveTerminal(configValue)
    }

    @objc private func revealEmbeddedCliTapped(_ sender: Any?) {
        guard let url = ForgeCliInstaller.embeddedCliURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func installCliTapped(_ sender: Any?) {
        runCliInstallFlow(isInstall: true)
    }

    @objc private func uninstallCliTapped(_ sender: Any?) {
        runCliInstallFlow(isInstall: false)
    }

    private func runCliInstallFlow(isInstall: Bool) {
        let alert = NSAlert()
        alert.messageText = isInstall ? "Install forge CLI" : "Uninstall forge CLI"
        alert.informativeText = "Choose where to \(isInstall ? "install" : "remove") the 'forge' command."
        let targets = Array(ForgeCliInstaller.InstallTarget.allCases)
        for target in targets {
            alert.addButton(withTitle: target.title(isInstall: isInstall))
        }
        alert.addButton(withTitle: "Cancel")
        let resp = alert.runModal()

        let selectedIndex = resp.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let target = targets[safe: selectedIndex]
        guard let target else { return }

        do {
            if isInstall {
                try ForgeCliInstaller.install(to: target, allowOverwrite: false)
                showCliStatus("Installed to \(ForgeCliInstaller.destinationURL(for: target).path)", isError: false)
            } else {
                try ForgeCliInstaller.uninstall(from: target)
                showCliStatus("Removed from \(ForgeCliInstaller.destinationURL(for: target).path)", isError: false)
            }
        } catch {
            if isInstall,
               let installerError = error as? ForgeCliInstaller.InstallerError,
               case .destinationExistsButIsNotForge(let path) = installerError {
                let overwrite = NSAlert()
                overwrite.messageText = "A different 'forge' already exists"
                overwrite.informativeText = "\(path) already exists and does not appear to be Forge’s embedded CLI. Overwrite it?"
                overwrite.addButton(withTitle: "Overwrite")
                overwrite.addButton(withTitle: "Cancel")
                if overwrite.runModal() == .alertFirstButtonReturn {
                    do {
                        try ForgeCliInstaller.install(to: target, allowOverwrite: true)
                        showCliStatus("Installed to \(ForgeCliInstaller.destinationURL(for: target).path)", isError: false)
                    } catch {
                        let msg = (error as? ForgeCliInstaller.InstallerError)?.description ?? error.localizedDescription
                        showCliStatus(msg, isError: true)
                    }
                }
                return
            }
            let msg = (error as? ForgeCliInstaller.InstallerError)?.description ?? error.localizedDescription
            showCliStatus(msg, isError: true)
        }
    }

    private func showCliStatus(_ message: String, isError: Bool) {
        cliStatusLabel?.stringValue = message
        cliStatusLabel?.textColor = isError ? .systemRed : .secondaryLabelColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.cliStatusLabel?.stringValue = ""
            self?.cliStatusLabel?.textColor = .secondaryLabelColor
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

// MARK: - OmniFocus panel

private final class PreferencesOmniFocusView: NSView {
    private let configPath: String?
    private let onSave: (Bool, Bool, Bool) -> Bool
    private var enabledCheckbox: NSButton!
    private var syncOnMoveCheckbox: NSButton!
    private var syncFromOmnifocusCheckbox: NSButton!
    private var statusLabel: NSTextField!

    override var isFlipped: Bool { true }

    init(configPath: String?, config: ForgeConfig?, onSave: @escaping (Bool, Bool, Bool) -> Bool) {
        self.configPath = configPath
        self.onSave = onSave
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: "OmniFocus")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        let blurb = NSTextField(wrappingLabelWithString: """
        Optional local bridge to OmniFocus (Automation / OmniJS). When enabled, Forge can link projects and mirror kanban columns both ways. Nothing is sent to the cloud.
        """)
        blurb.font = .systemFont(ofSize: 12, weight: .regular)
        blurb.textColor = .secondaryLabelColor
        blurb.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurb)

        let enabled = NSButton(
            checkboxWithTitle: "Enable OmniFocus integration",
            target: self,
            action: #selector(togglesChanged(_:))
        )
        enabled.translatesAutoresizingMaskIntoConstraints = false
        enabled.state = (config?.omnifocus.enabled == true) ? .on : .off
        enabled.isEnabled = configPath != nil
        addSubview(enabled)
        enabledCheckbox = enabled

        let sync = NSButton(
            checkboxWithTitle: "Board moves → OmniFocus (Finder column onto linked OF tasks)",
            target: self,
            action: #selector(togglesChanged(_:))
        )
        sync.translatesAutoresizingMaskIntoConstraints = false
        sync.state = (config?.omnifocus.syncOnMove == true) ? .on : .off
        sync.isEnabled = configPath != nil && enabled.state == .on
        addSubview(sync)
        syncOnMoveCheckbox = sync

        let pull = NSButton(
            checkboxWithTitle: "OmniFocus → board on Refresh (OF column onto Finder tags)",
            target: self,
            action: #selector(togglesChanged(_:))
        )
        pull.translatesAutoresizingMaskIntoConstraints = false
        pull.state = (config?.omnifocus.syncFromOmnifocus != false) ? .on : .off
        pull.isEnabled = configPath != nil && enabled.state == .on
        addSubview(pull)
        syncFromOmnifocusCheckbox = pull

        let note = NSTextField(wrappingLabelWithString: """
        Requires OmniFocus running with Automation permission for Forge. Change a column tag in OmniFocus, then press Refresh on the board. With board moves → OmniFocus on, leaving Shipped reopens the OF project and entering Shipped marks it Done (config: reopen_of_project_when_leaving_shipped / complete_of_project_when_entering_shipped).
        """)
        note.font = .systemFont(ofSize: 11, weight: .regular)
        note.textColor = .tertiaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false
        addSubview(note)

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        addSubview(status)
        statusLabel = status

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            blurb.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            blurb.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            blurb.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),

            enabled.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            enabled.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            enabled.topAnchor.constraint(equalTo: blurb.bottomAnchor, constant: 16),

            sync.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            sync.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            sync.topAnchor.constraint(equalTo: enabled.bottomAnchor, constant: 10),

            pull.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            pull.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            pull.topAnchor.constraint(equalTo: sync.bottomAnchor, constant: 8),

            note.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            note.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            note.topAnchor.constraint(equalTo: pull.bottomAnchor, constant: 16),

            status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            status.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func togglesChanged(_ sender: NSButton) {
        let enabled = enabledCheckbox.state == .on
        syncOnMoveCheckbox.isEnabled = configPath != nil && enabled
        syncFromOmnifocusCheckbox.isEnabled = configPath != nil && enabled
        if !enabled {
            syncOnMoveCheckbox.state = .off
            syncFromOmnifocusCheckbox.state = .off
        }
        let syncOnMove = enabled && syncOnMoveCheckbox.state == .on
        let syncFromOmnifocus = enabled && syncFromOmnifocusCheckbox.state == .on
        guard configPath != nil else {
            statusLabel.stringValue = "No config.yaml loaded."
            statusLabel.textColor = .systemRed
            return
        }
        if onSave(enabled, syncOnMove, syncFromOmnifocus) {
            statusLabel.stringValue = "Saved to config.yaml."
            statusLabel.textColor = .secondaryLabelColor
        } else {
            statusLabel.stringValue = "Could not save OmniFocus settings."
            statusLabel.textColor = .systemRed
        }
    }
}

// MARK: - Reminders panel

private final class PreferencesRemindersView: NSView, NSTextFieldDelegate {
    private let configPath: String?
    private let forgeDir: String?
    private let omnifocusEnabled: Bool
    private let onSave: (Bool, String, Bool, Bool, Bool) -> Bool
    private let onRefresh: () async -> String
    private var enabledCheckbox: NSButton!
    private var syncOnMoveCheckbox: NSButton!
    private var syncFromRemindersCheckbox: NSButton!
    private var includeCompletedCheckbox: NSButton!
    private var listField: NSTextField!
    private var snapshotLabel: NSTextField!
    private var refreshButton: NSButton!
    private var warningLabel: NSTextField!
    private var statusLabel: NSTextField!

    override var isFlipped: Bool { true }

    init(
        configPath: String?,
        forgeDir: String?,
        config: ForgeConfig?,
        onSave: @escaping (Bool, String, Bool, Bool, Bool) -> Bool,
        onRefresh: @escaping () async -> String
    ) {
        self.configPath = configPath
        self.forgeDir = forgeDir
        self.omnifocusEnabled = config?.omnifocus.enabled == true
        self.onSave = onSave
        self.onRefresh = onRefresh
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: "Reminders")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        let blurb = NSTextField(wrappingLabelWithString: """
        Optional local EventKit task backend. Each Forge project folder matches a Reminders list by title; capture next actions in Reminders.app. Board Refresh and Refresh now update the snapshot, list colours from Finder columns, and sentinel priority from Finder URGENT. Create missing lists with forge reminders align --apply. An optional sentinel reminder can mirror the column. Ordinary reminder items stay unchanged. Nothing is sent to the cloud.
        """)
        blurb.font = .systemFont(ofSize: 12, weight: .regular)
        blurb.textColor = .secondaryLabelColor
        blurb.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurb)

        let enabled = NSButton(
            checkboxWithTitle: "Enable Reminders integration",
            target: self,
            action: #selector(togglesChanged(_:))
        )
        enabled.translatesAutoresizingMaskIntoConstraints = false
        enabled.state = (config?.reminders.enabled == true) ? .on : .off
        enabled.isEnabled = configPath != nil
        addSubview(enabled)
        enabledCheckbox = enabled

        let sync = NSButton(
            checkboxWithTitle: "Column mirror: board moves → sentinel reminder",
            target: self,
            action: #selector(togglesChanged(_:))
        )
        sync.translatesAutoresizingMaskIntoConstraints = false
        sync.state = (config?.reminders.syncOnMove == true) ? .on : .off
        sync.isEnabled = configPath != nil && enabled.state == .on
        addSubview(sync)
        syncOnMoveCheckbox = sync

        let pull = NSButton(
            checkboxWithTitle: "Column mirror: sentinel → Finder tags on Refresh",
            target: self,
            action: #selector(togglesChanged(_:))
        )
        pull.translatesAutoresizingMaskIntoConstraints = false
        pull.state = (config?.reminders.syncFromReminders == true) ? .on : .off
        pull.isEnabled = configPath != nil && enabled.state == .on
        addSubview(pull)
        syncFromRemindersCheckbox = pull

        let includeCompleted = NSButton(
            checkboxWithTitle: "Include completed reminders by default",
            target: self,
            action: #selector(togglesChanged(_:))
        )
        includeCompleted.translatesAutoresizingMaskIntoConstraints = false
        includeCompleted.state = (config?.reminders.includeCompleted == true) ? .on : .off
        includeCompleted.isEnabled = configPath != nil && enabled.state == .on
        addSubview(includeCompleted)
        includeCompletedCheckbox = includeCompleted

        let listLabel = NSTextField(labelWithString: "Inbox list (optional extra list, not a project unless a folder has this name)")
        listLabel.font = .systemFont(ofSize: 12, weight: .regular)
        listLabel.textColor = .secondaryLabelColor
        listLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(listLabel)

        let list = NSTextField()
        list.translatesAutoresizingMaskIntoConstraints = false
        list.placeholderString = RemindersConfig.defaultListName
        list.stringValue = config?.reminders.list ?? RemindersConfig.defaultListName
        list.isEnabled = configPath != nil
        list.delegate = self
        list.target = self
        list.action = #selector(listAction(_:))
        addSubview(list)
        listField = list

        let snapshot = NSTextField(labelWithString: snapshotText())
        snapshot.font = .systemFont(ofSize: 11, weight: .regular)
        snapshot.textColor = .secondaryLabelColor
        snapshot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(snapshot)
        snapshotLabel = snapshot

        let refresh = NSButton(
            title: "Refresh now",
            target: self,
            action: #selector(refreshSnapshot(_:))
        )
        refresh.bezelStyle = .rounded
        refresh.translatesAutoresizingMaskIntoConstraints = false
        refresh.isEnabled = configPath != nil && enabled.state == .on
        addSubview(refresh)
        refreshButton = refresh

        let warning = NSTextField(wrappingLabelWithString: omnifocusEnabled
            ? "OmniFocus is also enabled. Refresh applies OmniFocus column pull first; Reminders sentinels skip those folders."
            : "")
        warning.font = .systemFont(ofSize: 11, weight: .regular)
        warning.textColor = .systemOrange
        warning.translatesAutoresizingMaskIntoConstraints = false
        warning.isHidden = !omnifocusEnabled
        addSubview(warning)
        warningLabel = warning

        let note = NSTextField(wrappingLabelWithString: """
        Requires Reminders permission for Forge.app. Refresh now matches board Refresh: snapshot, list colours, URGENT → sentinel priority, and sentinel → Finder when that toggle is on. Background snapshot refresh does not paint. Create missing lists with forge reminders align --apply. Folder aliases, sentinel_prefix, and source stay in config.yaml. The CLI can use .cache/reminders-snapshot.json, or run forge reminders refresh after granting Terminal access.
        """)
        note.font = .systemFont(ofSize: 11, weight: .regular)
        note.textColor = .tertiaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false
        addSubview(note)

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        addSubview(status)
        statusLabel = status

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            blurb.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            blurb.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            blurb.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),

            enabled.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            enabled.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            enabled.topAnchor.constraint(equalTo: blurb.bottomAnchor, constant: 16),

            sync.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            sync.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            sync.topAnchor.constraint(equalTo: enabled.bottomAnchor, constant: 8),

            pull.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            pull.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            pull.topAnchor.constraint(equalTo: sync.bottomAnchor, constant: 8),

            includeCompleted.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            includeCompleted.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            includeCompleted.topAnchor.constraint(equalTo: pull.bottomAnchor, constant: 8),

            listLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            listLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            listLabel.topAnchor.constraint(equalTo: includeCompleted.bottomAnchor, constant: 14),

            list.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            list.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            list.topAnchor.constraint(equalTo: listLabel.bottomAnchor, constant: 4),
            list.heightAnchor.constraint(equalToConstant: 22),

            snapshot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            snapshot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            snapshot.topAnchor.constraint(equalTo: list.bottomAnchor, constant: 12),

            refresh.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            refresh.topAnchor.constraint(equalTo: snapshot.bottomAnchor, constant: 8),

            warning.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            warning.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            warning.topAnchor.constraint(equalTo: refresh.bottomAnchor, constant: 12),

            note.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            note.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            note.topAnchor.constraint(equalTo: warning.bottomAnchor, constant: 12),

            status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            status.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        persist()
    }

    @objc private func listAction(_ sender: NSTextField) {
        persist()
    }

    @objc private func togglesChanged(_ sender: NSButton) {
        let enabled = enabledCheckbox.state == .on
        syncOnMoveCheckbox.isEnabled = configPath != nil && enabled
        syncFromRemindersCheckbox.isEnabled = configPath != nil && enabled
        includeCompletedCheckbox.isEnabled = configPath != nil && enabled
        refreshButton.isEnabled = configPath != nil && enabled
        if !enabled {
            syncOnMoveCheckbox.state = .off
            syncFromRemindersCheckbox.state = .off
            includeCompletedCheckbox.state = .off
        }
        persist()
    }

    @objc private func refreshSnapshot(_ sender: NSButton) {
        refreshButton.isEnabled = false
        Task { @MainActor in
            let message = await onRefresh()
            snapshotLabel.stringValue = snapshotText()
            statusLabel.stringValue = message
            let lower = message.lowercased()
            statusLabel.textColor = (lower.contains("denied") || lower.contains("could not") || lower.contains("enable") || lower.contains("no config"))
                ? .systemRed
                : .secondaryLabelColor
            refreshButton.isEnabled = configPath != nil && enabledCheckbox.state == .on
        }
    }

    private func snapshotText() -> String {
        guard let forgeDir else { return "Snapshot: (Forge directory unknown)" }
        return RemindersSnapshotStore.statusSummary(forgeDir: forgeDir)
    }

    private func persist() {
        guard configPath != nil else {
            statusLabel.stringValue = "No config.yaml loaded."
            statusLabel.textColor = .systemRed
            return
        }
        let enabled = enabledCheckbox.state == .on
        let includeCompleted = enabled && includeCompletedCheckbox.state == .on
        let syncOnMove = enabled && syncOnMoveCheckbox.state == .on
        let syncFromReminders = enabled && syncFromRemindersCheckbox.state == .on
        let list = listField.stringValue
        if onSave(enabled, list, includeCompleted, syncOnMove, syncFromReminders) {
            statusLabel.stringValue = "Saved to config.yaml."
            statusLabel.textColor = .secondaryLabelColor
        } else {
            statusLabel.stringValue = "Could not save Reminders settings."
            statusLabel.textColor = .systemRed
        }
    }
}

// MARK: - Board panel

private final class PreferencesBoardView: NSView {
    private let metaTags: [String]
    private var filterCheckboxes: [NSButton] = []
    private let stackView = NSStackView()

    override var isFlipped: Bool { true }

    init(metaTags: [String], frame frameRect: NSRect = .zero) {
        self.metaTags = metaTags
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        let label = NSTextField(labelWithString: "Meta tags to show in board filter:")
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        stackView.orientation = .vertical
        stackView.spacing = 4
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        let saved = BoardFilterPreferences.loadEnabledMetaTags()
        let enabledSet = saved.map { Set($0) } ?? Set(metaTags)

        for tag in metaTags {
            let cb = NSButton(checkboxWithTitle: tag, target: self, action: #selector(filterCheckboxChanged(_:)))
            cb.identifier = NSUserInterfaceItemIdentifier(tag)
            cb.state = enabledSet.contains(tag) ? .on : .off
            stackView.addArrangedSubview(cb)
            filterCheckboxes.append(cb)
        }

        if metaTags.isEmpty {
            let empty = NSTextField(labelWithString: "No config loaded — add config.yaml to see meta tags.")
            empty.font = .systemFont(ofSize: 11, weight: .regular)
            empty.textColor = .tertiaryLabelColor
            stackView.addArrangedSubview(empty)
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stackView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
        ])
    }

    @objc private func filterCheckboxChanged(_ sender: NSButton) {
        let selected = filterCheckboxes.compactMap { cb -> String? in
            guard cb.state == .on, let id = cb.identifier?.rawValue else { return nil }
            return id
        }
        if selected.count == metaTags.count {
            BoardFilterPreferences.saveEnabledMetaTags(nil)
        } else {
            BoardFilterPreferences.saveEnabledMetaTags(selected)
        }
    }
}

// MARK: - Workspace panel (editable paths)

private final class PreferencesWorkspaceView: NSView {
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let configPath: String?
    private let onSave: ([String]) -> Bool
    private weak var statusLabel: NSTextField?

    override var isFlipped: Bool { true }

    init(projectRoots: [String], configPath: String?, onSave: @escaping ([String]) -> Bool) {
        self.configPath = configPath
        self.onSave = onSave
        super.init(frame: .zero)
        setupUI(projectRoots: projectRoots)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI(projectRoots: [String]) {
        let label = NSTextField(labelWithString: "Project root folders")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let prompt = NSTextField(labelWithString: "One path per line. Tilde (~) is expanded. Save writes to config.yaml.")
        prompt.font = .systemFont(ofSize: 11, weight: .regular)
        prompt.textColor = .secondaryLabelColor
        prompt.translatesAutoresizingMaskIntoConstraints = false
        addSubview(prompt)

        textView.string = projectRoots.joined(separator: "\n")
        textView.isEditable = configPath != nil
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.drawsBackground = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .lineBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let saveButton = NSButton(title: "Save to config", target: self, action: #selector(saveTapped(_:)))
        saveButton.bezelStyle = .rounded
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.isEnabled = configPath != nil
        addSubview(saveButton)

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
        self.statusLabel = statusLabel

        if configPath == nil {
            let noConfig = NSTextField(labelWithString: "No config loaded — create config.yaml to edit roots here.")
            noConfig.font = .systemFont(ofSize: 11, weight: .regular)
            noConfig.textColor = .tertiaryLabelColor
            noConfig.translatesAutoresizingMaskIntoConstraints = false
            addSubview(noConfig)
            NSLayoutConstraint.activate([
                noConfig.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
                noConfig.topAnchor.constraint(equalTo: prompt.bottomAnchor, constant: 8),
            ])
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            prompt.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            prompt.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: prompt.bottomAnchor, constant: 12),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            saveButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            saveButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            saveButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            statusLabel.leadingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
        ])
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    @objc private func saveTapped(_ sender: NSButton) {
        let text = textView.string
        let newRoots = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if onSave(newRoots) {
            statusLabel?.stringValue = "Saved."
            statusLabel?.textColor = .secondaryLabelColor
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.statusLabel?.stringValue = ""
            }
        } else {
            statusLabel?.stringValue = "Save failed."
            statusLabel?.textColor = .systemRed
        }
    }
}

// MARK: - Shortcuts panel

private final class PreferencesShortcutsView: NSView {
    override var isFlipped: Bool { true }

    private let stackView = NSStackView()
    private var recordingFor: ShortcutPreferences.Identifier?
    private var localMonitor: Any?
    private var rowViews: [ShortcutPreferences.Identifier: ShortcutRowView] = [:]
    private weak var accessibilityLabel: NSTextField?
    private weak var openAccessibilityButton: NSButton?

    init() {
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        let label = NSTextField(labelWithString: "Keyboard shortcuts")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let sub = NSTextField(labelWithString: "Click \"Change…\" then press the keys you want.")
        sub.font = .systemFont(ofSize: 11, weight: .regular)
        sub.textColor = .secondaryLabelColor
        sub.maximumNumberOfLines = 2
        sub.lineBreakMode = .byWordWrapping
        sub.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sub)

        let headerAction = NSTextField(labelWithString: "Action")
        headerAction.font = .systemFont(ofSize: 11, weight: .semibold)
        headerAction.textColor = .secondaryLabelColor
        headerAction.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerAction)

        let headerShortcut = NSTextField(labelWithString: "Shortcut")
        headerShortcut.font = .systemFont(ofSize: 11, weight: .semibold)
        headerShortcut.textColor = .secondaryLabelColor
        headerShortcut.alignment = .right
        headerShortcut.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerShortcut)

        stackView.orientation = .vertical
        stackView.spacing = 6
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        for id in ShortcutPreferences.Identifier.allCases {
            let row = ShortcutRowView(
                label: ShortcutPreferences.label(for: id),
                shortcutDisplay: ShortcutPreferences.displayString(for: ShortcutPreferences.spec(for: id)),
                onChange: { [weak self] in self?.startRecording(for: id) }
            )
            stackView.addArrangedSubview(row)
            rowViews[id] = row
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            sub.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            sub.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            sub.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            headerAction.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            headerAction.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 16),
            headerShortcut.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20 + 220 + 12),
            headerShortcut.centerYAnchor.constraint(equalTo: headerAction.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: headerAction.bottomAnchor, constant: 6),
        ])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
    }

    private func startRecording(for id: ShortcutPreferences.Identifier) {
        guard recordingFor == nil else { return }
        recordingFor = id
        rowViews[id]?.setRecording(true)

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let id = self.recordingFor else { return event }
            if event.keyCode == 53 {
                self.cancelRecording(for: id)
                return nil
            }
            let key = event.charactersIgnoringModifiers ?? ""
            let spec = ShortcutPreferences.Spec(
                keyEquivalent: key,
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            )
            ShortcutPreferences.set(id, spec: spec)
            self.rowViews[id]?.setShortcutDisplay(ShortcutPreferences.displayString(for: spec))
            self.finishRecording(for: id)
            return nil
        }
    }

    private func finishRecording(for id: ShortcutPreferences.Identifier) {
        if let mon = localMonitor {
            NSEvent.removeMonitor(mon)
            localMonitor = nil
        }
        recordingFor = nil
        rowViews[id]?.setRecording(false)
    }

    private func cancelRecording(for id: ShortcutPreferences.Identifier) {
        if let mon = localMonitor {
            NSEvent.removeMonitor(mon)
            localMonitor = nil
        }
        recordingFor = nil
        rowViews[id]?.setRecording(false)
        rowViews[id]?.setShortcutDisplay(ShortcutPreferences.displayString(for: ShortcutPreferences.spec(for: id)))
    }

}

private final class ShortcutRowView: NSView {
    private let labelField: NSTextField
    private let shortcutField: NSTextField
    private let changeButton: NSButton
    private let onChange: () -> Void

    init(label: String, shortcutDisplay: String, onChange: @escaping () -> Void) {
        self.onChange = onChange
        labelField = NSTextField(labelWithString: label)
        labelField.font = .systemFont(ofSize: 12, weight: .regular)
        labelField.translatesAutoresizingMaskIntoConstraints = false

        shortcutField = NSTextField(labelWithString: shortcutDisplay)
        shortcutField.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        shortcutField.alignment = .right
        shortcutField.translatesAutoresizingMaskIntoConstraints = false

        changeButton = NSButton(title: "Change…", target: nil, action: nil)
        changeButton.bezelStyle = .rounded
        changeButton.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)
        addSubview(shortcutField)
        addSubview(changeButton)
        changeButton.target = self
        changeButton.action = #selector(changeTapped(_:))

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.widthAnchor.constraint(equalToConstant: 220),
            shortcutField.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 12),
            shortcutField.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutField.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            changeButton.leadingAnchor.constraint(equalTo: shortcutField.trailingAnchor, constant: 12),
            changeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            changeButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func changeTapped(_ sender: NSButton) {
        onChange()
    }

    func setShortcutDisplay(_ s: String) {
        shortcutField.stringValue = s
    }

    func setRecording(_ recording: Bool) {
        if recording {
            changeButton.title = "Press shortcut…"
            shortcutField.stringValue = "…"
        } else {
            changeButton.title = "Change…"
        }
    }
}
