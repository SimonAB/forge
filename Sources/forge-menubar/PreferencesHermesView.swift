import AppKit
import ForgeCore

/// Preferences tab for Hermes + Ollama local assistant setup (privacy-first).
@MainActor
final class PreferencesHermesView: NSView {
    private let configPath: String?
    private let config: ForgeConfig?

    private var statusStack: NSStackView?
    private var summaryLabel: NSTextField?
    private var checkButton: NSButton?

    init(configPath: String?, config: ForgeConfig?) {
        self.configPath = configPath
        self.config = config
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            Task { await refreshStatus() }
        }
    }

    private var forgeHome: String? {
        guard let configPath else { return nil }
        return (configPath as NSString).deletingLastPathComponent
    }

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            root.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
        ])

        let title = NSTextField(labelWithString: "Hermes (local assistant)")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        root.addArrangedSubview(title)

        let privacy = NSTextField(wrappingLabelWithString:
            "Privacy-first: Hermes uses local Ollama on this Mac. Board and calendar context stay on your machine when inference is loopback-only. Keep fallback_providers empty in ~/.hermes/config.yaml for strict local-only use."
        )
        privacy.textColor = .secondaryLabelColor
        privacy.maximumNumberOfLines = 0
        root.addArrangedSubview(privacy)

        let blurb = NSTextField(wrappingLabelWithString:
            "Recommended for interactive kanban work with the bundled forge-board skill. In-app Brief (previous tab) uses Ollama directly for quick summaries."
        )
        blurb.textColor = .secondaryLabelColor
        blurb.maximumNumberOfLines = 0
        root.addArrangedSubview(blurb)

        let summary = NSTextField(labelWithString: "Checking setup…")
        summary.textColor = .secondaryLabelColor
        summary.maximumNumberOfLines = 0
        summaryLabel = summary
        root.addArrangedSubview(summary)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        statusStack = stack
        root.addArrangedSubview(stack)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 8

        let check = NSButton(title: "Check setup", target: self, action: #selector(checkTapped))
        checkButton = check
        actions.addArrangedSubview(check)

        let runSetup = NSButton(title: "Run setup in Terminal", target: self, action: #selector(runSetupTapped))
        actions.addArrangedSubview(runSetup)

        let openGuide = NSButton(title: "Open guide", target: self, action: #selector(openGuideTapped))
        actions.addArrangedSubview(openGuide)

        let copyStart = NSButton(title: "Copy start command", target: self, action: #selector(copyStartTapped))
        actions.addArrangedSubview(copyStart)

        root.addArrangedSubview(actions)

        if forgeHome == nil {
            let note = NSTextField(labelWithString: "Load config.yaml to detect your Forge home for setup checks.")
            note.textColor = .tertiaryLabelColor
            root.addArrangedSubview(note)
        }
    }

    @objc private func checkTapped() {
        Task { await refreshStatus() }
    }

    @objc private func runSetupTapped() {
        guard let home = forgeHome, let config else { return }
        let cmd = "python3 \"\(home)/scripts/setup-hermes-forge.py\" --forge-home \"\(home)\""
        let launcher = TerminalLauncher(config: config, openURL: { NSWorkspace.shared.open($0) })
        launcher.run(cmd, workingDirectory: home)
    }

    @objc private func openGuideTapped() {
        guard let home = forgeHome else { return }
        let guide = (home as NSString).appendingPathComponent("docs/hermes.md")
        let url = URL(fileURLWithPath: guide)
        guard FileManager.default.fileExists(atPath: guide) else {
            summaryLabel?.stringValue = "Guide not found at docs/hermes.md"
            summaryLabel?.textColor = .systemRed
            return
        }
        let editor = EditorPreferences.loadPreferredEditor()
        EditorLauncher.openFile(
            fileURL: url,
            preferredEditor: editor,
            config: config,
            openURL: { NSWorkspace.shared.open($0) }
        )
    }

    @objc private func copyStartTapped() {
        guard let home = forgeHome else { return }
        let text = "cd \"\(home)\" && hermes\n/skill:forge-board"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        summaryLabel?.stringValue = "Copied start command to clipboard."
        summaryLabel?.textColor = .secondaryLabelColor
    }

    private func refreshStatus() async {
        checkButton?.isEnabled = false
        summaryLabel?.stringValue = "Checking setup…"
        summaryLabel?.textColor = .secondaryLabelColor
        statusStack?.arrangedSubviews.forEach { v in
            statusStack?.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        let home = forgeHome ?? HermesPaths.defaultForgeHome
        let probe = HermesSetupProbe(options: .init(forgeHome: home))
        let status = await probe.probe()

        for check in status.checks {
            let mark = check.passed ? "✓" : "✗"
            let row = NSTextField(labelWithString: "\(mark) \(check.label) — \(check.detail)")
            row.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            row.textColor = check.passed ? .secondaryLabelColor : .systemRed
            row.lineBreakMode = .byTruncatingMiddle
            statusStack?.addArrangedSubview(row)
        }

        if status.isReady {
            summaryLabel?.stringValue = "Ready — run hermes and /skill:forge-board in your Forge directory."
            summaryLabel?.textColor = .systemGreen
        } else {
            summaryLabel?.stringValue = "Setup incomplete — use Run setup in Terminal or see docs/hermes.md."
            summaryLabel?.textColor = .systemOrange
        }
        checkButton?.isEnabled = true
    }
}
