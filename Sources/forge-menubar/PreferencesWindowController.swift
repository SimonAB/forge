import AppKit
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
        generalItem.view = PreferencesGeneralView()
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
    override var isFlipped: Bool { true }

    init() {
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
