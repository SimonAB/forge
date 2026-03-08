import AppKit
import ApplicationServices
import ForgeCore

/// Preferences window with tabbed panels: General, Board, Workspace.
final class PreferencesWindowController: NSWindowController {

    static let windowTitle = "Preferences"
    private static let configCandidates: [String] = {
        let home = NSHomeDirectory()
        return [
            (home as NSString).appendingPathComponent("Documents/Forge/config.yaml"),
            (home as NSString).appendingPathComponent("Documents/Work/Projects/Forge/config.yaml"),
        ]
    }()

    private var configPath: String?
    private var config: ForgeConfig?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.windowTitle
        window.center()
        super.init(window: window)

        loadConfig()

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false

        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = "General"
        generalItem.view = PreferencesGeneralView(configPath: configPath, config: config)
        tabView.addTabViewItem(generalItem)

        let boardItem = NSTabViewItem(identifier: "board")
        boardItem.label = "Board"
        boardItem.view = PreferencesBoardView(metaTags: config?.board.metaTags ?? [])
        tabView.addTabViewItem(boardItem)

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

        window.contentView = tabView
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            tabView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])
    }

    private func loadConfig() {
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
        let updated = ForgeConfig(
            projectRoots: newRoots,
            board: current.board,
            gtd: current.gtd,
            workspaceTags: current.workspaceTags,
            projectAreas: current.projectAreas,
            terminal: current.terminal,
            projectTag: current.projectTag
        )
        do {
            try updated.save(to: path)
            config = updated
            return true
        } catch {
            return false
        }
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
    private let configPath: String?
    private let config: ForgeConfig?

    override var isFlipped: Bool { true }

    init(configPath: String?, config: ForgeConfig?) {
        self.configPath = configPath
        self.config = config
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: "General")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let sub = NSTextField(labelWithString: "More options will appear here.")
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
        let editTasksButton = NSButton(title: "Edit task files", target: self, action: #selector(editTaskFilesTapped(_:)))
        editTasksButton.bezelStyle = .rounded
        editTasksButton.translatesAutoresizingMaskIntoConstraints = false
        editTasksButton.isEnabled = configPath != nil
        editTasksButton.toolTip = "Open inbox, area files, and someday list in your default editor"
        addSubview(editTasksButton)
        NSLayoutConstraint.activate([
            openConfigButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            openConfigButton.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 16),
            editTasksButton.leadingAnchor.constraint(equalTo: openConfigButton.trailingAnchor, constant: 12),
            editTasksButton.centerYAnchor.constraint(equalTo: openConfigButton.centerYAnchor),
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
    }

    @objc private func openConfigTapped(_ sender: NSButton) {
        guard let path = configPath else { return }
        let url = URL(fileURLWithPath: path)
        let editor = EditorPreferences.loadPreferredEditor()
        openFile(url: url, withEditor: editor)
    }

    @objc private func editTaskFilesTapped(_ sender: NSButton) {
        guard let path = configPath, let config = config else { return }
        let forgeDir = (path as NSString).deletingLastPathComponent
        let taskFilesRoot = ForgePaths(forgeDir: forgeDir).taskFilesRoot
        let url = URL(fileURLWithPath: taskFilesRoot)
        let editor = EditorPreferences.loadPreferredEditor()
        openFolder(url: url, path: taskFilesRoot, withEditor: editor, config: config)
    }

    /// Opens a folder with the chosen default editor (Finder, named app, or vim in terminal).
    private func openFolder(url: URL, path: String, withEditor editorIdentifier: String?, config: ForgeConfig) {
        if editorIdentifier == nil || editorIdentifier == "default" || editorIdentifier?.isEmpty == true {
            NSWorkspace.shared.open(url)
            return
        }
        switch editorIdentifier! {
        case "Vim (in default terminal)":
            let launcher = TerminalLauncher(config: config, terminalOverride: nil, openURL: { NSWorkspace.shared.open($0) })
            let escaped = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            launcher.run("zsh -i -c 'vim \"\(escaped)\"'", workingDirectory: path)
        case "Cursor", "Visual Studio Code", "TextEdit", "Sublime Text":
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", editorIdentifier!, path]
            process.qualityOfService = .userInitiated
            try? process.run()
        default:
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens a file with the chosen default editor (system app, named app, or vim in terminal).
    private func openFile(url: URL, withEditor editorIdentifier: String?) {
        let path = url.path
        if editorIdentifier == nil || editorIdentifier == "default" || editorIdentifier?.isEmpty == true {
            NSWorkspace.shared.open(url)
            return
        }
        switch editorIdentifier! {
        case "Vim (in default terminal)":
            guard let config = config else {
                NSWorkspace.shared.open(url)
                return
            }
            let dir = (path as NSString).deletingLastPathComponent
            // Use Auto terminal
            let launcher = TerminalLauncher(config: config, terminalOverride: nil, openURL: { NSWorkspace.shared.open($0) })
            let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
            launcher.run("zsh -i -c 'vim \"\(escaped)\"'", workingDirectory: dir)
        case "Cursor", "Visual Studio Code", "TextEdit", "Sublime Text":
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", editorIdentifier!, path]
            process.qualityOfService = .userInitiated
            try? process.run()
        default:
            NSWorkspace.shared.open(url)
        }
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

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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
        textView.textContainer?.containerSize = NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
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
            scrollView.heightAnchor.constraint(equalToConstant: 180),
            saveButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            saveButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
        ])
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

        let sub = NSTextField(labelWithString: "Click \"Change…\" then press the keys you want. Requires Accessibility permission for Capture Selection when another app is frontmost.")
        sub.font = .systemFont(ofSize: 11, weight: .regular)
        sub.textColor = .secondaryLabelColor
        sub.maximumNumberOfLines = 2
        sub.lineBreakMode = .byWordWrapping
        sub.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sub)

        stackView.orientation = .vertical
        stackView.spacing = 8
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

        let accessibilityLabel = NSTextField(labelWithString: "Capture Selection when another app (e.g. Finder, Mail) is active requires Accessibility permission.")
        accessibilityLabel.font = .systemFont(ofSize: 11, weight: .regular)
        accessibilityLabel.textColor = .secondaryLabelColor
        accessibilityLabel.maximumNumberOfLines = 4
        accessibilityLabel.lineBreakMode = .byWordWrapping
        accessibilityLabel.cell?.truncatesLastVisibleLine = false
        accessibilityLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accessibilityLabel)
        self.accessibilityLabel = accessibilityLabel

        let openAccessibilityButton = NSButton(title: "Open System Settings (Accessibility)", target: self, action: #selector(openAccessibilitySettings(_:)))
        openAccessibilityButton.bezelStyle = .rounded
        openAccessibilityButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(openAccessibilityButton)
        self.openAccessibilityButton = openAccessibilityButton

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            sub.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            sub.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            sub.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 16),
            accessibilityLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            accessibilityLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            accessibilityLabel.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 20),
            openAccessibilityButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            openAccessibilityButton.topAnchor.constraint(equalTo: accessibilityLabel.bottomAnchor, constant: 8),
        ])
        updateAccessibilityStatus()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateAccessibilityStatus()
        }
    }

    private func updateAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        let name = ProcessInfo.processInfo.processName
        if trusted {
            accessibilityLabel?.stringValue = "Capture Selection in other apps: Accessibility is allowed. The shortcut should work when Finder or Mail is frontmost."
            accessibilityLabel?.textColor = .secondaryLabelColor
        } else {
            accessibilityLabel?.stringValue = "Capture Selection in other apps: not allowed for this run. The running app (\"\(name)\") must be in the list and enabled. If Forge.app is already ON, turn it OFF then ON again to re-grant for the current build."
            accessibilityLabel?.textColor = .systemOrange
        }
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

    @objc private func openAccessibilitySettings(_ sender: Any?) {
        let optionPrompt = "AXTrustedCheckOptionPrompt" as CFString
        let options = [optionPrompt: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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
